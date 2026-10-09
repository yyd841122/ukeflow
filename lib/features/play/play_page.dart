import 'package:flutter/material.dart';

import '../../core/ui/placeholder_page.dart';

/// 跟练页（占位）。
class PlayPage extends StatelessWidget {
  const PlayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(
      title: '跟练',
      icon: Icons.play_circle_outline,
    );
  }
}
