import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/chord_library.dart';
import 'cifraclub_driver.dart';
import 'cifraclub_failure_banner.dart';
import 'cifraclub_import.dart';
import 'cifraclub_urls.dart';
import 'text_import_page.dart';

/// Cifra Club 搜索源页(工单 17,GLOSSARY「搜索源」):WebView 站内搜索
/// → 浏览到曲谱页 → 从 DOM 提取内嵌和弦数据 → 转文本谱 → 走 16 的
/// 校验入库管线。导入编排(ukulele 优先/令牌/就绪重试)在
/// cifraclub_import.dart(工单 27 提出,搜索页共用)。
///
/// 一切提取只在 WebView 里发生(ADR-0002/调研:站点 Akamai 反爬,禁止
/// 服务端直连)。导入钮只在曲谱页形状的 URL 上出现;提取失败(结构变化/
/// 被拦/没和弦)给可读失败态,不崩溃,文本导入始终是退路。
class CifraClubPage extends ConsumerStatefulWidget {
  const CifraClubPage({super.key});

  @override
  ConsumerState<CifraClubPage> createState() => _CifraClubPageState();
}

class _CifraClubPageState extends ConsumerState<CifraClubPage> {
  late final WebViewController _controller;
  late final CifraClubImporter _importer;

  Uri? _currentUrl;

  /// 提取失败的可读原因(null = 没失败)。换页即清。
  String? _failure;

  /// 站点页面加载进度(0-100,中文状态条的数据源)。
  var _progress = 100;

  var _importing = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => NavigationDecision.navigate,
          // 回调全部先查 mounted:离开页面后 WebView 回调仍会到达,
          // 对已卸载的 State setState 会抛错(审计 2026-10-16 #28)。
          onUrlChange:
              (change) {
                if (!mounted) return;
                setState(() {
                  final url = change.url;
                  if (url != null) _currentUrl = Uri.tryParse(url);
                  _failure = null;
                  // 机检时「WebView 现在在哪页」从截图/树里都看不见——
                  // debug 构建留痕,release 零输出。
                  if (kDebugMode) {
                    debugPrint('CifraClub url: ${url ?? '<null>'}');
                  }
                });
              },
          onProgress:
              (value) {
                if (!mounted) return;
                setState(() {
                  _progress = value;
                });
              },
          onPageFinished: (_) => _importer.notePageFinished(),
        ),
      )
      ..loadRequest(CifraClubUrls.home);
    _importer = CifraClubImporter(WebViewDriver(_controller));
  }

  bool get _onSongPage {
    final url = _currentUrl;
    return url != null && CifraClubUrls.isSongPage(url);
  }

  /// 搜索框提交:像链接的直接加载(粘贴链接导入,含 /ukulele/ 乐器版),
  /// 关键词走站内搜索。导入钮仍由 isSongPage 把关,只在曲谱页出现。
  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final link = CifraClubUrls.linkOrNull(q);
    await _controller.loadRequest(link ?? CifraClubUrls.search(q));
  }

  /// 导入此谱:编排走 [CifraClubImporter](ukulele 优先+回退告知,
  /// 同一校验层 ADR-0006——预填进文本导入页,过了校验才谈入库)。
  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _failure = null;
    });
    try {
      final outcome = await _importer.importSong(
        _currentUrl!, // 导入钮只在 _onSongPage(非 null)时出现
        allowedChords: (await ref.read(chordLibraryProvider.future)).labels,
      );
      if (!mounted) return;
      switch (outcome) {
        case CifraImportOk(:final source, :final notice):
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  TextImportPage(initialSource: source, notice: notice),
            ),
          );
        case CifraImportFail(:final message):
          setState(() => _failure = message);
      }
    } catch (error) {
      // importSong 不抛,但和弦库加载会(17 原页面级 catch 的下家)。
      if (mounted) setState(() => _failure = importCatchCopy(error));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cifra Club')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              key: const Key('cifraclub-search'),
              hintText: '站内搜歌,如:beat it',
              onSubmitted: _search,
            ),
          ),
          _StatusLine(progress: _progress, onSongPage: _onSongPage),
          Expanded(child: WebViewWidget(controller: _controller)),
          if (_failure != null) FailureBanner(message: _failure!),
          if (_onSongPage || _importing)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  key: const Key('cifraclub-import'),
                  onPressed: _importing ? null : _import,
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('导入此谱'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 中文状态条(用户反馈:站点是葡语,「无法确定是不是完成了」)——
/// 加载进度 + 三态提示,让「做到哪一步」不依赖读站点语言:
/// 加载中→进度条+「正在加载」;非曲谱页→教下一步(点歌名);
/// 曲谱页→「就是这页,点下方导入」。
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.progress, required this.onSongPage});

  final int progress;
  final bool onSongPage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loading = progress < 100;
    final hint = loading
        ? '正在加载…'
        : onSongPage
        ? '这页就是曲谱,点下方「导入此谱」'
        : '在页面里点开一首歌(点大字歌名),再点下方「导入此谱」';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 2,
          child:
              loading
                  ? LinearProgressIndicator(value: progress / 100)
                  : const SizedBox.shrink(),
        ),
        Container(
          width: double.infinity,
          color: scheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(
                loading
                    ? Icons.hourglass_top
                    : onSongPage
                    ? Icons.check_circle_outline
                    : Icons.touch_app_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
