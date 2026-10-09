import 'package:flutter/material.dart';

/// UkeFlow 统一主题：琥珀木色种子色（尤克里里琴身），Material 3。
abstract final class AppTheme {
  static const _seedColor = Color(0xFFB36B24);

  static final ThemeData light = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
  );

  static final ThemeData dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
  );
}
