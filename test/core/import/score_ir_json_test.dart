import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/import/score_ir.dart';

import '../../helpers/score_ir_fixtures.dart';

/// 识谱源 JSON 序列化缝(工单 42,ADR-0009):工作台导出 JSON ↔ App 解析
/// 的契约。手编小 IR 逐字段往返;schemaVersion 门与缺字段当场拒析——
/// 坏源不静默(43 的 Ready/Broken 兜底吃的是这里的异常面)。
void main() {
  group('ScoreIr JSON 往返', () {
    test('手编小 IR:toJson→fromJson 逐字段相等(含证据/歌词/指形)', () {
      final ir = tinyScoreIr();
      final restored = ScoreIr.fromJson(ir.toJson());
      expectScoreIrEqual(restored, ir);
    });

    test('再编码逐字节一致(无隐性丢字段)', () {
      final ir = tinyScoreIr();
      final json = ir.toJson();
      expect(ScoreIr.fromJson(json).toJson(), json);
    });

    test('schemaVersion 非 1 当场拒析', () {
      final json = tinyScoreIr().toJson();
      json['schemaVersion'] = 2;
      expect(
        () => ScoreIr.fromJson(json),
        throwsA(
          isA<ScoreIrFormatException>().having(
            (e) => e.message,
            'message',
            contains('schemaVersion'),
          ),
        ),
      );
    });

    test('缺 voices.melody 报格式错,指明缺什么', () {
      final json = tinyScoreIr().toJson();
      (json['voices'] as Map<String, dynamic>).remove('melody');
      expect(
        () => ScoreIr.fromJson(json),
        throwsA(
          isA<ScoreIrFormatException>().having(
            (e) => e.message,
            'message',
            contains('voices.melody'),
          ),
        ),
      );
    });
  });
}
