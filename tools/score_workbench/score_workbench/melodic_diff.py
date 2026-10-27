"""真值 diff(工单49):识别草稿 × builtin 人工真值逐位对照。

配对单位=「块」:truth 按 4 拍一格(连拍格,b24/25 变拍两小节并一格),
草稿小节按 read_beats 贪心凑满一格(2+2 并块照常)。逐位比三样:
度数+八度点(印张约定=应用点数+1,sys01 实测 5'=G4)/块内拍位/时值
(休止感知:音后接休止按「至下音累计」对真值 gap;闭合不对的块底座
不成立,时值跳过、度数照比)。报告喂工单51 校对台对照模式。
"""

from . import __version__

SCHEMA = "ukeflow.workbench.melody_diff/1"
TOL = 1e-6

_NATURAL_DEGREE = {0: 1, 2: 2, 4: 3, 5: 4, 7: 5, 9: 6, 11: 7}


def truth_to_print_pitch(midi: int) -> tuple:
    """真值 midi → (度数, 印张高音点数)。印张点数=应用约定点数+1
    (应用 C4-B4 无点 = 印张 1 点;工单39 实测)。非自然音级 = 违反
    旋律层契约,ValueError 当场报(不静默)。"""
    pc = midi % 12
    if pc not in _NATURAL_DEGREE:
        raise ValueError(f"midi {midi} 非自然音级,旋律层契约破坏")
    degree = _NATURAL_DEGREE[pc]
    dots = midi // 12 - 5 + 1          # C4=60 → 应用 0 点 → 印张 1 点
    return degree, dots


def diff_melody(draft: dict, truth: dict, start_measure: int,
                chunk_beats: float = 4.0) -> dict:
    """逐位 diff 主入口。draft = melody.json 的 measures 段;truth =
    dump_melody_truth.dart 导出的 notes(beat/midi)。"""
    window = [m for m in draft["measures"] if m["index"] >= start_measure]
    chunks = _chunk_draft(window, chunk_beats)
    tnotes = truth["notes"]
    report = {"schema": SCHEMA, "tool_version": __version__,
              "window": {"start_measure": start_measure,
                         "truth_notes": len(tnotes)},
              "chunks": [],
              "summary": {"degree_ok": 0, "degree_bad": 0,
                          "octave_ok": 0, "octave_bad": 0,
                          "beat_ok": 0, "beat_bad": 0,
                          "duration_ok": 0, "duration_bad": 0,
                          "duration_compared": 0}}
    tail = 0
    for k, chunk in enumerate(chunks):
        lo, hi = k * chunk_beats, (k + 1) * chunk_beats
        t_group = [n for n in tnotes if lo - TOL <= n["beat"] < hi - TOL]
        if not t_group:                  # 真值已尽:草稿尾部只计不比
            tail += sum(len(m["notes"]) for m in chunk)
            continue
        entry = {"truth_measure": k, "draft_measures":
                 [m["index"] for m in chunk],
                 "read_beats": sum(m["read_beats"] for m in chunk),
                 "closure_ok": abs(sum(m["read_beats"] for m in chunk)
                                   - chunk_beats) < TOL,
                 "n_truth": len(t_group),
                 "n_draft": sum(len(m["notes"]) for m in chunk),
                 "mismatches": [], "duration_compared": 0}
        d_notes = [n for m in chunk for n in m["notes"]]
        d_rests = [r for m in chunk for r in m["rests"]]
        chunk_start = chunk[0]["start_beat"] if chunk else 0.0
        if entry["n_draft"] != entry["n_truth"]:
            entry["mismatches"].append(
                {"field": "count", "draft": entry["n_draft"],
                 "truth": entry["n_truth"]})
        for i in range(min(len(d_notes), len(t_group))):
            d, t = d_notes[i], t_group[i]
            t_deg, t_dots = truth_to_print_pitch(t["midi"])
            if d["degree"] != t_deg:
                entry["mismatches"].append(
                    {"i": i, "field": "degree", "draft": d["degree"],
                     "truth": t_deg, "beat": t["beat"]})
                report["summary"]["degree_bad"] += 1
            else:
                report["summary"]["degree_ok"] += 1
            if d.get("octave_dots_above", 0) != t_dots:
                entry["mismatches"].append(
                    {"i": i, "field": "octave",
                     "draft": d.get("octave_dots_above", 0), "truth": t_dots,
                     "beat": t["beat"]})
                report["summary"]["octave_bad"] += 1
            else:
                report["summary"]["octave_ok"] += 1
            d_rel = d["beat"] - chunk_start
            t_rel = t["beat"] - lo
            if abs(d_rel - t_rel) > TOL:
                entry["mismatches"].append(
                    {"i": i, "field": "beat", "draft": d_rel, "truth": t_rel,
                     "beat": t["beat"]})
                report["summary"]["beat_bad"] += 1
            else:
                report["summary"]["beat_ok"] += 1
            if (entry["closure_ok"] and i + 1 < len(t_group)
                    and i + 1 < len(d_notes)):
                gap = t_group[i + 1]["beat"] - t["beat"]
                nxt = d_notes[i + 1]["beat"]
                covered = d["duration"] + sum(
                    r["beats"] for r in d_rests if d["beat"] - TOL
                    <= r["beat"] < nxt - TOL)
                entry["duration_compared"] += 1
                report["summary"]["duration_compared"] += 1
                if abs(covered - gap) > TOL:
                    entry["mismatches"].append(
                        {"i": i, "field": "duration", "draft": covered,
                         "truth": gap, "beat": t["beat"]})
                    report["summary"]["duration_bad"] += 1
                else:
                    report["summary"]["duration_ok"] += 1
        report["chunks"].append(entry)
    report["summary"]["draft_notes"] = sum(
        len(m["notes"]) for m in window)
    report["summary"]["tail_notes_beyond_truth"] = tail
    return report


def _chunk_draft(window: list, chunk_beats: float) -> list:
    """草稿小节贪心凑块:read_beats 累加至 ≥ chunk_beats 即切块。"""
    chunks, cur = [], []
    for m in window:
        cur.append(m)
        if sum(x["read_beats"] for x in cur) >= chunk_beats - TOL:
            chunks.append(cur)
            cur = []
    if cur:
        chunks.append(cur)
    return chunks
