/// Cifra Club 搜索编排与结果解码(工单 27):隐藏 WebView 载 /busca/ SPA
/// → 轮询注入抽取脚本 → 终态(命中/明示零结果/超时失败)。
/// 一切提取只在 WebView 里发生(ADR-0002)。JS 输出契约见
/// cifraclub_search_js.dart;桥解码前导与 17 共用(decodeBridgeValue)。
library;

import 'dart:async';

import '../../core/chart/cifra_extract.dart' show decodeBridgeValue;
import 'cifraclub_driver.dart';
import 'cifraclub_search_js.dart';

/// 一条搜索结果(原生列表的一行)。
class CifraSearchHit {
  const CifraSearchHit({required this.title, required this.path, this.artist});

  /// 歌名(站点条目主文本)。
  final String title;

  /// 艺人(站点条目副文本;抽不到为 null,列表行只显示歌名)。
  final String? artist;

  /// 站内路径(以 / 开头,如 /michael-jackson/beat-it/);点结果时拼域
  /// 名走 17 的导入管线。
  final String path;
}

/// 对 SPA 浮层的一次读取(注入脚本的解码终读)。
sealed class CifraSearchRead {
  const CifraSearchRead();
}

/// 有结果(站点还没渲染完时读不到这个)。
class CifraSearchOkRead extends CifraSearchRead {
  const CifraSearchOkRead(this.hits);

  final List<CifraSearchHit> hits;
}

/// 站点明示零结果(与「还没出」可区分,给可读空态而不是报失败)。
class CifraSearchZeroRead extends CifraSearchRead {
  const CifraSearchZeroRead();
}

/// 站点没渲染完/读不出(继续轮询,窗口尽头按超时失败)。
class CifraSearchPendingRead extends CifraSearchRead {
  const CifraSearchPendingRead();
}

/// 注入脚本的返回值 → 终读。容错纪律同 17:认不得的不猜——桥值
/// 解不开/形状不对返回 null,上层按 pending 继续轮询,窗口尽头统一
/// 报「搜索失败」,绝不把读不出伪装成零结果。
CifraSearchRead? decodeCifraSearchPayload(Object? input) {
  final value = decodeBridgeValue(input);
  if (value == null) return null;
  switch (value['status']) {
    case 'zero':
      return const CifraSearchZeroRead();
    case 'pending':
      return const CifraSearchPendingRead();
    case 'ok':
      final rawHits = value['hits'];
      if (rawHits is! List) return null;
      final hits = <CifraSearchHit>[];
      final seenPaths = <String>{};
      for (final raw in rawHits) {
        if (raw is! Map) continue; // 坏条目跳过,不废整页结果
        final title = raw['t'];
        final path = raw['u'];
        if (title is! String || title.isEmpty) continue;
        if (path is! String || !path.startsWith('/')) continue;
        if (!seenPaths.add(path)) continue; // 同链接去重
        final artist = raw['a'];
        hits.add(CifraSearchHit(
          title: title,
          path: path,
          artist: artist is String && artist.isNotEmpty ? artist : null,
        ));
      }
      if (hits.isEmpty) return null; // 全坏:读不出,不假装零结果
      return CifraSearchOkRead(List.unmodifiable(hits));
    default:
      return null;
  }
}

/// 搜索结果:命中 / 明示零结果 / 失败(超时或被新搜索取代)。
sealed class CifraSearchOutcome {
  const CifraSearchOutcome();
}

class CifraSearchSuccess extends CifraSearchOutcome {
  const CifraSearchSuccess(this.hits);

  final List<CifraSearchHit> hits;
}

class CifraSearchEmpty extends CifraSearchOutcome {
  const CifraSearchEmpty();
}

class CifraSearchFailure extends CifraSearchOutcome {
  const CifraSearchFailure(this.code);

  /// 'timeout'(窗口内没出结果)或 'superseded'(被新搜索取代)。
  final String code;
}

/// 搜索编排的时间参数(默认真机值;测试注入零值跑真 async)。
class CifraSearchTimings {
  const CifraSearchTimings({
    this.firstPollDelay = const Duration(milliseconds: 1500),
    this.pollInterval = const Duration(milliseconds: 1500),
    this.window = const Duration(seconds: 20),
    this.maxPolls = 12,
  });

  /// 页面载入后首次抽取前的静候(SPA 浮层渲染需要时间)。
  final Duration firstPollDelay;

  /// 后续轮询间隔。
  final Duration pollInterval;

  /// 总预算窗;超过即报超时失败。
  final Duration window;

  /// 轮询次数硬上界(零延时的测试依赖它收敛)。
  final int maxPolls;
}

/// 搜索编排器。一个实例绑一个隐藏 WebView;页面把回调接进来。
/// 新搜索令旧搜索作废(superseded),页面侧忽略过期结果即可。
///
/// 搜索不导航(真机逆向 2026-10-17:结果由页内 fetch solr 端点取得,
/// CORS 全开,任何 cifraclub 页面上都成立):先跑 start 脚本 kick 页内
/// fetch(页内 seq 自防过期覆盖),再轮询 poll 脚本读结果。连续 pending
/// 则 re-kick——首次搜索可能撞上 WebView 还在载入首页,导航会把
/// window 变量连 fetch 一起清掉,不 re-kick 就只能等超时。
class CifraClubSearcher {
  CifraClubSearcher(this._driver, {this.timings = const CifraSearchTimings()});

  final CifraClubDriver _driver;
  final CifraSearchTimings timings;

  int _token = 0;

  /// 执行搜索:kick 页内 fetch,轮询至终态(命中/明示零结果/超时)。
  Future<CifraSearchOutcome> search(String query) async {
    final token = ++_token;
    try {
      await _kick(query);
      var slept = Duration.zero;
      var pendingStreak = 0;
      for (var attempt = 0; attempt < timings.maxPolls; attempt++) {
        await Future<void>.delayed(
          attempt == 0 ? timings.firstPollDelay : timings.pollInterval,
        );
        if (token != _token) return const CifraSearchFailure('superseded');
        Object? raw;
        try {
          raw = await _driver.runJavaScriptReturningResult(
            cifraSearchPollScript,
          );
        } catch (_) {
          raw = null; // 页面还在导航/桥不可用:按读不出继续轮询
        }
        if (token != _token) return const CifraSearchFailure('superseded');
        final read = decodeCifraSearchPayload(raw);
        if (read is CifraSearchOkRead) return CifraSearchSuccess(read.hits);
        if (read is CifraSearchZeroRead) return const CifraSearchEmpty();
        pendingStreak = read is CifraSearchPendingRead ? pendingStreak + 1 : 0;
        if (pendingStreak >= 2) {
          pendingStreak = 0;
          await _kick(query); // 结果没来也没被否:重新 kick(幂等,seq 自增)
        }
        slept += attempt == 0
            ? timings.firstPollDelay
            : timings.pollInterval;
        if (slept >= timings.window) break;
      }
      return const CifraSearchFailure('timeout');
    } catch (_) {
      return const CifraSearchFailure('timeout');
    }
  }

  Future<void> _kick(String query) async {
    try {
      await _driver.runJavaScriptReturningResult(
        cifraSearchStartScript(query),
      );
    } catch (_) {
      // kick 落空(页面导航中):poll 的 pending→re-kick 路径会补。
    }
  }
}
