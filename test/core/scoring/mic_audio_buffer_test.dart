import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/scoring/mic_audio_buffer.dart';

/// 会话音频缓冲(GLOSSARY「跟练评分」的重听底座):麦 chunk 到达即存
/// (Int16 半内存),报告点格重听与 Chroma 取窗都从这里按引擎秒取。
/// 看完即弃:缓冲随评分会话终止而丢弃,不落库。
void main() {
  test('空缓冲:边界查询返回空/null,不炸', () {
    final buf = MicAudioBuffer();
    expect(buf.startSec, isNull);
    expect(buf.endSec, isNull);
    expect(buf.window(0, 1), isEmpty);
    expect(buf.wavSnippet(startSec: 0, endSec: 1), isNull);
  });

  test('append:端点时刻取自传入的 chunk 末样本引擎秒', () {
    final buf = MicAudioBuffer();
    buf.append(Float64List.fromList([0.1, 0.2, 0.3]), 0.5);
    expect(buf.startSec, closeTo(0.5 - 3 / 44100, 1e-9));
    expect(buf.endSec, 0.5);
  });

  test('window:跨 chunk 取窗按时间定位,值经 Int16 量化往返', () {
    final buf = MicAudioBuffer();
    // chunk 1: 3 样本(0..0.29s 尾 0.3s);chunk 2: 3 样本(尾 0.6s)。
    // 44100 太大不利心算——直接用真实采样率,时间换算交给被测物。
    buf.append(Float64List.fromList([0.5, -0.5, 0.25]), 3 / 44100);
    buf.append(Float64List.fromList([1.0, -1.0, 0.125]), 6 / 44100);

    final whole = buf.window(0, 1);
    expect(whole, hasLength(6));
    // Int16 量化:0.5/32768 往返误差 < 1/32768。
    double q(double v) => (v * 32767).roundToDouble() / 32768;
    expect(whole[0], closeTo(q(0.5), 1e-4));
    expect(whole[1], closeTo(q(-0.5), 1e-4));
    expect(whole[3], closeTo(q(1.0), 1e-4));
    expect(whole[5], closeTo(q(0.125), 1e-4));

    // 取中段(第 4、5 样本,跨两个 chunk 各一)。
    final mid = buf.window(4 / 44100, 6 / 44100);
    expect(mid, hasLength(2));
    expect(mid[0], closeTo(q(-1.0), 1e-4));
    expect(mid[1], closeTo(q(0.125), 1e-4));
  });

  test('window:越界钳制到缓冲实有范围', () {
    final buf = MicAudioBuffer();
    buf.append(Float64List.fromList([0.5, 0.5, 0.5]), 3 / 44100);
    expect(buf.window(-1, 99), hasLength(3));
  });

  test('wavSnippet:规范 RIFF 头 + 样本数正确;窗外区间返回 null', () {
    final buf = MicAudioBuffer();
    buf.append(Float64List.fromList([0.5, -0.5, 0.25, -0.25]), 4 / 44100);
    final wav = buf.wavSnippet(startSec: 1 / 44100, endSec: 3 / 44100)!;
    final view = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(view.getUint32(40, Endian.little), 4, reason: 'data 块字节数');
    expect(
      view.getUint32(28, Endian.little),
      88200,
      reason: '字节率(44100×16bit)',
    );
    expect(
      view.getInt16(44, Endian.little),
      (-0.5 * 32767).round(),
      reason: '首样本是原缓冲第 2 个',
    );

    expect(
      buf.wavSnippet(startSec: 9 / 44100, endSec: 10 / 44100),
      isNull,
      reason: '窗外无实有样本',
    );
  });

  test('长跑多 chunk:append 数千次后 window 仍正确(报告期取窗不串位)', () {
    final buf = MicAudioBuffer();
    double a(int k) => ((k % 10) + 1) / 20; // 小幅值,避开 Int16 钳制
    for (var k = 0; k < 3000; k++) {
      buf.append(Float64List.fromList([a(k), -a(k)]), (2 * k + 2) / 44100);
    }
    // 窗 = [2000/44100, 2005/44100):样本 2000..2004,共 5 个
    // (chunk 1000 两全、chunk 1001 两全、chunk 1002 首)。
    final w = buf.window((1000 * 2) / 44100, (1002 * 2) / 44100 + 1 / 44100);
    expect(w, hasLength(5));
    expect(w[0], closeTo(a(1000), 1e-4));
    expect(w[1], closeTo(-a(1000), 1e-4));
    expect(w[2], closeTo(a(1001), 1e-4));
    expect(w[3], closeTo(-a(1001), 1e-4));
    expect(w[4], closeTo(a(1002), 1e-4));
  });
}
