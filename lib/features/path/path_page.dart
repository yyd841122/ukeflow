import 'package:flutter/material.dart';

import '../../core/ui/placeholder_page.dart';

/// 练习路径页（占位）。
class PathPage extends StatelessWidget {
  const PathPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(title: '路径', icon: Icons.route);
  }
}
