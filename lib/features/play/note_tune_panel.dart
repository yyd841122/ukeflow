import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/import/score_ir.dart';
import '../../core/import/score_ir_editor.dart';
import '../../core/import/score_ir_validator.dart';
import '../../core/model/uke_string.dart';
import 'score_ir_edit_session.dart';

/// 旋律层走简谱,谱面只认自然音级(score_sheet_layout 度数推导的白名单
/// 契约,黑键当场拒渲染):旋律音的弦/品候选落黑键即禁步进/拒存——
/// 不给「轻改把谱面改到画不出」的路。伴奏层无此约束(TAB 直书品数)。
bool _melodyNaturalPitch(int string, int fret) {
  const naturals = {0, 2, 4, 5, 7, 9, 11};
  return naturals.contains((UkeString.byNumber(string).midi + fret) % 12);
}

/// 弦/品候选是否可落:旋律层须自然音级(简谱画不出黑键),伴奏层不限。
bool _fretOk(bool isMelody, int string, int fret) =>
    !isMelody || _melodyNaturalPitch(string, fret);

/// 点选音 → 微调面板(工单 45;谱面视图/四线谱跟练两页同一入口)。
/// 返回 true = 源已存回,提示后由导入谱流推新源刷新页面。
Future<void> openNoteTunePanel(
  BuildContext context,
  ScoreIrEditSession session,
  ScoreIrNoteRef noteRef,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => NoteTunePanel(session: session, noteRef: noteRef),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已存回,谱面已刷新')));
  }
}

/// 单音微调面板(工单 45,spec 故事 64):谱面视图/四线谱跟练点选一个
/// 音后弹出的底部面板——弦/品步进、拍位微移(±0.25/±0.5,按钮按限界
/// 预禁用)、删除。面板内是工作副本,「存回」一次提交:改源 → 校验
/// 总闸 → 落库自动记 reviewedAt;被拦错误逐条人话亮在面板内,行不动
/// 可重试(组合编辑半提交时基线跟进已提交态,重试不重放已落库步)。
/// 物化刷新不归面板(会话只写源,页面听 provider 流换源)。
class NoteTunePanel extends ConsumerStatefulWidget {
  const NoteTunePanel({
    super.key,
    required this.session,
    required this.noteRef,
  });

  final ScoreIrEditSession session;
  final ScoreIrNoteRef noteRef;

  @override
  ConsumerState<NoteTunePanel> createState() => _NoteTunePanelState();
}

class _NoteTunePanelState extends ConsumerState<NoteTunePanel> {
  Future<ScoreIr>? _load;
  ScoreIr? _ir;

  late int _string0;
  late int _fret0;
  late int _string;
  late int _fret;
  late double _beat0;
  late double _beat;

  bool _busy = false;
  List<String>? _errors;

  @override
  void initState() {
    super.initState();
    _load = widget.session.load().then((ir) {
      if (!mounted) return ir; // 面板已关:字段不写(FutureBuilder 也不再消费)。
      // 引用 → 当前声部里那个音((弦,拍) 声部内唯一,校验器契约)。
      final notes = widget.noteRef.voice == ScoreIrVoiceKind.melody
          ? ir.melody.notes
          : ir.accompaniment.notes;
      ScoreIrNote? note;
      for (final n in notes) {
        if (n.string == widget.noteRef.string &&
            n.beat == widget.noteRef.beat) {
          note = n;
          break;
        }
      }
      if (note == null) throw StateError('选中的音不在源里:${widget.noteRef}');
      _ir = ir;
      _string0 = _string = note.string;
      _fret0 = _fret = note.fret;
      _beat0 = _beat = note.beat;
      return ir;
    });
  }

  /// 微移限界(层内本地拍,对原始拍位):面板全程不改库,限界对原始
  /// 源一次算定,累计位移受它收。
  ({double left, double right})? _limits(ScoreIr ir) {
    try {
      return scoreIrShiftLimits(ir, widget.noteRef);
    } on ArgumentError {
      return null;
    }
  }

  double get _shift => _beat - _beat0;

  bool _canShift(ScoreIr ir, double delta) {
    final limits = _limits(ir);
    if (limits == null) return false;
    final target = _shift + delta;
    if (target > 1e-9) return target < limits.right - 1e-9;
    if (target < -1e-9) return -target < limits.left - 1e-9;
    return true;
  }

  Future<void> _save() async {
    final ir = _ir;
    if (ir == null || _busy) return;
    setState(() {
      _busy = true;
      _errors = null;
    });
    // 工作副本的已提交基线((弦,拍) 身份照它算;初始即选中原音)。
    var ref = ScoreIrNoteRef(
      voice: widget.noteRef.voice,
      string: _string0,
      beat: _beat0,
    );
    ScoreIrEditOutcome? outcome;
    var shiftSaved = false;
    if (_shift.abs() > 1e-9) {
      outcome = await widget.session.apply(
        ScoreIrShift(ref: ref, delta: _shift),
      );
      if (outcome is ScoreIrEditSaved) {
        shiftSaved = true;
        // 微移落定后,(弦,拍) 身份里的拍变了,换弦品编辑引用新拍位。
        ref = ScoreIrNoteRef(voice: ref.voice, string: ref.string, beat: _beat);
      }
    }
    final refretChanged = _string != _string0 || _fret != _fret0;
    if (outcome is! ScoreIrEditBlocked &&
        refretChanged &&
        widget.noteRef.voice == ScoreIrVoiceKind.melody &&
        !_melodyNaturalPitch(_string, _fret)) {
      setState(() {
        _busy = false;
        _errors = const ['旋律层是简谱,黑键品画不出——换个弦或品'];
      });
      return;
    }
    if (outcome is! ScoreIrEditBlocked && refretChanged) {
      outcome = await widget.session.apply(
        ScoreIrReFret(ref: ref, string: _string, fret: _fret),
      );
    }
    if (!mounted) return;
    if (outcome == null) {
      Navigator.of(context).pop(); // 没改动,直接收起。
      return;
    }
    switch (outcome) {
      case ScoreIrEditSaved():
        Navigator.of(context).pop(true);
      case ScoreIrEditBlocked(:final errors):
        setState(() {
          _busy = false;
          _errors = errors;
          if (shiftSaved) {
            // 微移已落库而被拦的是后一步:基线跟进到已提交态——重试
            // 只补做被拦的一步,不重放微移(旧拍位引用必落空)。
            _beat0 = _beat;
          }
        });
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个音?'),
        content: const Text('删除后相邻音补上空档,源立即存回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('tune-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _errors = null;
    });
    final outcome = await widget.session.apply(
      ScoreIrDelete(ref: widget.noteRef),
    );
    if (!mounted) return;
    switch (outcome) {
      case ScoreIrEditSaved():
        Navigator.of(context).pop(true);
      case ScoreIrEditBlocked(:final errors):
        setState(() {
          _busy = false;
          _errors = errors;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('note-tune-panel'),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: FutureBuilder<ScoreIr>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '谱面读不出,改不了:${snapshot.error}',
                  style: TextStyle(color: scheme.error),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ],
            );
          }
          final ir = snapshot.data;
          if (ir == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final limits = _limits(ir);
          final isMelody =
              widget.noteRef.voice == ScoreIrVoiceKind.melody;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _title(ir),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                // 旋律层:候选(弦,品)落黑键即禁(简谱画不出,见
                // _melodyNaturalPitch);伴奏层只受范围收。
                _stepperRow(
                  label: '弦',
                  value: _stringLabel,
                  valueKey: 'tune-string-value',
                  onMinus: _string > 1 && _fretOk(isMelody, _string - 1, _fret)
                      ? () => setState(() => _string--)
                      : null,
                  minusKey: 'tune-string-minus',
                  onPlus: _string < 4 && _fretOk(isMelody, _string + 1, _fret)
                      ? () => setState(() => _string++)
                      : null,
                  plusKey: 'tune-string-plus',
                ),
                _stepperRow(
                  label: '品',
                  value: '$_fret',
                  valueKey: 'tune-fret-value',
                  onMinus: _fret > 0 && _fretOk(isMelody, _string, _fret - 1)
                      ? () => setState(() => _fret--)
                      : null,
                  minusKey: 'tune-fret-minus',
                  onPlus: _fret < scoreIrMaxFret && _fretOk(isMelody, _string, _fret + 1)
                      ? () => setState(() => _fret++)
                      : null,
                  plusKey: 'tune-fret-plus',
                ),
                _stepperRow(
                  label: '拍位',
                  value: _beatLabel(ir),
                  valueKey: 'tune-beat-value',
                  onMinus: _canShift(ir, -0.5)
                      ? () => setState(() => _beat -= 0.5)
                      : null,
                  minusKey: 'tune-beat-minus-half',
                  onPlus: _canShift(ir, 0.5)
                      ? () => setState(() => _beat += 0.5)
                      : null,
                  plusKey: 'tune-beat-plus-half',
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      key: const Key('tune-beat-minus-quarter'),
                      onPressed: _canShift(ir, -0.25)
                          ? () => setState(() => _beat -= 0.25)
                          : null,
                      child: const Text('−¼拍'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      key: const Key('tune-beat-plus-quarter'),
                      onPressed: _canShift(ir, 0.25)
                          ? () => setState(() => _beat += 0.25)
                          : null,
                      child: const Text('+¼拍'),
                    ),
                  ],
                ),
                if (limits == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '这个音的拍位不可微移',
                      style: TextStyle(color: scheme.outline, fontSize: 12),
                    ),
                  ),
                if (_errors != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      key: const Key('tune-errors'),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errors!.join('\n'),
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      key: const Key('tune-delete'),
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除'),
                    ),
                    const Spacer(),
                    FilledButton(
                      key: const Key('tune-save'),
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? '存回中…' : '存回'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _title(ScoreIr ir) =>
      '${widget.noteRef.voice == ScoreIrVoiceKind.melody ? '旋律' : '伴奏'}音 ·'
      '$_stringLabel弦 $_fret 品 · ${_beatLabel(ir)}';

  String get _stringLabel => const ['①', '②', '③', '④'][_string - 1];

  /// 主轴拍位展示(旋律层拍位 + 对齐偏移;与横带 x 一致)。
  String _beatLabel(ScoreIr ir) {
    final mainBeat =
        _beat +
        (widget.noteRef.voice == ScoreIrVoiceKind.melody
            ? ir.melodyAlignBeats
            : 0);
    final bar = ir.meter.beatsPerMeasure;
    final inBar = mainBeat - (mainBeat ~/ bar) * bar;
    return '第 ${(mainBeat ~/ bar).floor() + 1} 小节 ${_fmtBeat(inBar)} 拍';
  }

  String _fmtBeat(double v) => v == v.truncateToDouble()
      ? v.truncate().toString()
      : v.toStringAsFixed(2);

  Widget _stepperRow({
    required String label,
    required String value,
    required String valueKey,
    required VoidCallback? onMinus,
    required String minusKey,
    required VoidCallback? onPlus,
    required String plusKey,
  }) => Row(
    children: [
      SizedBox(width: 48, child: Text(label)),
      IconButton(
        key: Key(minusKey),
        onPressed: onMinus,
        icon: const Icon(Icons.remove),
      ),
      Expanded(
        child: Text(
          value,
          key: Key(valueKey),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      IconButton(
        key: Key(plusKey),
        onPressed: onPlus,
        icon: const Icon(Icons.add),
      ),
    ],
  );
}
