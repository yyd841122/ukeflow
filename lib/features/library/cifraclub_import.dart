/// Cifra Club 导入编排(工单 17 建立管线,工单 27 从页面提出共用):
/// ukulele 优先 → 无该版回退原版并告知 → 就绪重试提取 → 转文本谱。
/// 一切提取只在 WebView 里发生(ADR-0002),本类只编排 [CifraClubDriver]
/// 之上的取数时序;页面持有 WebView,把回调接进来。
library;

import 'dart:async';

import '../../core/chart/cifra_extract.dart';
import 'cifraclub_extract_js.dart';
import 'cifraclub_driver.dart';
import 'cifraclub_urls.dart';

/// WebView 驱动注入的时间参数(默认真机值;测试给零值/假延时跑真 async)。
class CifraClubTimings {
  const CifraClubTimings({
    this.pageTimeout = const Duration(seconds: 15),
    this.retryInterval = const Duration(milliseconds: 1500),
  });

  /// 单次导航等页面完成的兜底窗。
  final Duration pageTimeout;

  /// 提取就绪重试间隔(总窗约 10s = 6 次 × 1.5s)。
  final Duration retryInterval;
}

/// 导入结果:成功(ChordPro 源 + 可选中文告知)或可读失败。
sealed class CifraImportOutcome {
  const CifraImportOutcome();
}

class CifraImportOk extends CifraImportOutcome {
  const CifraImportOk({required this.source, this.notice});

  /// 转好的 ChordPro 文本谱(预填进文本导入页,过校验才谈入库)。
  final String source;

  /// 中文告知(如「站点没有这首的 Ukulele 转谱,已按原版导入」)。
  final String? notice;
}

class CifraImportFail extends CifraImportOutcome {
  const CifraImportFail(this.message);

  /// 可读中文失败文案(直接展示,指路文本导入)。
  final String message;
}

/// 导入编排器。一个实例绑一个 WebView;页面把 `onPageFinished` 转接给
/// [notePageFinished]。
class CifraClubImporter {
  CifraClubImporter(this._driver, {this.timings = const CifraClubTimings()});

  final CifraClubDriver _driver;
  final CifraClubTimings timings;

  /// 页面加载完成的一次性等待点(_navigateAndExtract 用)。
  Completer<void>? _pageWaiter;

  /// 导航请求令牌:每次导航递增,等待返回后核对——被打断/被取代的导航
  /// 不得把提取结果安到新请求上(审计 2026-10-16 #29)。
  int _navToken = 0;

  /// 页面的 onPageFinished 转接点。
  void notePageFinished() {
    final waiter = _pageWaiter;
    _pageWaiter = null;
    waiter?.complete();
  }

  /// 导入此谱(**ukulele 优先**,用户反馈:版本管理不该甩给用户):
  /// [songUrl] 是两段标准曲谱页时先载 `/ukulele/` 变体提取;没有该版
  /// (站点 404 壳/无和弦)自动回退原版,并在告知文案里说明「已按
  /// 原版导入」。提取→转文本谱([buildChordPro]);失败给可读文案,
  /// 不抛异常。
  Future<CifraImportOutcome> importSong(
    Uri songUrl, {
    required Set<String> allowedChords,
  }) async {
    try {
      final uke = CifraClubUrls.ukuleleVariant(songUrl);
      String? notice;
      Object? raw;
      if (uke != null) {
        final ukeRaw = await _navigateAndExtract(uke);
        if (cifraImportReadableFailure(ukeRaw) == null &&
            decodeCifraPayload(ukeRaw) != null) {
          raw = ukeRaw;
        } else {
          // 没有 ukulele 版(404 壳/页面无谱):回退原版,告知用户。
          notice = '站点没有这首的 Ukulele 转谱,已按原版导入。'
              '和弦名通用,尤克里里照常可练;原谱中的六线谱段已过滤。';
          raw = await _navigateAndExtract(songUrl);
        }
      } else {
        // 已是 ukulele 页/versao 变体页:17 原语义是**就地提取**(页面
        // 就停在目标谱上,再 loadRequest 同一 URL 是多余一次导航,评审
        // 2026-10-17 抓出回归)。仍走就绪重试:页面事件可能早于 DOM。
        raw = await _extractWhenReady();
      }

      final failureText = cifraImportReadableFailure(raw);
      if (failureText != null) return CifraImportFail(failureText);
      final payload = decodeCifraPayload(raw);
      if (payload == null) {
        return CifraImportFail(failureCopy('no-content'));
      }
      return CifraImportOk(
        source: buildChordPro(payload, allowedChords: allowedChords),
        notice: notice,
      );
    } catch (error) {
      return CifraImportFail(
        '提取失败,请重试;若反复出现请回曲库用文本导入。(技术细节:$error)',
      );
    }
  }

  /// 载入 [url] 等页面完成(15s 兜底),然后就绪重试提取。
  ///
  /// 导航关联纪律(审计 2026-10-16 #29):令牌核对——超时/被新导航取代
  /// 时不再提取(旧实现超时当成功,会在随便哪一页上提取,可能导错歌);
  /// 落点 URL 与请求不符(重定向去了别页)按失败返回,绝不拿旧页内容
  /// 当目标谱。
  Future<Object?> _navigateAndExtract(Uri url) async {
    final token = ++_navToken;
    final waiter = Completer<void>();
    _pageWaiter = waiter;
    await _driver.loadRequest(url);
    await waiter.future.timeout(timings.pageTimeout, onTimeout: () {});
    if (token != _navToken) return const {'error': 'superseded'};
    final landed = Uri.tryParse(await _driver.currentUrl() ?? '');
    if (landed == null || !_sameSongDocument(landed, url)) {
      return const {'error': 'wrong-page'};
    }
    return _extractWhenReady();
  }

  /// 同一曲谱文档判定:忽略 query/fragment 与结尾斜杠(站点会挂跟踪
  /// 参数),路径段须一致——重定向到别的歌不算到达。
  bool _sameSongDocument(Uri a, Uri b) {
    String normalize(Uri u) {
      final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
      return segs.join('/');
    }

    return normalize(a) == normalize(b);
  }

  /// 就绪重试:onPageFinished 可能早于 DOM 可用(真机实证——导航后
  /// 0.5s 即触发,提取落空拿到错误 JSON)。pre 是服务端渲染,页面就位
  /// 即可取,提取失败按 1.5s 间隔重取,总窗约 10s。
  Future<Object?> _extractWhenReady() async {
    Object? raw;
    for (var attempt = 0; attempt < 6; attempt++) {
      raw = await _driver.runJavaScriptReturningResult(cifraExtractScript);
      final ready = cifraImportReadableFailure(raw) == null &&
          decodeCifraPayload(raw) != null;
      if (ready) return raw;
      await Future<void>.delayed(timings.retryInterval);
    }
    return raw;
  }
}

/// JS 返回值里的失败码 → 可读文案;不是失败形状则 null。
String? cifraImportReadableFailure(Object? raw) {
  final code = cifraExtractError(raw);
  if (code == null) return null;
  return failureCopy(code);
}

/// 调用点兜底文案:importSong 自身不抛,但调用点在 try 里还要取和弦库
/// (库加载失败)——页面 catch 后用同一可读文案落横幅(评审 2026-10-17:
/// 重构丢了页面级 catch,库失败从可读横幅变成静默未处理异常,补下家)。
String importCatchCopy(Object error) =>
    '提取失败,请重试;若反复出现请回曲库用文本导入。(技术细节:$error)';

/// 失败码 → 中文文案(导入页/搜索页共用)。
String failureCopy(String code) {
  if (code.startsWith('exception:')) return '页内脚本出错($code),请重试';
  return switch (code) {
    'no-content' => '没认出谱面内容——页面可能没加载完,或站点改版了。'
        '稍等重试,或回曲库用文本导入。',
    'no-chords' => '这个页面没提取到和弦——可能不是曲谱页。'
        '也可以回曲库用文本导入。',
    'wrong-page' => '页面没停在目标曲谱页(可能被站点重定向),请重试。',
    'superseded' => '这次提取被新的操作取代了。',
    _ => '提取失败($code),请重试或用文本导入。',
  };
}
