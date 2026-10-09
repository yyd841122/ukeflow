import 'package:flutter/material.dart';

import '../../core/ui/placeholder_page.dart';

/// 调音器页（占位）。
class TunerPage extends StatelessWidget {
  const TunerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(title: '调音器', icon: Icons.tune);
  }
}
