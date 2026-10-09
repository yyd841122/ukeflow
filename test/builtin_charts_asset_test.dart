import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_charts.dart';
import 'package:ukeflow/core/model/strum_chart.dart';
import 'package:ukeflow/data/chart_providers.dart';
import 'package:ukeflow/data/chord_library.dart';

/// 工单 07 验收：5 首目标曲全部解析、过校验、可被后续工单取用。
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

  test('清单与资产一一对应，5 首全部加载成功', () {
    expect(charts, hasLength(5));
    expect(
      charts.map((c) => c.id).toSet(),
      hasLength(5),
      reason: '曲目 id 不得重复',
    );
  });

  group('每首目标曲的内容契约', () {
    final expected = {
      'ai-ni-bu-shi-liang-san-tian': ('爱你不是两三天', '梁静茹'),
      'cang-hai-yi-sheng-xiao': ('沧海一声笑', '黄霑'),
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
        if (entry.key != 'cang-hai-yi-sheng-xiao') {
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

  test('全部谱内和弦名都在和弦库白名单内（校验已保证，此处显式复核）', () async {
    final lib = ChordLibrary.parse(
      await rootBundle.loadString('assets/chords/ukulele.json'),
    );
    final used = <String>{
      for (final built in charts) ...chordNamesOf(built),
    };
    expect(used.intersection(lib.labels), used);
  });

  test('builtinChartsProvider 经真实资产解析出 5 首弹唱谱', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final loaded = await container.read(builtinChartsProvider.future);
    expect(loaded.map((c) => c.id), charts.map((c) => c.id));
  });
}
