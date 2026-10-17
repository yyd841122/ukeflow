import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/chord_library.dart';
import 'cifraclub_driver.dart';
import 'cifraclub_import.dart';
import 'cifraclub_failure_banner.dart';
import 'cifraclub_page.dart' show CifraClubPage;
import 'cifraclub_search.dart';
import 'cifraclub_urls.dart';
import 'text_import_page.dart';

/// Cifra Club 原生搜索页(工单 27,GLOSSARY「搜索源」):输歌名 → 页内
/// fetch 站点搜索端点(真机逆向 2026-10-17:solr JSON,CORS 全开;搜索
/// 不导航)→ 原生中文列表(歌名+艺人)→ 点结果直达 17 的 ukulele-first
/// 导入管线。
///
/// 纪律同 17:一切提取只在 WebView 里发生(ADR-0002——WebView 常驻
/// 站点首页,搜索/导入都发生在它里面);SPA 层被原生层整面盖住,列表页
/// 不暴露站点葡语 UI;失败/零结果给可读中文空态,不崩,文本导入与
/// 「浏览原站」始终是退路。
class CifraClubSearchPage extends ConsumerStatefulWidget {
  const CifraClubSearchPage({super.key});

  @override
  ConsumerState<CifraClubSearchPage> createState() =>
      _CifraClubSearchPageState();
}

class _CifraClubSearchPageState extends ConsumerState<CifraClubSearchPage> {
  late final WebViewController _controller;
  late final CifraClubImporter _importer;
  late final CifraClubSearcher _searcher;

  /// 搜索视图状态(idle/搜索中/命中/零结果/失败)。
  _SearchView _view = const _IdleView();

  /// 正在导入的结果行(导入中禁点,底部显示进度)。
  CifraSearchHit? _importing;

  /// 导入失败的可读文案(null = 没失败)。
  String? _failure;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => NavigationDecision.navigate,
          onUrlChange:
              (change) {
                // 机检时「WebView 现在在哪页」从截图/树里都看不见——
                // debug 构建留痕,release 零输出。导入会把 WebView 从
                // 首页导去曲谱页,这条留痕对机检核对走位很关键。
                if (!mounted || !kDebugMode) return;
                debugPrint('CifraClubSearch url: ${change.url}');
              },
          onPageFinished: (_) => _importer.notePageFinished(),
        ),
      )
      ..loadRequest(CifraClubUrls.home);
    final driver = WebViewDriver(_controller);
    _importer = CifraClubImporter(driver);
    _searcher = CifraClubSearcher(driver);
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    setState(() {
      _view = const _SearchingView();
      _failure = null;
    });
    final outcome = await _searcher.search(query);
    if (!mounted) return;
    switch (outcome) {
      case CifraSearchSuccess(:final hits):
        setState(() => _view = _ResultsView(query: query, hits: hits));
      case CifraSearchEmpty():
        setState(() => _view = _EmptyView(query: query));
      case CifraSearchFailure(:final code):
        // superseded = 用户已发起新搜索,别把旧搜索的失败画上去。
        if (code == 'superseded') return;
        setState(() => _view = _FailureView(query: query));
    }
  }

  /// 点结果 → 直达导入:同一 [CifraClubImporter](17 管线,ukulele 优先
  /// +无该版回退告知)。结果链接是站内路径,拼回域名交给管线;导入会把
  /// WebView 从首页导去曲谱页(搜索不受影响:页内 fetch 任何站点页上都成立)。
  Future<void> _importHit(CifraSearchHit hit) async {
    if (_importing != null) return;
    setState(() {
      _importing = hit;
      _failure = null;
    });
    try {
      final songUrl = CifraClubUrls.home.resolve(hit.path);
      final outcome = await _importer.importSong(
        songUrl,
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
      // importSong 不抛,但和弦库加载会(与 17 页同一兜底,下家补齐)。
      if (mounted) setState(() => _failure = importCatchCopy(error));
    } finally {
      if (mounted) setState(() => _importing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜谱'),
        actions: [
          // 站点改版/搜索失效时的退路:原站 WebView 手动浏览(17 页)。
          IconButton(
            key: const Key('cifraclub-search-browser'),
            tooltip: '浏览原站',
            icon: const Icon(Icons.language),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CifraClubPage()),
            ),
          ),
        ],
      ),
      // Stack:WebView 常驻底层(搜索的 fetch 与导入的导航都发生在它里
      // 面)。原生层整面盖住之外,WebView 还要 IgnorePointer(不挡的话
      // 点「空白区」会穿透到隐形的站点链接——ColoredBox 不吸收指针)+
      // ExcludeSemantics(不挡的话葡语内容全进 a11y 树:读屏可逛到
      // 隐形页面,机检 dump 也被污染——真机机检逮到)。
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Theme.of(context).colorScheme.surface),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SearchBar(
                    key: const Key('cifraclub-search-field'),
                    hintText: '搜歌名,如:beat it',
                    onSubmitted: _importing == null ? _search : null,
                  ),
                ),
                if (_view is _SearchingView)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('正在搜索…'),
                      ],
                    ),
                  )
                else
                  Expanded(child: _buildView(context)),
                if (_importing != null) const _ImportingLine(),
                if (_failure != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: FailureBanner(message: _failure!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (_view) {
      case _SearchingView():
        return const SizedBox.shrink(); // 外层已画搜索中转圈
      case _IdleView():
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '输入歌名,在 Cifra Club 里搜谱。\n点结果直接导入,不用进网站。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        );
      case _ResultsView(:final query, :final hits):
        return ListView.separated(
          key: Key('cifraclub-search-results-$query'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: hits.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final hit = hits[i];
            return Card(
              key: Key('cifraclub-search-hit-$i'),
              margin: EdgeInsets.zero,
              child: ListTile(
                title: Text(hit.title),
                subtitle: hit.artist == null ? null : Text(hit.artist!),
                onTap: _importing == null ? () => _importHit(hit) : null,
              ),
            );
          },
        );
      case _EmptyView(:final query):
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '没有找到「$query」。\n换个歌名试试,或回曲库用文本导入。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        );
      case _FailureView(:final query):
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '搜索「$query」失败——站点可能没响应或改版了。\n'
              '稍等重试;也可以点右上角进原站手动找,或回曲库用文本导入。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        );
    }
  }
}

// —— 搜索视图状态(封闭小计型,页面私有) ——

sealed class _SearchView {
  const _SearchView();
}

class _IdleView extends _SearchView {
  const _IdleView();
}

class _SearchingView extends _SearchView {
  const _SearchingView();
}

class _ResultsView extends _SearchView {
  const _ResultsView({required this.query, required this.hits});

  final String query;
  final List<CifraSearchHit> hits;
}

class _EmptyView extends _SearchView {
  const _EmptyView({required this.query});

  final String query;
}

class _FailureView extends _SearchView {
  const _FailureView({required this.query});

  final String query;
}

/// 导入进行中的可见反馈(中文,整行)。
class _ImportingLine extends StatelessWidget {
  const _ImportingLine();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '正在导入(优先找 Ukulele 版)…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
