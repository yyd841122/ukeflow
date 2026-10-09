import 'package:flutter/material.dart';

import '../../core/ui/placeholder_page.dart';

/// 曲库页（占位）。
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(title: '曲库', icon: Icons.library_music);
  }
}
