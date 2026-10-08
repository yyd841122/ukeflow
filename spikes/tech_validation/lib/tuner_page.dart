import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:record/record.dart';

/// Spike A：麦克风 → YIN 音高检测 → 最近音名/音分偏差。
/// 通过标准：真琴单弦拨响，音名正确且读数稳定；静音时不乱报音高。
class TunerPage extends StatefulWidget {
  const TunerPage({super.key});

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  static const _sampleRate = 44100;
  static const _bufSize = 2048;
  static const _detectInterval = Duration(milliseconds: 60);

  /// GCEA 标准定音（re-entrant，G 为高音 G4）
  static const _strings = <String, double>{
    'G': 391.995,
    'C': 261.626,
    'E': 329.628,
    'A': 440.0,
  };

  final _recorder = AudioRecorder();
  final _detector =
      PitchDetector(audioSampleRate: _sampleRate.toDouble(), bufferSize: _bufSize);

  StreamSubscription<Uint8List>? _sub;
  final List<double> _samples = [];
  DateTime _lastDetect = DateTime.fromMillisecondsSinceEpoch(0);

  bool _running = false;
  double? _pitch;
  double _probability = 0;
  String _target = 'G';

  @override
  void dispose() {
    _sub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggle() => _running ? _stop() : _start();

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('未授予麦克风权限')));
      }
      return;
    }
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    ));
    _samples.clear();
    _sub = stream.listen(_onChunk);
    setState(() => _running = true);
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    await _recorder.stop();
    setState(() {
      _running = false;
      _pitch = null;
      _probability = 0;
    });
  }

  Future<void> _onChunk(Uint8List bytes) async {
    final sampleCount = bytes.length ~/ 2;
    if (sampleCount == 0) return;
    final data = ByteData.sublistView(bytes, 0, sampleCount * 2);
    for (var i = 0; i < sampleCount; i++) {
      _samples.add(data.getInt16(i * 2, Endian.little) / 32768.0);
    }
    if (_samples.length > _bufSize) {
      _samples.removeRange(0, _samples.length - _bufSize);
    }
    final now = DateTime.now();
    if (_samples.length < _bufSize ||
        now.difference(_lastDetect) < _detectInterval) {
      return;
    }
    _lastDetect = now;
    final result = await _detector.getPitchFromFloatBuffer(_samples);
    if (!mounted) return;
    setState(() {
      _pitch = result.pitched ? result.pitch : null;
      _probability = result.probability;
    });
  }

  ({String name, double cents})? _noteInfo(double freq) {
    final midi = 69.0 + 12 * math.log(freq / 440.0) / math.ln2;
    final nearest = midi.round();
    const names = [
      'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
    ];
    final name = '${names[nearest % 12]}${nearest ~/ 12 - 1}';
    return (name: name, cents: (midi - nearest) * 100);
  }

  @override
  Widget build(BuildContext context) {
    final pitch = _pitch;
    final info = pitch == null ? null : _noteInfo(pitch);
    final targetFreq = _strings[_target]!;
    final targetCents = pitch == null
        ? null
        : 1200 * math.log(pitch / targetFreq) / math.ln2;
    final inTune = targetCents != null && targetCents.abs() < 5;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final entry in _strings.entries)
                ChoiceChip(
                  label: Text('${entry.key} · ${entry.value.toStringAsFixed(0)}Hz'),
                  selected: _target == entry.key,
                  onSelected: (_) => setState(() => _target = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            _running ? (info?.name ?? '…') : '待启动',
            style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold),
          ),
          Text(pitch == null
              ? '未检测到音高（置信度 ${_probability.toStringAsFixed(2)}）'
              : '${pitch.toStringAsFixed(1)} Hz · 置信度 ${_probability.toStringAsFixed(2)}'),
          const SizedBox(height: 16),
          SizedBox(
            width: 280,
            child: Column(
              children: [
                Text(targetCents == null
                    ? '相对 $_target 弦：-'
                    : '相对 $_target 弦：${targetCents.toStringAsFixed(0)} ¢'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 14,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: inTune ? Colors.green.shade200 : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      Align(
                        alignment: Alignment(
                            ((targetCents ?? 0) / 50).clamp(-1.0, 1.0), 0),
                        child: Container(
                          width: 4,
                          height: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (inTune)
            const Text('✔ 已调准', style: TextStyle(color: Colors.green, fontSize: 18)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _toggle,
            child: Text(_running ? '停止' : '开始调音'),
          ),
        ],
      ),
    );
  }
}
