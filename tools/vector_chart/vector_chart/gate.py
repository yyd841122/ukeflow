"""体检闸(ADR-0011):解码产物 JSON 的自动放行关卡。

规则镜像 lib/core/import/score_ir_validator.dart 的阻塞面(矢量源信任
等级:全绿自动入库,红旗只列疑点;权威校验仍在 App 物化端):
- schema/骨架/meter(v1 仅 4/4)/tempo/keyMap;
- 每声部每小节拍长闭合(音+声部休止严丝合缝,不许洞/叠/整小节空白);
- 弦品合法(1..4 弦,0..15 品),midi = 空弦 + fret;
- 同声部同拍同弦冲突;事件表升序且不出骨架;
- unsupportedSymbols 非空即阻塞(禁止静默丢)。

warnings(红旗,不阻塞):小节内容时长偏差、无符干列、全零指形、
泛音披露等——进人读报告。
"""
from __future__ import annotations

STRING_MIDI = {1: 69, 2: 64, 3: 60, 4: 67}
MAX_FRET = 15

_ROOT_PC = {'C': 0, 'C#': 1, 'DB': 1, 'D': 2, 'D#': 3, 'EB': 3, 'E': 4, 'F': 5,
            'F#': 6, 'GB': 6, 'G': 7, 'G#': 8, 'AB': 8, 'A': 9, 'A#': 10,
            'BB': 10, 'B': 11}


def _name_shape_mismatch(label: str, frets: list, base: int) -> str | None:
    """和弦名 ↔ 指形互证:音名解析 + 指形实际音高对照(矢量源红旗项)。"""
    import re as _re
    m = _re.fullmatch(r'([A-G][#B]?)(m7|maj7|sus4|m7b5|dim|7|m|)', label.strip(),
                      _re.IGNORECASE)
    if not m:
        return None
    root = m.group(1).upper().replace('B', 'B').replace('b', 'B')
    root = _re.sub(r'(?<=[A-G])b$', 'B', root)
    suffix = m.group(2).lower()
    if root not in _ROOT_PC:
        return None
    root_pc = _ROOT_PC[root]
    pcs = set()
    for i, f in enumerate(frets):
        if f == -1:
            continue
        abs_fret = f if f > 0 else 0
        if f > 0:
            abs_fret = f + base - 1
        string_no = 4 - i  # frets 下标 0 = ④
        pcs.add((STRING_MIDI[string_no] + abs_fret) % 12)
    if root_pc not in pcs:
        return f'根音 {root} 不在指形音集 {sorted(pcs)}'
    need = {'m': (0, 3, 7), '': (0, 4, 7), '7': (0, 4, 10),
            'm7': (0, 3, 10), 'maj7': (0, 4, 11), 'sus4': (0, 5, 7)}
    if suffix in need:
        missing = [iv for iv in need[suffix] if iv != 0 and iv not in
                   {(p - root_pc) % 12 for p in pcs}]
        if missing:
            return f'缺 {root}{suffix} 应有音程 {missing}'
    return None


def run_gate(ir: dict, extra: dict | None = None) -> tuple[list[str], list[str]]:
    """→ (errors 阻塞, warnings 红旗)。errors 空 = 自动放行。"""
    errors: list[str] = []
    warns: list[str] = list((extra or {}).get('warnings', []))

    if ir.get('schemaVersion') != 1:
        errors.append(f"schemaVersion 须为 1,实际 {ir.get('schemaVersion')}")
    if not str(ir.get('id', '')).strip():
        errors.append('id 为空')
    if not str(ir.get('title', '')).strip():
        errors.append('title 为空')

    meter = ir.get('meter', {})
    bpm_measure, beat_unit = meter.get('beatsPerMeasure'), meter.get('beatUnit')
    if not bpm_measure or not beat_unit:
        errors.append(f'拍号非法:{meter}')
    elif (bpm_measure, beat_unit) != (4, 4):
        errors.append(f'拍号 {bpm_measure}/{beat_unit}:v1 物化仅支持 4/4(票02 解除)')

    tempo = ir.get('tempoMap', [])
    if not tempo or tempo[0].get('beat') != 0:
        errors.append('tempoMap 首条必须落在拍 0')
    if len(tempo) > 1:
        errors.append('tempoMap 多条:v1 仅单速')
    keymap = ir.get('keyMap', [])
    if not keymap or keymap[0].get('beat') != 0:
        errors.append('keyMap 首条必须落在拍 0')
    if len(keymap) > 1:
        errors.append('keyMap 多条:v1 仅单调号')

    measures = ir.get('measures', [])
    n_measures = len(measures)
    grid_end = n_measures * (bpm_measure or 4)
    for i, m in enumerate(measures):
        if m.get('number') != i + 1:
            errors.append(f'measures 小节号须自 1 连续:第 {i + 1} 条 {m.get("number")}')
        if abs(m.get('startBeat', -1) - i * (bpm_measure or 4)) > 1e-6:
            errors.append(f"measures[{i}].startBeat 与拍号不符:{m}")

    voices = ir.get('voices', {})
    for name in ('melody', 'accompaniment'):
        v = voices.get(name)
        if v is None:
            errors.append(f'voices.{name} 缺失')
            continue
        _gate_voice(v, name, n_measures, bpm_measure or 4, errors, warns)

    for ev in ir.get('strums', []) + ir.get('tremolos', []) + ir.get('rests', []):
        b = ev.get('beat', 0.0)
        if b < -1e-6 or b >= grid_end:
            errors.append(f'事件拍位出骨架:{b}(骨架 0-{grid_end})')

    anchors = ir.get('chordAnchors', [])
    prev = -1.0
    for a in anchors:
        b = a.get('beat', 0.0)
        if b < prev - 1e-6:
            errors.append(f'和弦锚拍位非升序:@ {b}')
        prev = b
        fing = a.get('fingering', {})
        frets = fing.get('frets', [])
        base = fing.get('baseFret', 1)
        if len(frets) != 4:
            errors.append(f'和弦锚 {a.get("label")} 指形须 4 弦,实际 {frets}')
        elif all(f == 0 for f in frets):
            warns.append(f'和弦锚 {a.get("label")}@{b}:全零指形(全开放弦?)请目验')
        else:
            for f in frets:
                if f != -1 and not 0 <= f <= MAX_FRET:
                    errors.append(f'和弦锚 {a.get("label")} 品位越界:{f}')
                elif f not in (0, -1) and base > 1 and not 1 <= f <= 5:
                    warns.append(f'和弦锚 {a.get("label")}@{b}:窗口相对品 {f} '
                                 f'超出 4 空窗,请目验')
            bad = _name_shape_mismatch(a.get('label', ''), frets, base)
            if bad:
                warns.append(f'和弦锚 {a.get("label")}@{b}:{bad}(印张名称与指形'
                             f'不一致,按印张转录,请目验裁决)')

    if ir.get('unsupportedSymbols'):
        for u in ir['unsupportedSymbols']:
            errors.append(f'不支持记号「{u.get("kind")}」:禁止静默丢,须消解后导出')

    for kind in ('harmonicBars',):
        for bar_no in (extra or {}).get(kind, []):
            warns.append(f'第 {bar_no} 小节含 12 品自然泛音(<12>):按同品常音转录'
                         f'(音高相同,音色不计入运行时模型),请目验')
    for label, bar_no in (extra or {}).get('sections', []):
        warns.append(f'段落标注「{label}」@ 第 {bar_no} 小节:排版信息,不进识谱源')
    return errors, warns


def _gate_voice(v: dict, name: str, n_measures: int, bpm_measure: float,
                errors: list[str], warns: list[str]) -> None:
    notes = v.get('notes', [])
    rests = v.get('rests', [])
    if not notes:
        errors.append(f'{name} 声部没有任何音')
        return
    seen: set[tuple[float, int]] = set()
    for n in notes:
        s, f, midi = n.get('string'), n.get('fret'), n.get('midi')
        if s not in (1, 2, 3, 4):
            errors.append(f'{name}:弦号非法 {s}(须 1..4)')
            continue
        if not isinstance(f, int) or not 0 <= f <= MAX_FRET:
            errors.append(f'{name}:品位非法 {f}(须 0..{MAX_FRET})')
        if midi != STRING_MIDI[s] + f:
            errors.append(f'{name}:midi 与弦品不符 {midi} != {STRING_MIDI[s]}+{f}')
        key_ev = (round(n.get('beat', 0.0), 3), s)
        if key_ev in seen:
            errors.append(f'{name}:同拍同弦冲突 @{n.get("beat")} 弦{s}')
        seen.add(key_ev)
        db = n.get('durationBeats', 0.0)
        if not db or db <= 0:
            errors.append(f'{name}:durationBeats 非正 @{n.get("beat")}')
    # 逐小节拍长闭合:同拍多音 = 同一槽(和弦柱),槽长取该拍最大时值
    # (镜像 Dart 校验器「同拍多音并槽」口径);rest 表达空档,与音同拍则取并。
    slots: dict[float, float] = {}
    for n in notes:
        b = round(n['beat'], 4)
        slots[b] = max(slots.get(b, 0.0), round(n['durationBeats'], 4))
    for r in rests:
        b = round(r['beat'], 4)
        slots[b] = max(slots.get(b, 0.0), round(r['beats'], 4))
    beats_sorted = sorted(slots)
    for mi in range(n_measures):
        lo, hi = mi * bpm_measure, (mi + 1) * bpm_measure
        tiles = [(b, slots[b]) for b in beats_sorted if lo - 1e-6 <= b < hi - 1e-6]
        cursor = lo
        for b, d in tiles:
            if b > cursor + 1e-4:
                errors.append(f'{name}:第 {mi + 1} 小节拍 {cursor}-{b} 空洞(拍长不闭合)')
            elif b < cursor - 1e-4:
                errors.append(f'{name}:第 {mi + 1} 小节拍 {b} 重叠(前槽尾 {cursor:.2f})')
            cursor = max(cursor, b + d)
        if cursor < hi - 1e-4:
            errors.append(f'{name}:第 {mi + 1} 小节尾欠 {hi - cursor:.2f} 拍(拍长不闭合)')
        elif cursor > hi + 1e-4:
            errors.append(f'{name}:第 {mi + 1} 小节超出 {cursor - hi:.2f} 拍'
                          f'(末音延过小节线——跨小节延音须拆音,见校验器纪律)')
    if not rests and n_measures > 1:
        warns.append(f'{name}:无声部休止——若声部确有长音整曲填满可忽略,否则可疑')
