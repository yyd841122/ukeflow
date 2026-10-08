import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Spike B：flutter_soloud playClocked 精确节拍调度。
/// 通过标准：600 拍（5 分钟 @120bpm）全部调度成功；引擎时钟与挂钟漂移 <20ms；
/// 听感节拍均匀、无爆音；"立即一声"主观延迟可接受。
class SchedulerPage extends StatefulWidget {
  const SchedulerPage({super.key});

  @override
  State<SchedulerPage> createState() => _SchedulerPageState();
}

class _SchedulerPageState extends State<SchedulerPage> {
  static const _lookahead = Duration(milliseconds: 400);
  static const _totalBeats = 600;

  final _bpmCtrl = TextEditingController(text: '120');

  AudioSource? _tick;
  bool _engineReady = false;
  String _engineError = '';
  bool _running = false;

  int _scheduled = 0;
  int _heard = 0;
  double _maxDriftMs = 0;
  DateTime? _t0Wall;
  Duration _t0Engine = Duration.zero;
  final List<SoundHandle> _handles = [];
  Timer? _schedTimer;
  Timer? _uiTimer;

  double get _periodMs => 60000 / (double.tryParse(_bpmCtrl.text) ?? 120);

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init(
          sampleRate: 44100,
          bufferSize: 1024,
          channels: Channels.mono,
          lowLatency: true,
        );
      }
      final wav = _buildTickWav(sampleRate: 44100, ms: 90, freq: 1000);
      _tick = await SoLoud.instance.loadMem('tick', wav, mode: LoadMode.memory);
      if (mounted) setState(() => _engineReady = true);
    } catch (e) {
      if (mounted) setState(() => _engineError = '$e');
    }
  }

  @override
  void dispose() {
    _schedTimer?.cancel();
    _uiTimer?.cancel();
    if (SoLoud.instance.isInitialized) SoLoud.instance.deinit();
    _bpmCtrl.dispose();
    super.dispose();
  }

  Uint8List _buildTickWav({
    required int sampleRate,
    required int ms,
    required double freq,
  }) {
    final sampleCount = sampleRate * ms ~/ 1000;
    final pcm = Uint8List(sampleCount * 2);
    final view = ByteData.view(pcm.buffer);
    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final env = math.exp(-t * 35);
      final v =
          (math.sin(2 * math.pi * freq * t) * env * 0.85 * 32767).round();
      view.setInt16(i * 2, v.clamp(-32768, 32767).toInt(), Endian.little);
    }
    final out = BytesBuilder();
    final u32 = ByteData(4);
    final u16 = ByteData(2);
    void u32le(int v) {
      u32.setInt32(0, v, Endian.little);
      out.add(u32.buffer.asUint8List());
    }

    void u16le(int v) {
      u16.setUint16(0, v, Endian.little);
      out.add(u16.buffer.asUint8List());
    }

    void str(String s) => out.add(ascii.encode(s));
    str('RIFF');
    u32le(36 + pcm.length);
    str('WAVE');
    str('fmt ');
    u32le(16);
    u16le(1);
    u16le(1);
    u32le(sampleRate);
    u32le(sampleRate * 2);
    u16le(2);
    u16le(16);
    str('data');
    u32le(pcm.length);
    out.add(pcm);
    return out.takeBytes();
  }

  void _start() {
    _scheduled = 0;
    _heard = 0;
    _maxDriftMs = 0;
    _handles.clear();
    _t0Engine = SoLoud.instance.getEngineTime();
    _t0Wall = DateTime.now();
    setState(() => _running = true);
    _schedTimer = Timer.periodic(
        const Duration(milliseconds: 40), (_) => _scheduleAhead());
    _uiTimer =
        Timer.periodic(const Duration(milliseconds: 100), (_) => _monitor());
  }

  void _scheduleAhead() {
    final now = SoLoud.instance.getEngineTime();
    while (_scheduled < _totalBeats) {
      final t = _t0Engine +
          Duration(milliseconds: (_scheduled * _periodMs).round());
      if (t > now + _lookahead) break;
      _handles.add(SoLoud.instance.playClocked(_tick!, t));
      _scheduled++;
    }
    final endAt =
        _t0Engine + Duration(milliseconds: (_totalBeats * _periodMs + 2000).round());
    if (_scheduled >= _totalBeats && now >= endAt) {
      _finish();
    }
  }

  void _monitor() {
    final now = SoLoud.instance.getEngineTime();
    final engineElapsedUs = (now - _t0Engine).inMicroseconds;
    final wallElapsedUs =
        DateTime.now().difference(_t0Wall!).inMicroseconds;
    final driftMs = (engineElapsedUs - wallElapsedUs) / 1000.0;
    if (driftMs.abs() > _maxDriftMs.abs()) _maxDriftMs = driftMs;
    final heard = (engineElapsedUs / 1000 / _periodMs).floor() + 1;
    if (heard > _heard && heard <= _totalBeats) _heard = heard;
    setState(() {});
  }

  void _finish() {
    _schedTimer?.cancel();
    _uiTimer?.cancel();
    setState(() => _running = false);
  }

  void _panicStop() {
    _schedTimer?.cancel();
    _uiTimer?.cancel();
    for (final h in _handles) {
      SoLoud.instance.stop(h);
    }
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final elapsedMs = _running
        ? (SoLoud.instance.getEngineTime() - _t0Engine).inMilliseconds
        : 0;
    final phase = _running ? (elapsedMs % _periodMs) / _periodMs : 1.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            _engineError.isNotEmpty
                ? '引擎初始化失败：$_engineError'
                : _engineReady
                    ? '引擎就绪 · 44.1kHz · buffer 1024 · mono · lowLatency'
                    : '引擎初始化中…',
            style: TextStyle(
                color: _engineError.isNotEmpty ? Colors.red : Colors.green),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('BPM'),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _bpmCtrl,
                  keyboardType: TextInputType.number,
                  enabled: !_running,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 16),
              Text('目标：$_totalBeats 拍（5 分钟）'),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: phase < 0.25 ? Colors.orange : Colors.orange.shade100,
            ),
            child: Center(
              child: Text(
                _running ? '$_heard' : '·',
                style: const TextStyle(fontSize: 36),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('已调度 $_scheduled / $_totalBeats · 已听 $_heard\n'
              '引擎-挂钟最大漂移 ${_maxDriftMs.toStringAsFixed(1)} ms'),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton(
                onPressed:
                    !_engineReady || _running ? null : _start,
                child: const Text('开始 5 分钟测试'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _running ? _panicStop : null,
                child: const Text('紧急停止'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed:
                    _engineReady ? () => SoLoud.instance.playClocked(
                        _tick!,
                        SoLoud.instance.getEngineTime() +
                            const Duration(milliseconds: 30)) : null,
                child: const Text('立即一声'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '通过标准：600 拍全调度、|漂移| < 20ms、听感均匀无爆音、\n"立即一声"主观延迟可接受',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
