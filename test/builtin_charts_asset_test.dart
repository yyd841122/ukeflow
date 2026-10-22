import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_charts.dart';
import 'package:ukeflow/core/model/strum_chart.dart';
import 'package:ukeflow/data/chart_providers.dart';
import 'package:ukeflow/data/chord_library.dart';

/// 工单 07 验收：5 首目标曲全部解析、过校验、可被后续工单取用。
/// 2026-10-18 起清单并入 19 首旧项目迁移谱（ukulele-demo/glm 转录，
/// 自由段/示意段落形态），加载与白名单契约对全清单生效。
/// 真实资产 + 真实和弦库白名单，普通 test()（rootBundle 在非 widget
/// 测试里可用）。

/// 一首谱用到的全部和弦名。
Set<String> chordNamesOf(BuiltInChart built) => {
  for (final section in built.chart.sections)
    for (final line in section.lines)
      for (final mark in line.chords) mark.name,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<BuiltInChart> charts;

  setUpAll(() async {
    final lib = ChordLibrary.parse(
      await rootBundle.loadString('assets/chords/ukulele.json'),
    );
    charts = await BuiltInCharts.load(
      readAsset: rootBundle.loadString,
      allowedChords: lib.labels,
    );
  });

  test('清单与资产一一对应，${builtinChartCatalog.length} 首全部加载成功', () {
    expect(charts, hasLength(builtinChartCatalog.length));
    expect(charts, hasLength(24), reason: '5 首目标曲 + 19 首旧项目迁移谱');
    expect(
      charts.map((c) => c.id).toSet(),
      hasLength(builtinChartCatalog.length),
      reason: '曲目 id 不得重复',
    );
  });

  group('每首目标曲的内容契约', () {
    final expected = {
      'ai-ni-bu-shi-liang-san-tian': ('爱你不是两三天', '梁静茹'),
      'cang-hai-yi-sheng-xiao-strum': ('沧海一声笑', '黄霑'),
      'big-big-world': ('Big Big World', 'Emilia'),
      'love-you-more-than-i-can-say': ('More Than I Can Say', 'Leo Sayer'),
      'yesterday-once-more': ('Yesterday Once More', 'Carpenters'),
    };

    for (final entry in expected.entries) {
      test('${entry.key}：元数据与结构齐全', () {
        final chart = charts
            .singleWhere((c) => c.id == entry.key)
            .chart;
        expect(chart.title, entry.value.$1);
        expect(chart.artist, entry.value.$2);
        expect(chart.key, isNotNull);
        expect(chart.tempo, isNotNull);

        // 跟练需要段落结构与足够的和弦；没有和弦就没法编时间轴。
        // 沧海一声笑是分节歌（主歌×n+尾声，无副歌），其余四首有副歌。
        expect(chart.sections, hasLength(greaterThanOrEqualTo(2)));
        expect(
          chart.sections.map((s) => s.kind),
          contains(StrumSectionKind.verse),
        );
        if (entry.key != 'cang-hai-yi-sheng-xiao-strum') {
          expect(
            chart.sections.map((s) => s.kind),
            contains(StrumSectionKind.chorus),
          );
        }
        final chords = chordNamesOf(
          charts.singleWhere((c) => c.id == entry.key),
        );
        expect(chords, isNotEmpty);
        expect(chords, everyElement(isNot(contains('/'))),
            reason: 'v1 和弦库无斜杠和弦指法');
      });
    }
  });

  group('旧项目迁移谱的内容契约（自由段/示意段落，只锁可用性）', () {
    final migrated = {
      'song-bie', 'you-yi-di-jiu-tian-chang', 'mo-li-hua',
      'xiao-xing-xing-strum', 'sheng-ri-kuai-le', 'liang-zhi-lao-hu',
      'huan-le-song-strum', 'fen-shua-jiang', 'chun-tian-lai-le',
      'ling-er-xiang-ding-dang', 'oh-susanna', 'yao-lan-qu', 'tong-nian',
      'yin-xing-de-chi-bang', 'you-are-my-sunshine', 'london-bridge',
      'row-row-row', 'xin-nian-hao', 'kang-kang-wu-qu',
    };

    test('迁移谱 id 齐全且不多不少', () {
      expect(
        charts.map((c) => c.id).where(migrated.contains).toSet(),
        migrated,
      );
    });

    for (final id in migrated) {
      test('$id：元数据齐全、至少一段、有和弦', () {
        final built = charts.singleWhere((c) => c.id == id);
        expect(built.chart.title, isNot(StrumChart.untitled));
        expect(built.chart.artist, isNotNull);
        expect(built.chart.key, isNotNull);
        expect(built.chart.tempo, isNotNull);
        expect(built.chart.sections, hasLength(greaterThanOrEqualTo(1)));
        final chords = chordNamesOf(built);
        expect(chords, isNotEmpty);
        expect(chords, everyElement(isNot(contains('/'))),
            reason: 'v1 和弦库无斜杠和弦指法');
      });
    }
  });

  test('全部谱内和弦名都在和弦库白名单内（校验已保证，此处显式复核）', () async {
    final lib = ChordLibrary.parse(
      await rootBundle.loadString('assets/chords/ukulele.json'),
    );
    final used = <String>{
      for (final built in charts) ...chordNamesOf(built),
    };
    expect(used.intersection(lib.labels), used);
  });

  test('builtinChartsProvider 经真实资产解析出全部弹唱谱', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final loaded = await container.read(builtinChartsProvider.future);
    expect(loaded.map((c) => c.id), charts.map((c) => c.id));
  });
}
