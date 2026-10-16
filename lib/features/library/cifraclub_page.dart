import 'dart:async';

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

  /// 页面加载完成的一次性等待点(_navigateAndExtract 用)。
  Completer<void>? _pageWaiter;

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
          onUrlChange:
              (change) => setState(() {
                final url = change.url;
                if (url != null) _currentUrl = Uri.tryParse(url);
                _failure = null;
              }),
          onProgress:
              (value) => setState(() {
                _progress = value;
              }),
          onPageFinished: (_) {
            final waiter = _pageWaiter;
            _pageWaiter = null;
            waiter?.complete();
          },
        ),
      )
      ..loadRequest(CifraClubUrls.home);
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

  /// 导入此谱(**ukulele 优先**,用户反馈:版本管理不该甩给用户):
  /// 当前是两段标准曲谱页时先载 `/ukulele/` 变体提取;没有该版
  /// (站点 404 壳/无和弦)自动回退原版,并在导入页中文告知「已按
  /// 原版导入」。提取→转文本谱→进 16 的校验入库管线(预填直达报告)。
  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _failure = null;
    });
    try {
      final current = _currentUrl;
      final uke = current == null ? null : CifraClubUrls.ukuleleVariant(current);
      String? notice;
      var raw = uke == null
          ? await _controller.runJavaScriptReturningResult(cifraExtractScript)
          : null;
      if (uke != null) {
        final ukeRaw = await _navigateAndExtract(uke);
        if (_readableFailure(ukeRaw) == null &&
            decodeCifraPayload(ukeRaw) != null) {
          raw = ukeRaw;
        } else {
          // 没有 ukulele 版(404 壳/页面无谱):回退原版,告知用户。
          notice = '站点没有这首的 Ukulele 转谱,已按原版导入。'
              '和弦名通用,尤克里里照常可练;原谱中的六线谱段已过滤。';
          raw = await _navigateAndExtract(current!);
        }
      }

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
          builder: (_) =>
              TextImportPage(initialSource: source, notice: notice),
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

  /// 载入 [url] 等页面完成(15s 兜底),然后就绪重试提取。
  Future<Object?> _navigateAndExtract(Uri url) async {
    final waiter = Completer<void>();
    _pageWaiter = waiter;
    await _controller.loadRequest(url);
    await waiter.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {},
    );
    return _extractWhenReady();
  }

  /// 就绪重试:onPageFinished 可能早于 DOM 可用(真机实证——导航后
  /// 0.5s 即触发,提取落空拿到错误 JSON)。pre 是服务端渲染,页面就位
  /// 即可取,提取失败按 1.5s 间隔重取,总窗约 10s。
  Future<Object?> _extractWhenReady() async {
    Object? raw;
    for (var attempt = 0; attempt < 6; attempt++) {
      raw = await _controller.runJavaScriptReturningResult(
        cifraExtractScript,
      );
      final ready =
          _readableFailure(raw) == null && decodeCifraPayload(raw) != null;
      if (ready) return raw;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return raw;
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
          _StatusLine(progress: _progress, onSongPage: _onSongPage),
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
