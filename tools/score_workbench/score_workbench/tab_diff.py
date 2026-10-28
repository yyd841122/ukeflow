"""真值 diff(工单50):TAB 识别草稿 × builtin 人工真值逐位对照。

四个金标准维度(票面):数字正确率(草稿品位数字 × 真值按「拍位 ±容差 +
同弦」配对后比 fret)/ 时值误差(同弦连续配对段的草稿时值对真值拍距)/
休止 P-R(全小节休止不在真值事件模型里,单列只报不罚)/ 技巧 F1
(roll/strumUp/strumDown/tremolo/slide 各类 P-R-F1,拍位容差配对)。
草稿窗口按真值最后事件拍 + 4 拍截断,窗口外只计不比(工单49 同纪律)。
报告喂工单51 校对台对照模式。
"""

from . import __version__

SCHEMA = "ukeflow.workbench.tab_diff/1"
TOL = 0.35                 # 拍位配对容差(印张锚位漂移 ±0.3 拍,census)
STRUM_KINDS = ("roll", "strumUp", "strumDown")
TECH_KINDS = ("roll", "strumUp", "strumDown", "tremolo", "slide")


def _prf(tp: int, fp: int, fn: int) -> dict:
    """P/R/F1 三元组(休止与技巧共用一个公式,别处不再手搓)。"""
    p = tp / (tp + fp) if tp + fp else None
    r = tp / (tp + fn) if tp + fn else None
    f1 = 2 * p * r / (p + r) if p and r else None
    return {"tp": tp, "fp": fp, "fn": fn, "precision": p, "recall": r,
            "f1": f1}


def diff_tab(draft: dict, truth: dict, start_measure: int = 0) -> dict:
    """逐位 diff 主入口。draft = tab.json;truth = dump_tab_truth.dart
    导出的真值(notes/strums/rests/tremolos/slides)。"""
    window = [m for m in draft["measures"]
              if m["index"] >= start_measure]
    tnotes = list(truth["notes"])
    ends = [n["beat"] for n in tnotes] \
        + [e["beat"] for e in truth["strums"]] \
        + [r["beat"] for r in truth["rests"]] \
        + [t["beat"] for t in truth["tremolos"]] \
        + [s["fromBeat"] for s in truth["slides"]]
    end_beat = max(ends, default=0.0) + 4.0
    d_notes = [n for m in window for n in m["notes"] if n["beat"] <= end_beat]
    d_rests = [r for m in window for r in m["rests"] if r["beat"] <= end_beat]
    report = {
        "schema": SCHEMA, "tool_version": __version__,
        "window": {"start_measure": start_measure, "truth_notes": len(tnotes),
                   "end_beat": end_beat},
        "summary": {}, "by_string": {}, "duration": {}, "rests": {},
        "techniques": {}, "hotspots": [],
    }
    # ── 数字正确率:拍位 ±TOL + 同弦优先配对(和弦堆同拍多弦,先同弦)──
    matched, fret_ok, string_bad = [], 0, 0
    used = [False] * len(tnotes)

    def _nearest(n):
        same = [(abs(n["beat"] - t["beat"]), i) for i, t in enumerate(tnotes)
                if not used[i] and t["string"] == n["string"]]
        if same:
            return min(same)[1]
        anys = [(abs(n["beat"] - t["beat"]), i) for i, t in enumerate(tnotes)
                if not used[i]]
        return min(anys)[1] if anys else None

    for n in sorted(d_notes, key=lambda n: n["beat"]):
        i = _nearest(n)
        if i is None or abs(n["beat"] - tnotes[i]["beat"]) > TOL:
            continue
        used[i] = True
        t = tnotes[i]
        if t["string"] != n["string"]:
            string_bad += 1
            continue
        ok = n["fret"] == t["fret"]
        matched.append((n, t, ok))
        fret_ok += ok
        if not ok:
            report["hotspots"].append(
                {"field": "fret", "beat": t["beat"], "string": t["string"],
                 "draft": n["fret"], "truth": t["fret"]})
    report["summary"]["digit_matched"] = len(matched)
    report["summary"]["digit_ok"] = fret_ok
    report["summary"]["digit_bad"] = len(matched) - fret_ok
    report["summary"]["digit_accuracy"] = round(
        fret_ok / len(matched), 4) if matched else None
    report["summary"]["draft_notes"] = len(d_notes)
    report["summary"]["string_mismatch"] = string_bad
    for st in (1, 2, 3, 4):
        ms = [(n, t, ok) for n, t, ok in matched if n["string"] == st]
        if ms:
            report["by_string"][st] = {
                "ok": sum(ok for _, _, ok in ms), "n": len(ms)}
    # ── 时值:同弦连续配对对(草稿序)的真值拍距 ──
    dur_ok = dur_bad = dur_n = 0
    for st in (1, 2, 3, 4):
        run = [(n, t) for n, t, ok in matched if n["string"] == st
               and n["duration"] is not None]
        for (n1, t1), (n2, t2) in zip(run, run[1:]):
            gap = t2["beat"] - t1["beat"]
            dur_n += 1
            if abs(n1["duration"] - gap) <= 1e-6:
                dur_ok += 1
            else:
                dur_bad += 1
                report["hotspots"].append(
                    {"field": "duration", "beat": t1["beat"],
                     "string": st, "draft": n1["duration"], "truth": gap})
    report["duration"] = {"ok": dur_ok, "bad": dur_bad, "compared": dur_n}
    # ── 休止 P-R(全小节休止单列,真值事件模型外)──
    trests = list(truth["rests"])
    used_r = [False] * len(trests)
    tp = fp = 0
    whole = 0
    for r in d_rests:
        if r["kind"] == "rest_whole":
            whole += 1
            continue
        hit = next((i for i, t in enumerate(trests)
                    if not used_r[i] and abs(r["beat"] - t["beat"]) <= TOL),
                   None)
        if hit is None:
            fp += 1
            report["hotspots"].append(
                {"field": "rest_fp", "beat": r["beat"], "draft": r["beats"]})
        else:
            used_r[hit] = True
            tp += 1
    fn = used_r.count(False)
    for i, t in enumerate(trests):
        if not used_r[i]:
            report["hotspots"].append(
                {"field": "rest_fn", "beat": t["beat"],
                 "truth": t["beats"]})
    report["rests"] = {**_prf(tp, fp, fn),
                       "whole_bar_not_in_truth": whole}
    # ── 技巧 F1 ──
    d_tech = [t for m in window for t in m["techniques"]
              if t["kind"] in TECH_KINDS and t["beat"] is not None
              and t["beat"] <= end_beat]
    t_events = ([{"kind": s["kind"], "beat": s["beat"]}
                 for s in truth["strums"]]
                + [{"kind": "tremolo", "beat": t["beat"]}
                   for t in truth["tremolos"]]
                + [{"kind": "slide", "beat": s["fromBeat"]}
                   for s in truth["slides"]])
    used_t = [False] * len(t_events)
    tp_t = fp_t = 0
    per_kind = {k: {"tp": 0, "fp": 0, "fn": 0} for k in TECH_KINDS}
    for t in sorted(d_tech, key=lambda t: t["beat"]):
        hit = next((i for i, e in enumerate(t_events)
                    if not used_t[i] and e["kind"] == t["kind"]
                    and abs(t["beat"] - e["beat"]) <= TOL), None)
        if hit is None:
            fp_t += 1
            per_kind.setdefault(t["kind"], {"tp": 0, "fp": 0, "fn": 0})["fp"] += 1
        else:
            used_t[hit] = True
            tp_t += 1
            per_kind[t["kind"]]["tp"] += 1
    fn_t = 0
    for i, e in enumerate(t_events):
        if not used_t[i]:
            fn_t += 1
            per_kind[e["kind"]]["fn"] += 1
    macro = _prf(tp_t, fp_t, fn_t)
    for k, v in per_kind.items():
        v.update(_prf(v["tp"], v["fp"], v["fn"]))
    report["techniques"] = {**macro, "by_kind": per_kind}
    report["summary"]["technique_f1"] = macro["f1"]
    return report
