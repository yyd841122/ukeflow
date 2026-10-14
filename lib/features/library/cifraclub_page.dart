import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/chart/cifra_extract.dart';
import '../../data/chord_library.dart';
import 'cifraclub_extract_js.dart';
import 'cifraclub_urls.dart';
import 'text_import_page.dart';

/// Cifra Club 搜索源页(工单 17,GLOSSARY「搜索源」):WebView 站内搜索
/// → 浏览到曲谱页 → 从 DOM 提取内嵌和弦数据 → 转文本谱 → 走 16 的
/// 校验入库管线。
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

  Uri? _currentUrl;

  /// 提取失败的可读原因(null = 没失败)。换页即清。
  String? _failure;

  var _importing = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => NavigationDecision.navigate,
          onUrlChange:
              (change) => setState(() {
                final url = change.url;
                if (url != null) _currentUrl = Uri.tryParse(url);
                _failure = null;
              }),
        ),
      )
      ..loadRequest(CifraClubUrls.home);
  }

  bool get _onSongPage {
    final url = _currentUrl;
    return url != null && CifraClubUrls.isSongPage(url);
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    await _controller.loadRequest(CifraClubUrls.search(q));
  }

  /// 提取 → 转文本谱 → 进 16 的校验入库管线(预填直达报告)。
  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _failure = null;
    });
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        cifraExtractScript,
      );
      final failureText = _readableFailure(raw);
      if (failureText != null) {
        setState(() => _failure = failureText);
        return;
      }
      final payload = decodeCifraPayload(raw);
      if (payload == null) {
        setState(() => _failure = _failureCopy('no-content'));
        return;
      }
      final library = await ref.read(chordLibraryProvider.future);
      if (!mounted) return;
      final source = buildChordPro(payload, allowedChords: library.labels);
      // 同一校验层(ADR-0006):预填进文本导入页,过了校验才谈入库。
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TextImportPage(initialSource: source),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _failure = '提取失败,请重试;若反复出现请回曲库用文本导入。'
              '(技术细节:$error)',
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// JS 返回值里的失败码 → 可读文案;不是失败形状则 null。
  String? _readableFailure(Object? raw) {
    final code = cifraExtractError(raw);
    if (code == null) return null;
    return _failureCopy(code);
  }

  String _failureCopy(String code) {
    if (code.startsWith('exception:')) return '页内脚本出错($code),请重试';
    return switch (code) {
      'no-content' => '没认出谱面内容——页面可能没加载完,或站点改版了。'
          '稍等重试,或回曲库用文本导入。',
      'no-chords' => '这个页面没提取到和弦——可能不是曲谱页。'
          '也可以回曲库用文本导入。',
      _ => '提取失败($code),请重试或用文本导入。',
    };
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
          Expanded(child: WebViewWidget(controller: _controller)),
          if (_failure != null) _FailureBanner(message: _failure!),
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

/// 提取失败的可见横幅:原文直接展示,指路文本导入(与曲库错误同一哲学)。
class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
