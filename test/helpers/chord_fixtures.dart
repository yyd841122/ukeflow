import 'dart:io';

import 'package:ukeflow/data/chord_library.dart';

/// UI 测试共用：小型 fixture 和弦库 + provider 覆盖。
/// 与真实资产解耦（testWidgets 的 FakeAsync 里 rootBundle 真实文件 I/O
/// 永远完不了）；真实资产的加载在 chord_library_test 用普通 test() 验证。
final uiFixtureLibrary = ChordLibrary.parse(
  File('test/fixtures/chords/ui_fixture.json').readAsStringSync(),
);

/// 返回类型随 Riverpod 版本走（3.x 不再导出 Override），测试无需具名。
// ignore: strict_top_level_inference
chordLibraryFixtureOverride() => chordLibraryProvider.overrideWith(
  (ref) async => uiFixtureLibrary,
);
