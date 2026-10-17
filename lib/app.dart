import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/providers.dart';
import 'features/chords/chords_page.dart';
import 'features/library/library_page.dart';
import 'features/path/path_page.dart';
import 'features/settings/settings_page.dart';
import 'features/tuner/tuner_page.dart';
import 'tab_index.dart';

/// UkeFlow 应用根：中文 UI、统一主题、五页签导航壳。
class UkeFlowApp extends StatelessWidget {
  const UkeFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UkeFlow',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeShell(),
    );
  }
}

/// 底部导航壳：调音器 / 和弦 / 路径 / 曲库 / 设置(五页签;四页签形态见
/// 工单 15 用户决策裁撤跟练页签——跟练是点歌后发生的活动,入口在曲库页
/// 与路径页;设置页归工单 20)。IndexedStack 保活各页状态，切页签不丢
/// 滚动位置。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

/// 当前页签下标见 tab_index.dart(调音器「离开页面即停」的感知缝)。

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _tabs = [
    (label: '调音器', icon: Icons.tune, page: TunerPage()),
    (label: '和弦', icon: Icons.music_note, page: ChordsPage()),
    (label: '路径', icon: Icons.route, page: PathPage()),
    (label: '曲库', icon: Icons.library_music, page: LibraryPage()),
    (label: '设置', icon: Icons.settings, page: SettingsPage()),
  ];

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // 启动即预热数据库（见 databaseWarmupProvider）。
    ref.watch(databaseWarmupProvider);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [for (final tab in _tabs) tab.page],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() {
          _index = index;
          ref.read(activeTabIndexProvider.notifier).set(index);
        }),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }
}
