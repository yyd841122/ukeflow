"""评测集构建(工单56):历史转录底稿 + 裁决修正 → 冻结评测集。

底稿 = dump_tab_truth.dart 导出的 builtin 真值(484 音,仅参照不作真值
——ADR-0010);裁决修正 = evalset/adjudications.json(裁片终审记录,含
逐项证据)。构建是确定性纯函数:v2 = 同管线 + 新裁决,真值冻结后改动走
版本号。

推导规则(单源,与 eval_expand 呼应):
- 记号形态:品位 = 当拍和弦指形 → ×;否则数字(工单39 约定,修正后全曲成立);
- 闷音:和弦指形 -1 且无记号的弦(如 D7 ②④);虚按③:三记号 {④②①}
  堆列的 ③(37 台账形态全同,裁片核验);
- 时值:至下一 attack/休止的区间(显式休止截断;连音列不截断);曲尾封顶
  主轴长;这是「播放时值」口径——延音线链(如 ⑨⑨⑨tie)只记首 attack,
  时值自然吃满链长;
- 扫弦/卷弦列只落 tech 行不落 × 列(印张是一支箭头/一道波浪);tremolo
  列保 × 列(椭圆罩 × 柱);
- 拍段过滤后进冻结集,台账记三类:已裁定/待裁定/未覆盖。
"""

import json

from .eval_expand import expand_events, rat
from .eval_truth import SCHEMA, payload_sha256

MAIN_AXIS_BEATS = 108

SEGMENTS = [
    {"id": "b1", "label": "第1小节(全小节休止)", "from_beat": "0",
     "to_beat": "4", "evidence_level": "裁片12x核验 2026-11-02"},
    {"id": "intro", "label": "前奏 b2-b5", "from_beat": "4", "to_beat": "20",
     "evidence_level": "争议项裁片12x/24x/原生逐项终审 2026-11-02;"
                       "×弦号与时值承 37/39 转录+听验基线"},
    {"id": "verse-a", "label": "主歌一遍 b6-b9", "from_beat": "20",
     "to_beat": "36",
     "evidence_level": "37/39 转录+听验基线;虚按③/拨× 裁片抽查 2026-11-02"},
    {"id": "chorus", "label": "副歌B高置+尾段 b21-b27", "from_beat": "80",
     "to_beat": "108",
     "evidence_level": "37/39 转录+听验基线;bar21/22+D7 裁片核验,"
                       "89+ 箭头方向未核(待裁定)"},
]

UNCOVERED = [
    {"from_beat": "36", "to_beat": "80",
     "desc": "主歌二遍+移位句+副歌A(b10-b20):已转录、未冻结进 v1(同型段落,"
             "扩展走 v2)"},
    {"from_beat": "108", "to_beat": None,
     "desc": "印张 p2 剩余段(b28+):间奏(震音椭圆)/二段主歌(拨 P)/转调 "
             "1=F+3/4(b42)/尾段,全未转录——用户终审裁决永久弃用"
             "(2026-11-02,评测只考已转录段)"},
]


def _group_notes(notes):
    cols = {}
    for n in notes:
        cols.setdefault(rat(n["beat"]), []).append(n)
    return cols


def _marks_for(notes, chords):
    """逐音记号形态:品位=和弦指形 → ×,否则数字。"""
    from .eval_expand import chord_frets_at
    marks = []
    for n in sorted(notes, key=lambda n: -n["string"]):
        frets = chord_frets_at(rat(n["beat"]), chords)
        cf = frets[4 - n["string"]] if frets else None
        if cf == n["fret"]:
            marks.append({"string": n["string"], "kind": "x"})
        else:
            marks.append({"string": n["string"], "kind": "digit",
                          "fret": n["fret"]})
    return marks


def _muted_for(marks, beat, chords):
    """闷音/虚按记号:和弦 -1 弦(D7 ②④)+ 三记号堆列的虚按③。"""
    from .eval_expand import chord_frets_at
    frets = chord_frets_at(beat, chords)
    if frets is None:
        return []
    muted = []
    have = {m["string"] for m in marks}
    for s in (4, 3, 2, 1):
        if frets[4 - s] == -1 and s not in have:
            muted.append({"string": s, "kind": "muted"})
    if len(marks) == 3 and {m["string"] for m in marks} == {4, 2, 1} \
            and not muted:
        muted.append({"string": 3, "kind": "muted"})
    return muted


def build_evalset(tab_gt: dict, chords_dump: dict, corrections: dict,
                  version: int, frozen_at: str) -> dict:
    chords = [{"beat": _rat_str(c["beat"]), "label": c["label"],
               "frets": c["frets"]} for c in chords_dump["chords"]]
    cols = _group_notes(tab_gt["notes"])
    # ── 裁决修正:整列替换(增/删/改品位)──
    for beat_s, marks in (corrections.get("note_columns") or {}).items():
        beat = rat(beat_s)
        if marks:
            strings = {m["string"] for m in marks}
            cols[beat] = [{"beat": float(beat), "string": m["string"],
                           "fret": m.get("fret", 0)} for m in marks]
        else:
            cols.pop(beat, None)
    strums = {rat(s["beat"]): s["kind"] for s in tab_gt["strums"]}
    for beat_s in corrections.get("tech_remove") or []:
        strums.pop(rat(beat_s), None)
    for add in corrections.get("tech_add") or []:
        strums[rat(add["beat"])] = add["kind"]
    for beat_s, kind in (corrections.get("tech_direction") or {}).items():
        strums[rat(beat_s)] = kind
    dir_pending_from = corrections.get("tech_direction_pending_from")
    dir_pending_from = rat(dir_pending_from) if dir_pending_from else None
    tremolos = {rat(t["beat"]) for t in tab_gt["tremolos"]}
    tie_cols = {rat(t["beat"]): t for t in corrections.get("tie_columns") or []}
    rests = [{"beat": _rat_str(r["beat"]), "beats": _rat_str(r["beats"]),
              "status": "adjudicated",
              "evidence": "工单37 台账+工单39 裁片(实心点+尾钩)"}
             for r in tab_gt["rests"]
             if rat(r["beat"]) not in {rat(b) for b in
                                       corrections.get("rests_remove") or []}]
    for add in corrections.get("rests_add") or []:
        rests.append({"beat": _rat_str(add["beat"]), "beats": _rat_str(add["beats"]),
                      "status": add.get("status", "adjudicated"),
                      "evidence": add.get("evidence", "")})
    slides = [s for s in tab_gt["slides"]
              if rat(s["fromBeat"]) not in {rat(b) for b in
                                            corrections.get("slides_remove")
                                            or []}]
    ties = [{"from_beat": t["from_beat"], "to_beat": t["to_beat"],
             "status": "adjudicated", "evidence": t.get("evidence", "")}
            for t in corrections.get("ties_add") or []]
    # ── 列装配(全时间轴,段过滤在后)──
    all_beats = sorted(set(cols) | set(strums) | set(tremolos) | set(tie_cols))
    out = []
    for beat in all_beats:
        seg = next((s["id"] for s in SEGMENTS
                    if rat(s["from_beat"]) <= beat < rat(s["to_beat"])), None)
        col = {"beat": _rat_str(beat), "segment": seg,
               "status": "adjudicated"}
        notes = cols.get(beat)
        tech = strums.get(beat)
        keep_x = beat in {rat(b) for b in
                          corrections.get("tech_x_marks") or []}
        if beat in tremolos:
            tech = "tremolo" if tech is None else tech
            col["tech"] = tech
            col["marks"] = _marks_for(notes or [], chords)
            col["muted"] = _muted_for(col["marks"], beat, chords)
        elif tech in ("roll", "strumUp", "strumDown"):
            col["tech"] = tech
            if dir_pending_from is not None and tech != "roll" \
                    and beat >= dir_pending_from:
                col["tech_pending"] = True
                col["reason"] = "箭头方向惯例预置未逐支核验(工单39 遗留#3;" \
                                "bar21/22 抽查 7/15 与预置不符,已核者已改)"
            col["marks"] = _marks_for(notes or [], chords) if keep_x else []
        elif beat in tie_cols:
            tc = tie_cols[beat]
            col["tie"] = True
            col["marks"] = []
            col["status"] = tc.get("status", "pending")
            if tc.get("reason"):
                col["reason"] = tc["reason"]
            if tc.get("evidence"):
                col["evidence"] = tc["evidence"]
        else:
            col["marks"] = _marks_for(notes or [], chords)
            col["muted"] = _muted_for(col["marks"], beat, chords)
        if seg is None:
            continue
        out.append(col)
    # ── 时值:至下一 attack/休止(显式休止截断;连音列不拦),曲尾封顶 ──
    attack_beats = sorted(set(all_beats) - set(tie_cols))
    rest_beats = [rat(r["beat"]) for r in rests]
    end = rat(corrections.get("main_axis_beats", MAIN_AXIS_BEATS))
    col_by_beat = {rat(c["beat"]): c for c in out}
    for beat, col in col_by_beat.items():
        nxt = [b for b in attack_beats if beat < b <= end] \
            + [b for b in rest_beats if beat < b <= end]
        dur = (min(nxt) if nxt else end) - beat
        col["duration"] = _rat_str(dur)
    out.sort(key=lambda c: rat(c["beat"]))
    payload = {
        "chords": chords,
        "segments": SEGMENTS,
        "columns": out,
        "rests": sorted(rests, key=lambda r: rat(r["beat"])),
        "ties": ties,
        "slides": [{"from_beat": _rat_str(s["fromBeat"]), "to_beat": _rat_str(s["toBeat"]),
                    "status": "adjudicated",
                    "evidence": "工单39 第3小节重读裁片"} for s in slides],
        "uncovered": UNCOVERED,
    }
    events, _ = expand_events(payload["columns"], chords)
    return {
        "schema": SCHEMA,
        "id": "gs-aini-tab",
        "version": version,
        "title": chords_dump.get("title", "爱你不是两三天·独奏 TAB 层"),
        "frozen_at": frozen_at,
        "source": {
            "base_transcription":
                "builtin ai-ni-bu-shi-liang-san-tian-solo(dump_tab_truth,484 音)"
                f"@{corrections.get('base_commit', '')}",
            "archaeology": ["工单37 转录台账", "工单39 印张像素考古",
                            "工单50 300dpi 几何档案",
                            "工单56 裁片终审 " + frozen_at],
            "transcription_notes": len(tab_gt["notes"]),
            "adjudications": corrections.get("comment", ""),
        },
        "meta": {
            "tempo": chords_dump.get("tempo", tab_gt.get("tempo")),
            "beats_per_bar": 4, "key": chords_dump.get("key", "1=E"),
            "main_axis_beats": MAIN_AXIS_BEATS,
            "event_count": len(events),
        },
        "payload": payload,
        "payload_sha256": payload_sha256(payload),
    }


def _rat_str(v) -> str:
    """Fraction → 冻结文件的有理数串("4"/"19/2");JSON 数值装不下 1/3。"""
    f = rat(v)
    return str(f.numerator) if f.denominator == 1 \
        else f"{f.numerator}/{f.denominator}"
