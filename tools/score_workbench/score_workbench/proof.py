"""校对台状态层(工单51,dev-only):识别草稿 → 逐小节人工确认 → ScoreIR。

纯函数模块(不依赖 Flask):会话=layout/melody/tab 三份 JSON 的可变副本,
人工编辑就地落副本、整包存 `proof.json`(重启不丢);导出按工单 42 schema
(score_ir.dart 的 JSON 交换契约,lowerCamelCase)装配,并带一份 preflight
镜像校验(Dart 校验器的关键规则的 Python 预演,权威仍在 App 端)。

映射约定(证据见各函数 docstring):
- 旋律度数+印张八度点 → midi:印张点数=应用点数+1(工单39 实测),两侧
  各自 max(0, p−1) 折回应用点数;度数按可动唱名(1=X 调号)换半音。
- midi → (弦,品):弦 ①→④ 取第一个 0..15 品的合法位(与 builtin 金标准
  逐音核对:G4→②3、C5→①3、A4→①0 同规;旋律层印张不印指位,此映射
  只服务 IR 的弦品必填,不影响对照/播放)。
- 伴奏声部休止 = 音槽间空洞自动补记(与内置导出器 _tileVoice「静默由
  休止簿记」同规),让「每声部拍长闭合」结构上恒可满足;旋律声部休止 =
  印张 0 号(识别草稿的休止行)照录,空洞留 preflight 报给人工。
- 印张 TAB 休止 → IR 顶层 rests(显示休止,主轴);印张简谱 0 → 旋律
  声部休止——与 IR schema 的「显示休止只在主轴」不对称性一致。
"""

from __future__ import annotations

import copy
import datetime
import json
import os
import re

PROOF_FILE = "proof.json"

# 弦号 → 空弦 midi(UkeString:①A=69 ②E=64 ③C=60 ④G=67,高音 G)。
OPEN_MIDI = {1: 69, 2: 64, 3: 60, 4: 67}

KEY_SEMITONE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
DEGREE_SEMITONE = {1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11}

# IR 声部外发的技巧种类;其余(shaft/ellipse)留在草稿证据里不导出。
STRUM_KINDS = ("roll", "strumUp", "strumDown")

_METER_RE = re.compile(r"^(\d+)/(\d+)$")
_EPS = 1e-6


# ── 会话:装/存/小节视图 ─────────────────────────────────────────────

def load_session(out_dir: str) -> dict:
    """out_dir 的 layout/melody/tab 三 JSON → 校对会话。

    `proof.json` 在则整包覆盖(人工编辑/确认状态赢过草稿原样);小节数
    对不上(草稿重认过)时确认表按新长度裁补,编辑以 proof.json 为准。"""
    out_dir = str(out_dir)
    layout = _read_json(os.path.join(out_dir, "layout.json"))
    melody = _read_json(os.path.join(out_dir, "melody.json"))
    tab = _read_json(os.path.join(out_dir, "tab.json"))
    stem = os.path.splitext(os.path.basename(layout["source"]["file"]))[0]
    header = melody.get("header", {})
    session = {
        "out_dir": out_dir,
        "layout": layout,
        "melody": melody,
        "tab": tab,
        "meta": {
            "id": stem,
            "title": stem,
            "artist": None,
            "key": header.get("key") or "1=C",
            "meter": header.get("meter") or "4/4",
            "tempo": header.get("tempo_bpm"),
            "melodyAlignBeats": 0.0,
        },
        "confirmed": [False] * len(melody["measures"]),
        "chords": [],          # 和弦锚:{measure, beat(小节内), label, fingering{}}
    }
    proof_path = os.path.join(out_dir, PROOF_FILE)
    if os.path.isfile(proof_path):
        saved = _read_json(proof_path)
        session["melody"] = saved["melody"]
        session["tab"] = saved["tab"]
        session["meta"].update(saved.get("meta", {}))
        session["chords"] = saved.get("chords", [])
        confirmed = saved.get("confirmed", [])
        n = len(session["melody"]["measures"])
        session["confirmed"] = (confirmed + [False] * n)[:n]
    return session


def save_session(session: dict) -> None:
    """整包落 `proof.json`(临时文件+rename 原子替换)。layout/crops 不进
    包(只读产物,大),存 melody/tab 编辑、meta、确认表、和弦锚。"""
    payload = {
        "schema": "ukeflow.workbench.proof/1",
        "saved_at": _now(),
        "melody": session["melody"],
        "tab": session["tab"],
        "meta": session["meta"],
        "confirmed": session["confirmed"],
        "chords": session["chords"],
    }
    path = os.path.join(session["out_dir"], PROOF_FILE)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def measure_count(session: dict) -> int:
    return len(session["melody"]["measures"])


def measure_view(session: dict, mi: int, errors: list | None = None) -> dict:
    """第 mi 小节的合并视图(右栏数据表 + 左栏叠图几何 + 本小节 preflight)。

    errors 缺省现算 preflight;调用方整包出视图时传入共享清单(清单一次
    算,69 小节逐个重算是 O(n²),评审 51 抓的)。只含本小节条目——全局
    错误(id/速度等)在顶部问题抽屉,不折进每个小节。"""
    melody_m = _measure_at(session["melody"], mi)
    tab_m = _measure_at(session["tab"], mi)
    if errors is None:
        errors = preflight(session)
    return {
        "index": mi,
        "system": (melody_m or tab_m or {}).get("system"),
        "x0": (melody_m or tab_m or {}).get("x0"),
        "x1": (melody_m or tab_m or {}).get("x1"),
        "start_beat": (melody_m or {}).get("start_beat",
                                           (tab_m or {}).get("start_beat")),
        "melody": melody_m,
        "tab": tab_m,
        "chords": chords_in_measure(session, mi),
        "confirmed": bool(session["confirmed"][mi])
        if mi < len(session["confirmed"]) else False,
        "errors": errors_in_measure(errors, mi),
    }


def chords_in_measure(session: dict, mi: int) -> list:
    out = [dict(c, index=i) for i, c in enumerate(session["chords"])
           if c["measure"] == mi]
    out.sort(key=lambda c: c["beat"])
    return out


def anchor_layer_to_grid(session: dict, layer: str) -> int:
    """逐小节重锚到小节网格(start_beat = 小节序×拍号),小节内事件拍位
    随差平移。旋律层 start_beat 是 read_beats 累加(工单49 装配口径),
    欠拍小节会让后续小节整体漂——拍长闭合逐小节窗核对抓不到跨小节重叠,
    重锚是校对台的正名动作(TAB 层识别端已网格锚定,此操作幂等)。"""
    meter = measure_beats(session)
    moved = 0
    for mi, m in enumerate(session[layer]["measures"]):
        delta = mi * meter - m["start_beat"]
        if abs(delta) < _EPS:
            continue
        m["start_beat"] = round(mi * meter, 6)
        for table in ("notes", "rests", "techniques", "x_marks"):
            for row in m.get(table, ()):
                if row.get("beat") is not None:
                    row["beat"] = round(row["beat"] + delta, 6)
                if row.get("to_beat") is not None:
                    row["to_beat"] = round(row["to_beat"] + delta, 6)
        moved += 1
    return moved


def measure_beats(session: dict) -> float:
    m = _METER_RE.match(str(session["meta"]["meter"] or ""))
    return float(m.group(1)) if m else 4.0


# ── 编辑操作(就地改会话;server 层负责持久化)────────────────────────

_META_FLOATS = ("tempo", "melodyAlignBeats")
_META_STRS = ("id", "title", "artist", "key", "meter")


def set_meta(session: dict, fields: dict) -> None:
    for k, v in fields.items():
        if k in _META_FLOATS:
            session["meta"][k] = None if v in (None, "") else float(v)
        elif k in _META_STRS:
            session["meta"][k] = None if v == "" else str(v)


def set_confirm(session: dict, mi: int, value: bool) -> None:
    session["confirmed"][mi] = bool(value)


def confirm_all(session: dict) -> None:
    session["confirmed"] = [True] * measure_count(session)


def _sorted_notes(measure: dict) -> None:
    measure["notes"].sort(key=lambda n: n["beat"])


def edit_note(session: dict, layer: str, mi: int, row: int, data: dict) -> None:
    """改一行音(旋律:degree/dots_above/dots_below/beat/duration;
    TAB:string/fret/beat/duration)。其余字段(x/evidence/缀记)照旧。"""
    note = _row(session, layer, mi, row, "notes")
    for k in ("degree", "dots_above", "dots_below"):
        if layer == "melody" and k in data:
            note[k] = None if data[k] in ("", None) else int(data[k])
    for k in ("string", "fret"):
        if layer == "tab" and k in data:
            note[k] = None if data[k] in ("", None) else int(data[k])
    for k in ("beat", "duration"):
        if k in data:
            note[k] = None if data[k] in ("", None) else float(data[k])
    _sorted_notes(_measure_at(session[layer], mi))


def add_note(session: dict, layer: str, mi: int, data: dict) -> None:
    note = {"beat": float(data["beat"]), "duration": _opt_float(data["duration"]),
            "confidence": None, "x": None, "evidence": None,
            "manual": True}
    if layer == "melody":
        note.update({"degree": _opt_int(data["degree"]),
                     "dots_above": int(data.get("dots_above") or 0),
                     "dots_below": int(data.get("dots_below") or 0)})
    else:
        note.update({"string": _opt_int(data["string"]),
                     "fret": _opt_int(data["fret"])})
    _measure_at(session[layer], mi)["notes"].append(note)
    _sorted_notes(_measure_at(session[layer], mi))


def delete_note(session: dict, layer: str, mi: int, row: int) -> None:
    notes = _measure_at(session[layer], mi)["notes"]
    notes.pop(_check_row(row, len(notes)))


def edit_rest(session: dict, layer: str, mi: int, row: int, data: dict) -> None:
    rest = _row(session, layer, mi, row, "rests")
    if "beat" in data:
        rest["beat"] = _opt_float(data["beat"])
    if "beats" in data:
        rest["beats"] = _opt_float(data["beats"])
    if layer == "tab" and "kind" in data:
        if data["kind"] not in ("rest8", "rest_whole"):
            raise ValueError(f"休止种类只能是 rest8/rest_whole,得 {data['kind']!r}")
        rest["kind"] = data["kind"]


def add_rest(session: dict, layer: str, mi: int, data: dict) -> None:
    kind = data.get("kind", "rest8") if layer == "tab" else None
    if kind not in (None, "rest8", "rest_whole"):
        raise ValueError(f"休止种类非法:{kind!r}")
    _measure_at(session[layer], mi)["rests"].append({
        "beat": _opt_float(data["beat"]), "beats": _opt_float(data["beats"]),
        "kind": kind, "x": None, "evidence": None, "manual": True,
    })


def delete_rest(session: dict, layer: str, mi: int, row: int) -> None:
    rests = _measure_at(session[layer], mi)["rests"]
    rests.pop(_check_row(row, len(rests)))


TECHNIQUE_KINDS = ("roll", "strumUp", "strumDown", "shaft", "slide",
                   "tremolo", "ellipse")


def edit_technique(session: dict, mi: int, row: int, data: dict) -> None:
    tech = _row(session, "tab", mi, row, "techniques")
    if "kind" in data:
        if data["kind"] not in TECHNIQUE_KINDS:
            raise ValueError(f"技巧种类非法:{data['kind']!r}")
        tech["kind"] = data["kind"]
    if "beat" in data:
        tech["beat"] = _opt_float(data["beat"])
    if "to_beat" in data:                      # 滑音止拍(export 用)
        tech["to_beat"] = _opt_float(data["to_beat"])


def add_technique(session: dict, mi: int, data: dict) -> None:
    kind = data.get("kind")
    if kind not in TECHNIQUE_KINDS:
        raise ValueError(f"技巧种类非法:{kind!r}(合法:{','.join(TECHNIQUE_KINDS)})")
    _measure_at(session["tab"], mi)["techniques"].append({
        "kind": kind, "beat": _opt_float(data["beat"]),
        "to_beat": _opt_float(data["to_beat"]), "x": None,
        "evidence": None, "manual": True,
    })


def delete_technique(session: dict, mi: int, row: int) -> None:
    techs = _measure_at(session["tab"], mi)["techniques"]
    techs.pop(_check_row(row, len(techs)))


def batch_technique(session: dict, data: dict) -> int:
    """批量技巧录入(票面在界内的重活上限):同一技巧按同一小节内拍位
    打进 [from, to] 小节区间,返回写入条数。"""
    kind = data.get("kind")
    if kind not in TECHNIQUE_KINDS:
        raise ValueError(f"技巧种类非法:{kind!r}")
    lo, hi = int(data["from_measure"]), int(data["to_measure"])
    local = float(data["beat"])
    meter = measure_beats(session)
    n = 0
    for mi in range(lo, hi + 1):
        m = _measure_at(session["tab"], mi)
        m["techniques"].append({"kind": kind, "beat": m["start_beat"] + local,
                                "to_beat": None, "x": None, "evidence": None,
                                "manual": True, "batch": f"每小节第 {local:g} 拍"})
        n += 1
    return n


def delete_x_mark(session: dict, mi: int, row: int) -> None:
    marks = _measure_at(session["tab"], mi)["x_marks"]
    marks.pop(_check_row(row, len(marks)))


def _validated_chord(chord_data: dict) -> tuple[str, list, list, int]:
    """和弦数据校验(× 还原与和弦锚共用):label 非空、frets 恰 4 项
    (④③②①)、fingers 4 项、baseFret ≥1。"""
    label = str(chord_data["label"]).strip()
    if not label:
        raise ValueError("和弦名为空")
    frets = [int(v) for v in chord_data["frets"]]
    if len(frets) != 4:
        raise ValueError(f"frets 须 4 项(④③②①),得 {len(frets)} 项")
    fingers = [int(v) for v in (chord_data.get("fingers") or [0, 0, 0, 0])]
    if len(fingers) != 4:
        raise ValueError(f"fingers 须 4 项,得 {len(fingers)} 项")
    base_fret = int(chord_data.get("baseFret") or 1)
    if base_fret < 1:
        raise ValueError(f"baseFret 须 ≥1,得 {base_fret}")
    return label, frets, fingers, base_fret


def expand_x_mark(session: dict, mi: int, row: int, chord_data: dict) -> dict:
    """× 拨痕 → 音(GLOSSARY:还原须查当小节和弦指形,归校对台)。

    chord_data = {label, frets[④③②①](−1 闷音/0 空弦/窗口相对), fingers?,
    baseFret?}。和弦锚同拍没有同 label 的就落一个;发声弦(fret≥0)与 ×
    弦号证据(已知时)取交集,逐弦建音;时值 = 至同小节下一 attack 的
    距离,无下一 attack 则收到小节线。返回建的音数。"""
    measure = _measure_at(session["tab"], mi)
    marks = measure["x_marks"]
    mark = marks[_check_row(row, len(marks))]
    label, frets, fingers, base_fret = _validated_chord(chord_data)
    beat = float(mark["beat"])
    meter = measure_beats(session)
    local = beat - measure["start_beat"]

    anchor = next((c for c in session["chords"]
                   if c["measure"] == mi and abs(c["beat"] - local) < _EPS
                   and c["label"] == label), None)
    if anchor is None:
        anchor = {"measure": mi, "beat": local, "label": label,
                  "fingering": {"frets": frets, "fingers": fingers,
                                "baseFret": base_fret, "barres": []}}
        session["chords"].append(anchor)

    x_strings = mark.get("strings") or None
    created = 0
    for i, f in enumerate(frets):              # 下标 0 = ④ 弦(GLOSSARY 弦序)
        string = 4 - i
        if f < 0:
            continue
        fret = 0 if f == 0 else f + base_fret - 1   # 窗口相对 → 绝对品位
        if x_strings is not None and string not in x_strings:
            continue
        nxt = min((n["beat"] for n in measure["notes"] if n["beat"] > beat
                   + _EPS), default=None)
        duration = (nxt - beat if nxt is not None
                    else measure["start_beat"] + meter - beat)
        measure["notes"].append({
            "string": string, "fret": fret, "beat": beat,
            "duration": round(duration, 4), "confidence": None,
            "x": mark.get("x"), "evidence": mark.get("evidence"),
            "manual": f"×还原({label})",
        })
        created += 1
    _sorted_notes(measure)
    marks.pop(row)
    return {"created": created}


def add_chord(session: dict, mi: int, data: dict) -> None:
    session["chords"].append(_chord_from(mi, data))


def edit_chord(session: dict, index: int, data: dict) -> None:
    chords = session["chords"]
    chords[_check_row(index, len(chords))] = _chord_from(
        chords[index]["measure"], {**chords[index], **data})


def delete_chord(session: dict, index: int) -> None:
    session["chords"].pop(_check_row(index, len(session["chords"])))


def _chord_from(mi: int, data: dict) -> dict:
    label, frets, fingers, base_fret = _validated_chord(data)
    return {"measure": int(mi), "beat": float(data["beat"]), "label": label,
            "fingering": {"frets": frets, "fingers": fingers,
                          "baseFret": base_fret, "barres": []}}


# ── 草稿视图(diff 复用 + 导出原料)────────────────────────────────

def current_melody_draft(session: dict) -> dict:
    """编辑后的旋律草稿(diff_melody 直接吃):小节内音按拍位排序。"""
    draft = copy.deepcopy(session["melody"])
    for m in draft["measures"]:
        _sorted_notes(m)
    return draft


def current_tab_draft(session: dict) -> dict:
    draft = copy.deepcopy(session["tab"])
    for m in draft["measures"]:
        _sorted_notes(m)
    return draft


# ── 印张 → midi → 弦品 ─────────────────────────────────────────────

def degree_to_midi(key: str, degree: int, dots_above: int, dots_below: int
                   ) -> int:
    """度数+印张八度点 → midi(可动唱名)。

    印张点数 = 应用点数 + 1(工单39 sys01 实测 5̇=G4),两侧各自折回:
    应用点数 = max(0, p−1)。基音 = C4 起 + 调号偏移(1=E → 度1=E4=64)。"""
    koff = _key_offset(key)
    if degree not in DEGREE_SEMITONE:
        raise ValueError(f"度数 {degree} 非法(1..7)")
    octaves = max(0, int(dots_above) - 1) - max(0, int(dots_below) - 1)
    return 60 + koff + DEGREE_SEMITONE[degree] + 12 * octaves


def _key_offset(key: str) -> int:
    m = re.match(r"^1\s*=\s*([A-G])([#b]?)$", str(key or "").strip())
    if not m:
        raise ValueError(f"调号 {key!r} 读不懂(要 1=X 形)")
    semi = KEY_SEMITONE[m.group(1)]
    return semi + (1 if m.group(2) == "#" else -1 if m.group(2) == "b" else 0)


def midi_to_tab(midi: int) -> tuple[int, int] | None:
    """midi → (弦,品):弦 ①→④ 取第一个 0..15 品合法位(见模块 docstring
    的金标准核对)。无处可放(低于 ③ 空弦域外/品 >15)给 None。"""
    for string in (1, 2, 3, 4):
        fret = midi - OPEN_MIDI[string]
        if 0 <= fret <= 15:
            return string, fret
    return None


# ── ScoreIR 导出(工单 42 schema,JSON 交换契约)────────────────────

def build_ir(session: dict, reviewed_at: str | None = None) -> tuple[dict, list]:
    """会话 → (ScoreIR dict, skipped)。

    skipped = [{measure, what, why}]:映射不了的事件(未知度数/缺弦号/
    缺时值/滑音缺止拍)不进 IR——**不静默**,由调用方连同 preflight 报给
    人工;preflight 全绿时 skipped 恒空。伴奏声部休止按音槽空洞自动补记
    (模块 docstring),显示休止只收印张 TAB 休止。"""
    meta = session["meta"]
    meter = measure_beats(session)
    skipped: list[dict] = []
    n_measures = measure_count(session)
    sys_pages = _system_pages(session["layout"])

    accomp_notes, accomp_voice_rests, display_rests = [], [], []
    slides, tremolos, strums = [], [], []
    for mi, measure in enumerate(session["tab"]["measures"]):
        sys_i = _sys_of(session, mi)
        slots: list[tuple[float, float]] = []
        for n in sorted(measure["notes"], key=lambda n: n["beat"]):
            if n["string"] is None or n["fret"] is None or not n.get(
                    "duration"):
                skipped.append({"measure": mi + 1, "what": "伴奏音",
                                "why": _why_note(n)})
                continue
            accomp_notes.append(_ir_note(n))
            slots.append((n["beat"], n["beat"] + n["duration"]))
        accomp_voice_rests.extend(_gap_rests(slots, measure["start_beat"],
                                             meter))
        for r in measure["rests"]:
            beats = meter if r["kind"] == "rest_whole" else r.get("beats")
            if not beats:
                skipped.append({"measure": mi + 1, "what": "显示休止",
                                "why": "拍数未知,先补时值"})
                continue
            display_rests.append({
                "beat": r["beat"], "beats": beats,
                "evidence": _ir_evidence(r, sys_i, sys_pages),
            })
        for t in measure["techniques"]:
            kind = t["kind"]
            if kind == "tremolo":
                tremolos.append({"beat": t["beat"],
                                 "evidence": _ir_evidence(t, sys_i, sys_pages)})
            elif kind in STRUM_KINDS:
                strums.append({"beat": t["beat"], "kind": kind,
                               "evidence": _ir_evidence(t, sys_i, sys_pages)})
            elif kind == "slide":
                if not t.get("to_beat"):
                    skipped.append({"measure": mi + 1, "what": "滑音",
                                    "why": "缺止拍,先在技巧行补 to_beat"})
                    continue
                slides.append({"fromBeat": t["beat"], "toBeat": t["to_beat"],
                               "evidence": _ir_evidence(t, sys_i, sys_pages)})
            # shaft/ellipse:草稿证据保留,IR 无此概念,不导出(README 注明)

    melody_notes, melody_rests = [], []
    for mi, measure in enumerate(session["melody"]["measures"]):
        sys_i = _sys_of(session, mi)
        for n in sorted(measure["notes"], key=lambda n: n["beat"]):
            if n["degree"] is None or not n.get("duration"):
                skipped.append({"measure": mi + 1, "what": "旋律音",
                                "why": _why_note(n)})
                continue
            try:
                midi = degree_to_midi(meta["key"], n["degree"],
                                      n.get("dots_above") or 0,
                                      n.get("dots_below") or 0)
            except ValueError as exc:
                skipped.append({"measure": mi + 1, "what": "旋律音",
                                "why": str(exc)})
                continue
            spot = midi_to_tab(midi)
            if spot is None:
                skipped.append({"measure": mi + 1, "what": "旋律音",
                                "why": f"midi {midi} 落不进四弦域(度"
                                       f"{n['degree']}+点)"})
                continue
            entry = {
                "beat": n["beat"], "durationBeats": n["duration"],
                "string": spot[0], "fret": spot[1], "midi": midi,
                "evidence": _ir_evidence(n, sys_i, sys_pages),
            }
            lyric = n.get("lyric")
            if lyric:
                entry["lyric"] = lyric
            melody_notes.append(entry)
        for r in measure["rests"]:
            if not r.get("beats"):
                skipped.append({"measure": mi + 1, "what": "旋律休止",
                                "why": "拍数未知,先补时值"})
                continue
            melody_rests.append({"beat": r["beat"], "beats": r["beats"],
                                 "evidence": _ir_evidence(r, sys_i, sys_pages)})

    chords = []
    for c in sorted(session["chords"],
                    key=lambda c: (_main_beat(session, c), c["beat"])):
        chords.append({"beat": _main_beat(session, c), "label": c["label"],
                       "fingering": c["fingering"]})

    ir = {
        "schemaVersion": 1,
        "id": meta["id"],
        "title": meta["title"],
        "artist": meta["artist"],
        "meter": {"beatsPerMeasure": int(meter), "beatUnit": 4},
        "tempoMap": [{"beat": 0.0, "bpm": int(meta["tempo"])}]
        if meta["tempo"] else [],
        "keyMap": [{"beat": 0.0, "key": meta["key"]}] if meta["key"] else [],
        "measures": [{"number": i + 1, "startBeat": i * meter}
                     for i in range(n_measures)],
        "melodyAlignBeats": float(meta["melodyAlignBeats"] or 0.0),
        "tabChartId": f"{meta['id']}-tab",
        "melodyChartId": f"{meta['id']}-melody",
        "voices": {
            "melody": {"notes": melody_notes, "rests": melody_rests},
            "accompaniment": {"notes": accomp_notes,
                              "rests": accomp_voice_rests},
        },
    }
    if display_rests:
        ir["rests"] = sorted(display_rests, key=lambda r: r["beat"])
    if slides:
        ir["slides"] = sorted(slides, key=lambda s: s["fromBeat"])
    if tremolos:
        ir["tremolos"] = sorted(tremolos, key=lambda t: t["beat"])
    if strums:
        ir["strums"] = sorted(strums, key=lambda s: s["beat"])
    if chords:
        ir["chordAnchors"] = chords
    if reviewed_at:
        ir["review"] = {"reviewedAt": reviewed_at}
    return ir, skipped


def _main_beat(session: dict, chord: dict) -> float:
    m = _measure_at(session["tab"], chord["measure"])
    start = m["start_beat"] if m else chord["measure"] * measure_beats(session)
    return start + chord["beat"]


def _ir_note(n: dict) -> dict:
    midi = OPEN_MIDI[n["string"]] + n["fret"]
    entry = {"beat": n["beat"], "durationBeats": n["duration"],
             "string": n["string"], "fret": n["fret"], "midi": midi,
             "evidence": None}
    ev = n.get("evidence")
    if ev:
        entry["evidence"] = {"bbox": ev.get("bbox"),
                             "confidence": ev.get("confidence")}
        if entry["evidence"]["confidence"] is None:
            del entry["evidence"]["confidence"]
        if entry["evidence"]["bbox"] is None:
            del entry["evidence"]["bbox"]
        if not entry["evidence"]:
            entry["evidence"] = None
    return entry


def _sys_of(session: dict, mi: int) -> int | None:
    m = _measure_at(session["melody"], mi) or _measure_at(session["tab"], mi)
    return m.get("system") if m else None


def _ir_evidence(row: dict, sys_index: int | None, sys_pages: dict) -> dict | None:
    """ScoreIrEvidence:识别行带 bbox/置信度(页码按所属系统折);人工行
    只落 source(如「×还原(Am)」/「manual」)。证据链纪律:能带的都带。"""
    ev = row.get("evidence")
    out = {}
    if ev:
        if ev.get("bbox"):
            out["bbox"] = ev["bbox"]
        if ev.get("confidence") is not None:
            out["confidence"] = ev["confidence"]
        if "bbox" in out and sys_index is not None \
                and sys_pages.get(sys_index) is not None:
            out["page"] = sys_pages[sys_index]
    if row.get("manual"):
        out["source"] = row["manual"] if isinstance(row["manual"], str) \
            else "manual"
    return out or None


def _gap_rests(slots: list[tuple[float, float]], start: float,
               meter: float) -> list[dict]:
    """音槽空洞 → 声部休止簿记(与内置导出器同规:首音前/音间/整小节;
    音间静默若前音时值已盖住则不另立)。"""
    rests = []
    cursor = start
    for s, e in sorted(slots):
        if s > cursor + _EPS:
            rests.append({"beat": cursor, "beats": round(s - cursor, 6)})
        cursor = max(cursor, e)
    end = start + meter
    if not slots:
        rests.append({"beat": start, "beats": meter})
    elif cursor < end - _EPS:
        rests.append({"beat": cursor, "beats": round(end - cursor, 6)})
    return rests


def _system_pages(layout: dict) -> dict[int, int]:
    out = {}
    for page in layout["score_pages"]:
        for s in page["systems"]:
            out[s["index"]] = page["index"]
    return out


# ── preflight(Dart 校验器关键规则的镜像预演;权威在 App 端)────────

def preflight(session: dict) -> list[dict]:
    """阻塞错误清单:[{measure(1 起,全局性为 None), field, message}]。

    只演 App 端 validateScoreIr 会拦的规则(id/title/拍位闭合/弦品界/
    同弦同刻/滑音端点/骨架界),供导出前把清单喂给人工;通过 = 空表。"""
    errors: list[dict] = []
    meta = session["meta"]
    if not str(meta["id"] or "").strip():
        errors.append({"measure": None, "field": "id", "message": "曲目 id 为空"})
    if not str(meta["title"] or "").strip():
        errors.append({"measure": None, "field": "title", "message": "曲名为空"})
    if not meta["tempo"] or meta["tempo"] <= 0:
        errors.append({"measure": None, "field": "tempo",
                       "message": "速度缺失或非法(页眉没读出,人工补)"})
    try:
        _key_offset(meta["key"])
    except ValueError as exc:
        errors.append({"measure": None, "field": "key", "message": str(exc)})
    if not _METER_RE.match(str(meta["meter"] or "")):
        errors.append({"measure": None, "field": "meter",
                       "message": f"拍号 {meta['meter']!r} 读不懂(要 n/4 形)"})

    nm, nt = measure_count(session), len(session["tab"]["measures"])
    if nm != nt:
        errors.append({"measure": None, "field": "measures",
                       "message": f"旋律 {nm} 小节 ≠ TAB {nt} 小节(草稿不同源?)"})
    meter = measure_beats(session)
    total = nm * meter
    align = float(meta["melodyAlignBeats"] or 0.0)

    # 小节起点须在小节网格上(Dart 端 measures.startBeat 是均匀网格、闭合
    # 按均匀窗核对;草稿旋律层起点是 read_beats 累加,欠拍小节整体漂——
    # 逐小节窗各自闭合抓不到跨小节重叠,先重锚再导出,评审 51 定的闸)。
    for layer in ("melody", "tab"):
        for mi, m in enumerate(session[layer]["measures"]):
            want = mi * meter
            if abs(m["start_beat"] - want) > _EPS:
                errors.append({"measure": mi + 1, "field": "anchor",
                               "message": f"{'旋律' if layer == 'melody' else 'TAB'}"
                               f"层第 {mi + 1} 小节起点 @{m['start_beat']:g} 偏离"
                               f"网格 @{want:g}(欠拍小节漂移),先「重锚」"})

    _check_voice(session, "melody", range(nm), errors, shift=align,
                 total=total)
    _check_voice(session, "tab", range(nt), errors, shift=0.0, total=total)

    accomp_beats = {round(n["beat"], 6)
                    for m in session["tab"]["measures"]
                    for n in m["notes"] if n["string"] is not None}
    for mi, measure in enumerate(session["tab"]["measures"]):
        for t in measure["techniques"]:
            if t["kind"] == "slide" and t.get("to_beat") is not None:
                if round(t["to_beat"], 6) not in accomp_beats:
                    errors.append({"measure": mi + 1, "field": "slide",
                                   "message": f"滑音止拍 @{t['to_beat']:g} "
                                   "不落在伴奏任何音上"})
            if t["beat"] is not None and not (0 <= t["beat"] <= total + _EPS):
                errors.append({"measure": mi + 1, "field": "technique",
                               "message": f"技巧 {t['kind']} 拍位 "
                               f"@{t['beat']:g} 出骨架(0..{total:g})"})
    for c in session["chords"]:
        beat = _main_beat(session, c)
        if not (0 <= beat <= total + _EPS):
            errors.append({"measure": c["measure"] + 1, "field": "chord",
                           "message": f"和弦锚 {c['label']} 拍位 @{beat:g} 出骨架"})
        for f in c["fingering"]["frets"]:
            if f != -1 and (f < 0 or (f > 0 and f + c["fingering"]["baseFret"]
                                      - 1 > 15)):
                errors.append({"measure": c["measure"] + 1, "field": "chord",
                               "message": f"和弦 {c['label']} 指形品位荒唐"
                               f"(frets={c['fingering']['frets']})"})
                break
    return errors


def _check_voice(session: dict, layer: str, mis: range, errors: list,
                 shift: float, total: float) -> None:
    name = "旋律" if layer == "melody" else "伴奏"
    meter = measure_beats(session)
    key = session["meta"]["key"]
    for mi in mis:
        measure = _measure_at(session[layer], mi)
        if measure is None:
            continue
        slots: list[tuple[float, float, str]] = []
        seen: set[tuple[int, float]] = set()
        for n in sorted(measure["notes"], key=lambda n: n["beat"]):
            at = f"{name}音@{n['beat']:g}"
            if n["beat"] is None or n["beat"] < 0:
                errors.append({"measure": mi + 1, "field": layer,
                               "message": f"{at} 拍位非法"})
                continue
            if layer == "melody":
                if n["degree"] is None:
                    errors.append({"measure": mi + 1, "field": layer,
                                   "message": f"{at} 度数未知(识别保槽位),先校对"})
                elif n.get("dots_above") and n.get("dots_below"):
                    errors.append({"measure": mi + 1, "field": layer,
                                   "message": f"{at} 上下同时带八度点,印张读歧"})
                if n["degree"] is not None:
                    try:
                        midi = degree_to_midi(key, n["degree"],
                                              n.get("dots_above") or 0,
                                              n.get("dots_below") or 0)
                        if midi_to_tab(midi) is None:
                            errors.append({"measure": mi + 1,
                                           "field": layer,
                                           "message": f"{at} midi {midi} "
                                           "落不进四弦域"})
                    except ValueError as exc:
                        errors.append({"measure": mi + 1, "field": layer,
                                       "message": f"{at} {exc}"})
            else:
                if n["string"] is None:
                    errors.append({"measure": mi + 1, "field": layer,
                                   "message": f"{at} 弦号未知(警告层已记),先校对"})
                if n["fret"] is None:
                    errors.append({"measure": mi + 1, "field": layer,
                                   "message": f"{at} 品位缺失"})
                if n["string"] is not None and n["string"] not in OPEN_MIDI:
                    errors.append({"measure": mi + 1, "field": layer,
                                   "message": f"{at} 弦号 {n['string']} 越界(1..4)"})
                elif n["string"] is not None and n["fret"] is not None:
                    if not (0 <= n["fret"] <= 15):
                        errors.append({"measure": mi + 1, "field": layer,
                                       "message": f"{at} 品位 {n['fret']} 越界(0..15)"})
                    key2 = (n["string"], round(n["beat"], 6))
                    if key2 in seen:
                        errors.append({"measure": mi + 1, "field": layer,
                                       "message": f"{name}声部同弦同刻冲突:"
                                       f"弦{n['string']} @{n['beat']:g} 多音"})
                    seen.add(key2)
            if not n.get("duration"):
                errors.append({"measure": mi + 1, "field": layer,
                               "message": f"{at} 时值未知(印张无节奏记号或未补)"})
                continue
            slots.append((n["beat"], n["beat"] + n["duration"], at))
        for r in measure["rests"]:
            if not r.get("beats") or r["beats"] <= 0:
                errors.append({"measure": mi + 1, "field": layer,
                               "message": f"{name}休止@{r['beat']:g} 拍数非法"})
                continue
            slots.append((r["beat"], r["beat"] + r["beats"],
                          f"{name}休止@{r['beat']:g}"))
        _check_closure(slots, measure["start_beat"], mi, name, layer,
                       meter, shift, total, errors, holes=(layer == "melody"))


def _check_closure(slots: list, start_beat: float, mi: int, name: str,
                   field: str, meter: float, shift: float, total: float,
                   errors: list, holes: bool) -> None:
    """单小节拍长闭合:事件槽须严丝合缝填满本小节自己的窗
    [start_beat, start_beat+meter)(层内拍位;草稿逐小节带 start_beat,
    不从全局网格重推——read_beats 被毒化时全曲重推会互相遮掩)。重叠/
    跨小节/空洞/落窗外都报;holes=False 时空洞不报(伴奏声部休止由导出
    端按空洞自动补记,结构上恒闭合)。层内末尾 + 偏移超出主轴骨架单独报。"""
    if not slots:
        if holes:
            errors.append({"measure": mi + 1, "field": field,
                           "message": f"{name}声部整小节无事件,拍长不闭合"})
        return
    end_ok = max(e for _, e, _ in slots) + shift <= total + _EPS
    if not end_ok:
        errors.append({"measure": mi + 1, "field": field,
                       "message": f"{name}声部事件超出小节骨架(层内末尾 "
                       f"@{max(e for _, e, _ in slots):g},主轴骨架到拍 "
                       f"{total - shift:g})"})
    begin, finish = start_beat, start_beat + meter
    inside = sorted((s, e, w) for s, e, w in slots
                    if s < finish - _EPS and e > begin + _EPS)
    if not inside:
        if holes:
            errors.append({"measure": mi + 1, "field": field,
                           "message": f"{name}声部无事件落在本小节窗内,拍长不闭合"})
        return
    if holes and inside[0][0] > begin + _EPS:
        errors.append({"measure": mi + 1, "field": field,
                       "message": f"{name}声部小节头缺 "
                       f"{_fmt(inside[0][0] - begin)} 拍(@{inside[0][0]:g} 起)"})
    cursor = max(begin, inside[0][0])
    for s, e, what in inside:
        if s < cursor - _EPS:
            errors.append({"measure": mi + 1, "field": field,
                           "message": f"{name}声部事件重叠:{what} 落在前槽内"})
        elif holes and s > cursor + _EPS:
            errors.append({"measure": mi + 1, "field": field,
                           "message": f"{name}声部拍位空洞(@{s:g} 前缺 "
                           f"{_fmt(s - cursor)} 拍)"})
        if e > finish + _EPS:
            errors.append({"measure": mi + 1, "field": field,
                           "message": f"{name}声部事件跨小节:{what} 延到 @{e:g}"
                           f"(小节到 @{finish:g})"})
        cursor = max(cursor, e)
    if holes and cursor < finish - _EPS:
        errors.append({"measure": mi + 1, "field": field,
                       "message": f"{name}声部末尾缺 {_fmt(finish - cursor)} 拍,"
                       "拍长不闭合"})


def _fmt(v: float) -> str:
    return str(int(v)) if v == int(v) else f"{v:g}"


def _why_note(n: dict) -> str:
    if n.get("degree") is None and "degree" in n:
        return "度数未知(识别保槽位),先校对"
    if n.get("string") is None and "string" in n:
        return "弦号未知,先校对"
    if n.get("fret") is None and "fret" in n:
        return "品位缺失"
    return "时值未知(印张无节奏记号),先补时值"


def errors_in_measure(errors: list, mi: int) -> list:
    """本小节的阻塞条目;全局条目(measure=None)归顶部问题抽屉,不折进
    每个小节(否则速度缺失会在 69 个小节面板各现一次)。"""
    return [e for e in errors if e["measure"] == mi + 1]


# ── 小工具 ──────────────────────────────────────────────────────────

def _measure_at(draft: dict, mi: int) -> dict | None:
    measures = draft["measures"]
    return measures[mi] if 0 <= mi < len(measures) else None


def _row(session: dict, layer: str, mi: int, row: int, table: str) -> dict:
    rows = _measure_at(session[layer], mi)[table]
    return rows[_check_row(row, len(rows))]


def _check_row(row: int, n: int) -> int:
    if not (0 <= row < n):
        raise ValueError(f"行号 {row} 越界(0..{n - 1})")
    return row


def _opt_int(v):
    return None if v in ("", None) else int(v)


def _opt_float(v):
    return None if v in ("", None) else float(v)


def _read_json(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def _now() -> str:
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")
