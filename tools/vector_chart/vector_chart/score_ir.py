"""解码模型 → 识谱源 ScoreIR JSON(schemaVersion 1)。

与 lib/core/import/score_ir.dart 逐字段对齐(键 lowerCamelCase):
拍格骨架平铺、双声部带拍长闭合所需的 voice rests、卷弦 roll、
和弦锚(指形 ④③②① 序,复用运行时 ChordFingering 语义)、逐音证据。
弱起约定:第 1 小节内容右对齐(印张弱起=尾拍进第 1 小节,时序保真)。
tie 照读不并(延续音=独立拍位上的音,物化器既有约定)。
"""
from __future__ import annotations

from .decode_tab import STRING_MIDI, Bar, Column, DecodedTab


def _midi(string: int, fret: int) -> int:
    return STRING_MIDI[string] + fret


def _evidence(bar_no: int, x: float, source: str) -> dict:
    return {
        'page': bar_no,  # 小节号,利于人工回查渲染件
        'bbox': [round(x - 1.0, 1), 0.0, 12.0, 12.0],
        'source': source,
        'confidence': 1.0,
    }


def _voice_json(bars: list[Bar], voice_attr: str, pickup_pad: float,
                beats_per_measure: float, source: str) -> dict:
    """一个声部:notes + 声部休止(拍长闭合)。

    弱起:第 1 小节先垫 [pickup_pad] 拍休止;各小节内按列序走,
    声部空档落 voice rest(校验器逐小节闭合核对的对账项)。
    """
    notes: list[dict] = []
    rests: list[dict] = []
    cursor = 0.0
    if pickup_pad > 0:
        rests.append({'beat': 0.0, 'beats': pickup_pad})
        cursor = pickup_pad
    for bi, b in enumerate(bars):
        bar_start = bi * beats_per_measure
        pad = pickup_pad if bi == 0 else 0.0
        events = [(c.beat, c) for c in b.columns if getattr(c, voice_attr)]
        for col_beat, c in events:
            at = bar_start + pad + col_beat
            if at > cursor + 1e-6:
                rests.append({'beat': round(cursor, 4),
                              'beats': round(at - cursor, 4)})
            for n in getattr(c, voice_attr):
                notes.append({
                    'beat': round(at, 4),
                    'durationBeats': round(c.duration or 0.0, 4),
                    'string': n.string,
                    'fret': n.fret,
                    'midi': _midi(n.string, n.fret),
                    'evidence': _evidence(b.number, c.x, source),
                })
            cursor = at + (c.duration or 0.0)
        bar_end = bar_start + beats_per_measure
        if cursor < bar_end - 1e-6:
            rests.append({'beat': round(cursor, 4),
                          'beats': round(bar_end - cursor, 4)})
        cursor = max(cursor, bar_end)
    return {'notes': notes, 'rests': rests}


def _chord_anchors(bars: list[Bar], beats_per_measure: float, source: str) -> list[dict]:
    anchors: list[dict] = []
    prev_label = None
    for bi, b in enumerate(bars):
        for shape in b.chords:
            # 锚拍 = 图 x 右侧最近列;无列则小节首拍
            beat_col = None
            for c in b.columns:
                if c.x >= shape.x - 12:
                    beat_col = c
                    break
            pad = pickup_pad if bi == 0 else 0.0
            beat = (bi * beats_per_measure + pad
                    + (beat_col.beat if beat_col and beat_col.beat is not None else 0.0))
            if shape.label == prev_label and anchors:
                continue  # 同名延续不重锚(金标准惯例)
            prev_label = shape.label
            anchors.append({
                'beat': round(beat, 4),
                'label': shape.label,
                'fingering': {
                    # 图纵线左→右即 ④③②①,IR 同序;品位 = 窗口相对(baseFret
                    # 语义照 ChordFingering:绝对品 = frets + baseFret - 1)
                    'frets': list(shape.frets),
                    'fingers': [0, 0, 0, 0],
                    'baseFret': shape.base_fret,
                    'barres': [],
                },
                'evidence': _evidence(b.number, shape.x, source),
            })
    return anchors


def build_score_ir(dt: DecodedTab, chart_id: str, source: str,
                   skip_measures: int = 0) -> tuple[dict, dict]:
    """→ (ScoreIR JSON dict, 附加信息 dict(小节数/红旗))。

    [skip_measures] = 弱起垫掉的整拍数(第 1 小节内容右对齐;骨架仍全小节)。
    """
    bpm_measure = float(dt.meter[0])
    total_bars = len(dt.bars)
    bars = dt.bars
    # 弱起:第 1 小节内容总长 < 整小节 → 右对齐,垫左侧休止
    pickup_pad = 0.0
    if bars and bars[0].total_duration < bpm_measure - 1e-6:
        pickup_pad = bpm_measure - bars[0].total_duration
    from .decode_tab import split_voices
    split_voices(dt)

    ir = {
        'schemaVersion': 1,
        'id': chart_id,
        'title': dt.title,
        'artist': dt.artist,
        'meter': {'beatsPerMeasure': dt.meter[0], 'beatUnit': dt.meter[1]},
        'tempoMap': [{'beat': 0.0, 'bpm': dt.bpm}],
        'keyMap': [{'beat': 0.0, 'key': dt.key}],
        'measures': [
            {'number': n + 1, 'startBeat': round(n * bpm_measure, 4)}
            for n in range(total_bars)
        ],
        'melodyAlignBeats': 0.0,
        'tabChartId': chart_id,
        'melodyChartId': f'{chart_id}-melody',
        'voices': {
            'melody': _voice_json(bars, 'melody', pickup_pad, bpm_measure, source),
            'accompaniment': _voice_json(bars, 'accompaniment', pickup_pad,
                                         bpm_measure, source),
        },
        'rests': [],
        'slides': [],
        'tremolos': [],
        'strums': [],
        'chordAnchors': _chord_anchors(bars, bpm_measure, source),
        'unsupportedSymbols': [],
        'review': {},
    }
    # 卷弦事件
    for bi, b in enumerate(bars):
        for c in b.columns:
            if c.roll and c.beat is not None:
                pad = pickup_pad if bi == 0 else 0.0
                ir['strums'].append({
                    'beat': round(bi * bpm_measure + pad + c.beat, 4),
                    'kind': 'roll',
                    'evidence': _evidence(b.number, c.x, source),
                })
    extra = {
        'pickupPad': pickup_pad,
        'bars': total_bars,
        'harmonicBars': [b.number for b in bars
                         if any(n.harmonic for c in b.columns for n in c.notes)],
        'sections': dt.sections,
        'warnings': list(dt.warnings),
    }
    return ir, extra
