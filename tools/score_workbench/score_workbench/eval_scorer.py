"""联合事件 F1 评分器(工单56 / ADR-0010 决策 1)。

联合事件 = 弦品+起音拍位+节奏三件套全对才算一个 TP;一对一配对;
容差固定 τ = min(1/32 拍, 真值最短相邻起音间隔之半),有理数精确比。
旧 ±0.35 拍只作空间漂移诊断(diagnostics.spatial),不作节奏标准。

语义分层(ADR-0010 决策 2):印张符号层(×/数字/技巧/休止/延音线)与
「统一展开→播放事件」层分开计分;展开走 eval_expand 单源,真值与候选
一致。晋级线口径 = 事件层 F1(已裁定范围)。

评分器只管打分:候选以统一草稿格式进来(ukeflow.eval.candidate/1,列
形状同真值),不做任何读取端适配;× 展开用真值和弦锚(已解层,单源),
报告里注明。
"""

from collections import namedtuple
from fractions import Fraction

from . import __version__
from .eval_expand import expand_events, rat
from .eval_truth import in_scope

REPORT_SCHEMA = "ukeflow.eval.report/1"
CAP = Fraction(1, 32)
SPATIAL_DIAG_TOL = Fraction(7, 20)      # ±0.35 拍:空间漂移诊断窗(非标准)

# 计分条目:key 桶 + 拍位 + 时值(后两段 = 诊断定位/per-segment 用)
ScoredItem = namedtuple("ScoredItem", "key beat dur segment ref")


def _prf(tp, fp, fn):
    p = tp / (tp + fp) if tp + fp else None
    r = tp / (tp + fn) if tp + fn else None
    den = 2 * tp + fp + fn
    return {"tp": tp, "fp": fp, "fn": fn, "precision": p,
            "recall": r, "f1": (2 * tp / den) if den else 1.0}


def tolerance(truth_events) -> Fraction:
    """τ = min(1/32, 真值最短相邻起音间隔之半)。空真值 = 上限 1/32。"""
    beats = sorted({e.onset for e in truth_events})
    gaps = [b - a for a, b in zip(beats, beats[1:])]
    return min([CAP] + [g / 2 for g in gaps if g > 0])


def _match(truth, cand, tol):
    """按 key 桶一对一最大配对(|Δbeat| < tol,严格:恰在 τ 上判错)。

    key 相同才可能成对;桶小、tol < 半间隔,近邻唯一——Kuhn 增广路取
    桶内最大配对,邻表按近先序保证平局取更近者。返回 [(ti, ci)]。"""
    from collections import defaultdict
    tb = defaultdict(list)
    cb = defaultdict(list)
    for i, item in enumerate(truth):
        tb[item[0]].append(i)
    for j, item in enumerate(cand):
        cb[item[0]].append(j)
    pairs = []
    for key, tis in tb.items():
        cis = cb.get(key, [])
        if not cis:
            continue
        adj = {}
        for ti in tis:
            near = sorted((abs(truth[ti][1] - cand[c][1]), c) for c in cis
                          if abs(truth[ti][1] - cand[c][1]) < tol)
            adj[ti] = [c for _, c in near]
        match_c = {}
        for ti in sorted(tis, key=lambda t: truth[t][1]):
            _augment(ti, adj, set(), match_c)
        pairs.extend((ti, ci) for ci, ti in match_c.items())
    return pairs


def _augment(ti, adj, seen, match_c):
    for ci in adj.get(ti, ()):
        if ci in seen:
            continue
        seen.add(ci)
        if ci not in match_c or _augment(match_c[ci], adj, seen, match_c):
            match_c[ci] = ti
            return True
    return False


def score_layer(truth_items, cand_items, tol):
    """条目 = (key, beat, dur|None):key+拍位+dur 全对才算 TP;拍位/时值
    都是严格小于 tol(恰在 τ 上判错,工单56「容差 <1/32 拍」字面);
    成对但 dur 错 = rhythm_miss(FP+FN 照计,单列诊断)。"""
    pairs = _match(truth_items, cand_items, tol)
    tp = rhythm_miss = 0
    miss_rows = []
    used_t, used_c = set(), set()
    for ti, ci in pairs:
        used_t.add(ti)
        used_c.add(ci)
        td, cd = truth_items[ti][2], cand_items[ci][2]
        if td is None and cd is None:
            tp += 1
        elif td is None or cd is None:
            rhythm_miss += 1
            miss_rows.append({"beat": str(truth_items[ti][1]),
                              "key": list(map(str, truth_items[ti][0])),
                              "truth": None if td is None else str(td),
                              "cand": None if cd is None else str(cd)})
        elif abs(td - cd) < tol:
            tp += 1
        else:
            rhythm_miss += 1
            miss_rows.append({"beat": str(truth_items[ti][1]),
                              "key": list(map(str, truth_items[ti][0])),
                              "truth": str(td), "cand": str(cd)})
    fn = len(truth_items) - tp          # 节奏错对照计 fp+fn(miss 行为其切片)
    fp = len(cand_items) - tp
    rep = _prf(tp, fp, fn)
    rep["rhythm_miss"] = {"count": rhythm_miss, "rows": miss_rows[:40]}
    return rep


def _spatial_diagnostics(truth_events, cand_events, tol, truth_pairs_t, cand_pairs_c):
    """未配对事件的空间定位诊断(另报,不进 F1):同弦品近邻漂移/
    同拍错品/同拍错弦,±0.35 拍诊断窗。"""
    paired_t, paired_c = set(truth_pairs_t), set(cand_pairs_c)
    drift, fret_err, string_err, un_t, un_c = [], [], [], [], []
    for i, e in enumerate(truth_events):
        if i in paired_t:
            continue
        near = [(abs(e.onset - c.onset), j) for j, c in enumerate(cand_events)
                if c.string == e.string and c.fret == e.fret]
        same_beat = [(j, c) for j, c in enumerate(cand_events)
                     if abs(e.onset - c.onset) <= tol]
        if near and min(near)[0] <= SPATIAL_DIAG_TOL:
            d, j = min(near)
            drift.append({"beat": str(e.onset), "string": e.string,
                          "fret": e.fret, "delta_beat": str(
                              Fraction(e.onset - cand_events[j].onset))})
        elif any(c.string == e.string and c.fret != e.fret
                 for _, c in same_beat):
            j, c = next((j, c) for j, c in same_beat
                        if c.string == e.string and c.fret != e.fret)
            fret_err.append({"beat": str(e.onset), "string": e.string,
                             "truth_fret": e.fret, "cand_fret": c.fret})
        elif any(c.string != e.string for _, c in same_beat):
            string_err.append({"beat": str(e.onset), "string": e.string,
                               "fret": e.fret})
        else:
            un_t.append({"beat": str(e.onset), "string": e.string,
                         "fret": e.fret})
    for j, c in enumerate(cand_events):
        if j in paired_c:
            continue
        near = [abs(c.onset - e.onset) for e in truth_events
                if e.string == c.string and e.fret == c.fret]
        if not (near and min(near) <= SPATIAL_DIAG_TOL) \
                and not any(abs(c.onset - e.onset) <= tol
                            and (e.string != c.string or e.fret != c.fret)
                            for e in truth_events):
            un_c.append({"beat": str(c.onset), "string": c.string,
                         "fret": c.fret})
    deltas = [abs(Fraction(d["delta_beat"])) for d in drift]
    spatial = ({
        "n": len(deltas),
        "mean_abs_beat": str(round(float(sum(deltas) / len(deltas)), 4))
        if deltas else None,
        "max_abs_beat": str(max(deltas)) if deltas else None,
    })
    return {"onset_drift": drift[:40], "fret_error": fret_err[:40],
            "string_error": string_err[:40],
            "unmatched_truth": un_t[:40], "unmatched_pred": un_c[:40],
            "spatial": spatial}


def _symbol_items(cols, rests, ties, slides, skip_tech_beats=(),
                  skip_tiecol_beats=()):
    """印张符号层计分条目,真值侧与候选侧共用(评审56:两抄收拢)。

    调用方负责行级准入(真值先过 in_scope;候选原样);skip_* = 真值侧
    待裁定槽位(箭头方向未核/连音柱未验)按拍对称出分,另报 unverified。
    """
    items = []
    for col in cols:
        beat = rat(col["beat"])
        for m in col.get("marks") or []:
            key = ("m", m["kind"], m["string"],
                   m.get("fret") if m["kind"] == "digit" else None)
            items.append(ScoredItem(key, beat, None, None, None))
        if col.get("tech") and beat not in skip_tech_beats:
            items.append(ScoredItem(("t", col["tech"]), beat, None, None, None))
        if col.get("tie") and beat not in skip_tiecol_beats:
            items.append(ScoredItem(("tiecol",), beat, None, None, None))
    for r in rests:
        items.append(ScoredItem(("rest",), rat(r["beat"]), rat(r["beats"]),
                                None, None))
    for t in ties:
        items.append(ScoredItem(("tie", rat(t["from_beat"])),
                                rat(t["from_beat"]),
                                rat(t["to_beat"]) - rat(t["from_beat"]),
                                None, None))
    for s in slides:
        items.append(ScoredItem(("slide",), rat(s["from_beat"]),
                                rat(s["to_beat"]) - rat(s["from_beat"]),
                                None, None))
    return items


def truth_items_from(doc, include_pending=False):
    """真值两层的计分条目:事件层 + 符号层。"""
    payload = doc["payload"]
    chords = payload.get("chords", [])
    cols = [c for c in payload["columns"] if in_scope(c, include_pending)]
    rests = [r for r in payload.get("rests", []) if in_scope(r, include_pending)]
    ties = [t for t in payload.get("ties", []) if in_scope(t, include_pending)]
    slides = [s for s in payload.get("slides", []) if in_scope(s, include_pending)]
    events, _ = expand_events(cols, chords)
    ev_items = [ScoredItem((e.string, e.fret), e.onset, e.duration,
                           e.segment, e.ref) for e in events]
    sym_items = _symbol_items(
        cols, rests, ties, slides,
        skip_tech_beats={rat(c["beat"]) for c in payload["columns"]
                         if c.get("tech_pending")},
        skip_tiecol_beats={rat(c["beat"]) for c in payload["columns"]
                           if c.get("tie") and c.get("status") == "pending"})
    return ev_items, sym_items, events


def candidate_items(cand_doc, chords, skip_tech_beats=(), skip_tiecol_beats=()):
    """候选草稿 → 两层条目。× 展开用真值和弦锚(单源,报告注明)。

    skip_*:真值侧待裁定的槽位(箭头方向未核/连音柱未验)对称出分——
    候选在该拍的 tech/tiecol 记号不计分也不计错,另报 unverified。"""
    if cand_doc.get("schema") != "ukeflow.eval.candidate/1":
        raise ValueError("候选草稿 schema 须为 ukeflow.eval.candidate/1")
    cols = cand_doc["columns"]
    events, warns = expand_events(cols, chords)
    ev_items = [ScoredItem((e.string, e.fret), e.onset, e.duration,
                           e.segment, e.ref) for e in events]
    sym_items = _symbol_items(cols, cand_doc.get("rests", []),
                              cand_doc.get("ties", []),
                              cand_doc.get("slides", []),
                              skip_tech_beats, skip_tiecol_beats)
    return ev_items, sym_items, events, warns


def joint_report(doc, cand_doc, include_pending=False):
    """主入口:评测集 × 候选草稿 → 报告。"""
    payload = doc["payload"]
    chords = payload.get("chords", [])
    skip_tech = {rat(c["beat"]) for c in payload["columns"]
                 if c.get("tech_pending")}
    skip_tiecol = {rat(c["beat"]) for c in payload["columns"]
                   if c.get("tie") and c.get("status") == "pending"}
    t_ev, t_sym, t_events = truth_items_from(doc, include_pending)
    c_ev, c_sym, c_events, warns = candidate_items(cand_doc, chords,
                                                   skip_tech, skip_tiecol)
    tol = tolerance(t_events)
    # 事件层:per-segment 拆分 + 总分
    segs = {s["id"]: s.get("label", s["id"])
            for s in payload.get("segments", [])}
    t_by_seg, c_by_seg = {}, {}
    for it in t_ev:
        t_by_seg.setdefault(it[3], []).append(it[:3])
    for it in c_ev:
        c_by_seg.setdefault(it[3], []).append(it[:3])
    per_seg = {}
    for seg in sorted(set(t_by_seg) | set(c_by_seg)):
        per_seg[seg] = score_layer(t_by_seg.get(seg, []),
                                   c_by_seg.get(seg, []), tol)
    ev_all = score_layer([i[:3] for i in t_ev], [i[:3] for i in c_ev], tol)
    sym_all = score_layer([i[:3] for i in t_sym], [i[:3] for i in c_sym], tol)
    # 诊断(事件层,基于配对结果)
    pairs = _match([i[:3] for i in t_ev], [i[:3] for i in c_ev], tol)
    diag = _spatial_diagnostics(t_events, c_events, tol,
                                {ti for ti, _ in pairs},
                                {ci for _, ci in pairs})
    from .eval_truth import ledger_stats
    led = ledger_stats(doc)
    return {
        "schema": REPORT_SCHEMA, "tool_version": __version__,
        "evalset": {"id": doc.get("id"), "version": doc.get("version"),
                    "payload_sha256": doc.get("payload_sha256")},
        "tol_beat": f"{tol.numerator}/{tol.denominator}",
        "chords_used": "truth(frozen)",
        "include_pending": include_pending,
        "expansion_warnings": [
            {"beat": str(b), "msg": m} for b, m in warns],
        "events": ev_all,
        "symbols": sym_all,
        "per_segment": {k: v for k, v in per_seg.items()},
        "diagnostics": diag,
        "ledger": led,
        "gate": {"passing_line": "TAB 联合事件 F1 ≥ 0.90",
                 "events_f1": ev_all["f1"],
                 "pass": ev_all["f1"] >= 0.90},
    }
