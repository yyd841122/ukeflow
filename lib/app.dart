import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/providers.dart';
import 'features/chords/chords_page.dart';
import 'features/library/library_page.dart';
import 'features/path/path_page.dart';
import 'features/play/play_page.dart';
import 'features/tuner/tuner_page.dart';

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

/// 底部导航壳：调音器 / 和弦 / 跟练 / 路径 / 曲库。
/// IndexedStack 保活各页状态，切页签不丢滚动位置。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.tune), label: '调音器'),
    NavigationDestination(icon: Icon(Icons.music_note), label: '和弦'),
    NavigationDestination(icon: Icon(Icons.play_circle_outline), label: '跟练'),
    NavigationDestination(icon: Icon(Icons.route), label: '路径'),
    NavigationDestination(icon: Icon(Icons.library_music), label: '曲库'),
  ];

  static const _pages = [
    TunerPage(),
    ChordsPage(),
    PlayPage(),
    PathPage(),
    LibraryPage(),
  ];

  int _index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_warmUpDatabase());
  }

  /// 启动即触碰数据库，让 drift 空库在真机上真正打开一次：
  /// 出问题当场在 logcat 留下痕迹，而不是等后续工单第一次查询才暴露。
  Future<void> _warmUpDatabase() async {
    try {
      await ref
          .read(appDatabaseProvider)
          .customSelect('SELECT 1 AS ok')
          .getSingle();
    } catch (error, stackTrace) {
      debugPrint('UkeFlow: 数据库打开失败 $error\n$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: _destinations,
      ),
    );
  }
}
