import 'package:flutter/material.dart';

import '../../core/ui/placeholder_page.dart';

/// 和弦库页（占位）。
class ChordsPage extends StatelessWidget {
  const ChordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(title: '和弦', icon: Icons.music_note);
  }
}
