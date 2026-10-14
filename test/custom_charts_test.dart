import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/custom_charts.dart';

/// 工单 15 曲库数据源:自建谱源文本读出解析。
/// 入库时已过校验(工单 16 导入管线),读出再过同一校验层是
/// 不信任存储的最后一道闸——坏谱当场抛错(带曲名可定位),
/// 与内置谱「不带病进曲库页」同一哲学。
void main() {
  test('合法源文本解析成弹唱谱,展示名以入库名为准', () {
    final chart = parseCustomChart(
      source: '{title: 内嵌名}\n{tempo: 90}\n[C]歌词',
      title: '我的歌',
      allowedChords: {'C'},
    );
    expect(chart.title, '我的歌', reason: '票15④命名合并策略:展示名=入库名,'
        '跟练会话页标题与曲库卡片一字不差');
    expect(chart.tempo, 90, reason: '其余元数据仍取自源文本');
  });

  test('源文本无名字的谱,入库名同样落到展示名', () {
    final chart = parseCustomChart(
      source: '[C]歌词',
      title: '起的名',
      allowedChords: {'C'},
    );
    expect(chart.title, '起的名');
  });

  test('段落未闭合的坏谱抛错,错误信息带曲名可定位', () {
    expect(
      () => parseCustomChart(
        source: '{start_of_verse}\n[C]歌词',
        title: '坏谱歌',
        allowedChords: {'C'},
      ),
      throwsA(
        predicate(
          (e) => e is StateError && '$e'.contains('坏谱歌'),
          'StateError 且带曲名「坏谱歌」',
        ),
      ),
    );
  });

  test('白名单外和弦抛错(存储期白名单漂移同样拦下)', () {
    expect(
      () => parseCustomChart(
        source: '[Xx9]词',
        title: '坏和弦歌',
        allowedChords: {'C'},
      ),
      throwsA(isA<StateError>()),
    );
  });
}
