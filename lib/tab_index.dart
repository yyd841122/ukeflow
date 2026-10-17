import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前页签下标(IndexedStack 保活各页,页内看不见自己是否在台前——
/// 调音器「离开页面即停」靠它感知自己被切走;导航壳是唯一写入方)。
final activeTabIndexProvider = NotifierProvider<ActiveTabIndex, int>(
  ActiveTabIndex.new,
);

class ActiveTabIndex extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

/// 调音器在页签序列里的下标(导航壳 _tabs 首位)。
const int tunerTabIndex = 0;
