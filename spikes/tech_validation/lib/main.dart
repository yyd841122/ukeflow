import 'package:flutter/material.dart';

import 'parser_page.dart';
import 'scheduler_page.dart';
import 'tuner_page.dart';

void main() {
  runApp(const TechValidationApp());
}

class TechValidationApp extends StatelessWidget {
  const TechValidationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UkeFlow 里程碑 0 · 技术验证',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('UkeFlow Spike'),
            bottom: const TabBar(tabs: [
              Tab(text: '调音器'),
              Tab(text: '节拍调度'),
              Tab(text: '谱面解析'),
            ]),
          ),
          body: const TabBarView(
            children: [TunerPage(), SchedulerPage(), ParserPage()],
          ),
        ),
      ),
    );
  }
}
