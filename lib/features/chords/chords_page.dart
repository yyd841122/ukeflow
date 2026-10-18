import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/centered_hint.dart';
import '../../core/ui/load_error_view.dart';
import '../../data/chord_library.dart';
import 'chord_detail_page.dart';
import 'chord_diagram.dart';
import 'chord_tips.dart';

/// 和弦库页：搜索直达 + 常用置顶 + 按根音字母分组浏览。
class ChordsPage extends ConsumerStatefulWidget {
  const ChordsPage({super.key});

  @override
  ConsumerState<ChordsPage> createState() => _ChordsPageState();
}

class _ChordsPageState extends ConsumerState<ChordsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(chordLibraryProvider);
    return libraryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      // 共享报错壳(工单19 提取,与曲库/路径页同壳;此处居中),评审后内联。
      error: (error, _) =>
          Center(child: LoadErrorView(title: '和弦库加载失败', error: error)),
      data: (library) => _BrowseView(
        chords: library.chords,
        query: _query,
        onQueryChanged: (q) => setState(() => _query = q),
      ),
    );
  }
}

class _BrowseView extends StatelessWidget {
  const _BrowseView({
    required this.chords,
    required this.query,
    required this.onQueryChanged,
  });

  final List<Chord> chords;
  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final results = q.isEmpty
        ? chords
        : chords.where((c) => c.label.toLowerCase().contains(q)).toList();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索和弦名，如 Am、G7',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? CenteredHint(message: '没有匹配「$query」的和弦')
                : _ChordList(results: results),
          ),
        ],
      ),
    );
  }
}

/// 浏览列表：常用套件置顶，其余按根音分组；每行 4 个瓦片。
class _ChordList extends StatelessWidget {
  const _ChordList({required this.results});

  final List<Chord> results;

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(results);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return switch (items[index]) {
          _BrowseHeader(:final text) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(text, style: Theme.of(context).textTheme.titleMedium),
          ),
          _BrowseRow(:final chords) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (final chord in chords)
                  Expanded(child: ChordTile(chord: chord)),
              ],
            ),
          ),
        };
      },
    );
  }

  /// 条目流：分组头与整行瓦片（≤4 个和弦）。
  static List<_BrowseItem> _buildItems(List<Chord> chords) {
    final items = <_BrowseItem>[];
    void addGroup(String header, List<Chord> group) {
      if (group.isEmpty) return;
      items.add(_BrowseHeader(header));
      for (var i = 0; i < group.length; i += 4) {
        items.add(
          _BrowseRow(group.sublist(i, (i + 4).clamp(0, group.length))),
        );
      }
    }

    final byLabel = {for (final c in chords) c.label: c};
    final common = [for (final label in commonChordKit) ?byLabel[label]];
    addGroup('常用', common);

    final kitLabels = commonChordKit.toSet();
    var current = <Chord>[];
    var lastRoot = common.isEmpty ? '' : common.last.root;
    for (final c in chords) {
      if (kitLabels.contains(c.label)) continue;
      if (c.root != lastRoot) {
        addGroup(lastRoot, current);
        current = <Chord>[];
        lastRoot = c.root;
      }
      current.add(c);
    }
    addGroup(lastRoot, current);
    return items;
  }
}

/// 浏览列表条目。
sealed class _BrowseItem {
  const _BrowseItem();
}

class _BrowseHeader extends _BrowseItem {
  const _BrowseHeader(this.text);

  final String text;
}

class _BrowseRow extends _BrowseItem {
  const _BrowseRow(this.chords);

  final List<Chord> chords;
}

/// 浏览瓦片：主指法小图 + 和弦名，点击进详情。
class ChordTile extends StatelessWidget {
  const ChordTile({super.key, required this.chord});

  final Chord chord;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ChordDetailPage(chord: chord)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            children: [
              ChordDiagram(fingering: chord.primaryFingering, width: 64),
              const SizedBox(height: 4),
              Text(
                chord.label,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
