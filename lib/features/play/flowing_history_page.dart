import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';

/// 最近练习会话流(票06:最近 20 条,自评改动即刷新)。
final flowingRecentSessionsProvider = StreamProvider<List<FlowingSession>>(
  (ref) => ref.watch(flowingSessionsDaoProvider).watchRecent(limit: 20),
);

/// 流水谱练习记录页(票06):最近 20 条(起始时刻降序),每条实际练习
/// 时长(预备/暂停不计)+ 结束位置 + 速度 + 自评下拉(codex 三档)。
class FlowingHistoryPage extends ConsumerWidget {
  const FlowingHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(flowingRecentSessionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('练习记录')),
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('记录读不出来：$error',
              style: const TextStyle(color: Color(0xFFC8616D))),
        ),
        data: (rows) {
          final visible = rows.where((r) => r.durationMs > 0).toList();
          if (visible.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '还没有练习记录——练一段（播了又停）就会记一行，预备数拍和暂停不算时长。',
                style: TextStyle(color: Color(0xFF617258)),
              ),
            );
          }
          return ListView.separated(
            itemCount: visible.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = visible[index];
              return ListTile(
                dense: true,
                title: Text(
                  '${_dateTime(row.startedAtMs)} · ${_duration(row.durationMs)} · '
                  '${_speedLabel(row.speed)} · 位置 ${_position(row.endPositionSeconds)}',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF374D3A)),
                ),
                trailing: _ratingPicker(context, ref, row),
              );
            },
          );
        },
      ),
    );
  }

  /// 自评下拉(未自评/还要练/逐渐熟/比较顺;codex 三档同款)。
  Widget _ratingPicker(BuildContext context, WidgetRef ref, FlowingSession row) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<int?>(
        value: row.rating,
        items: const [
          DropdownMenuItem(value: null, child: Text('未自评', style: TextStyle(fontSize: 12))),
          DropdownMenuItem(value: 1, child: Text('还要练', style: TextStyle(fontSize: 12))),
          DropdownMenuItem(value: 2, child: Text('逐渐熟', style: TextStyle(fontSize: 12))),
          DropdownMenuItem(value: 3, child: Text('比较顺', style: TextStyle(fontSize: 12))),
        ],
        onChanged: (value) {
          if (value == row.rating) return;
          unawaited(
            ref.read(flowingSessionsDaoProvider).setRating(row.id, value),
          );
        },
      ),
    );
  }

  String _dateTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  String _duration(int ms) {
    final total = (ms / 1000).round();
    if (total < 60) return '$total秒';
    return '${total ~/ 60}分${(total % 60).toString().padLeft(2, '0')}秒';
  }

  String _speedLabel(double speed) => speed == 1.0 ? '原速' : '$speed倍';

  String _position(double seconds) {
    final total = seconds.floor().clamp(0, 36000);
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}
