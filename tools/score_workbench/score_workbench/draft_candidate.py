"""工单59a:49/50 识别草稿 → 评分器输入的适配(基线专用,无训练)。

评分器零候选路适配(工单56 纪律)的另一半:适配在候选侧,评分器不动。

TAB 草稿(tab.json)→ ukeflow.eval.candidate/1:
- 逐拍聚列(同 attack 的数字/×/技巧共享同一 beat float,精确相等即同列);
- 时值持续窗重算与真值同规(eval_build:至下一 attack/休止截断、曲尾封顶
  主轴、连音列不拦——50 无连音列概念,天然不拦);
- 50 不读延音弧(ties)/滑音端点(slides)/连音×柱(tie 列),对应字段
  留空、逐类计数入 warnings——不伪造证据,符号层漏报照实计 FN;
- barline/slide/ellipse 是结构/悬证据记号,不进列(barline 真值侧无此
  计分项;slide 无端点;ellipse 只延音不改攻击),计数入 warnings;
- 弦号未知的记号照落(string=None),评分器按 key 不匹配计 FP,不静默;
- scope/标段复用 57 的 scope_filter(已裁定拍段 0-36+80-108)。

旋律草稿(melody.json)→ dolce_poc.Attack(melody_score 输入,与 58③
dolce 基线同尺):
- midi 折算沿用 melodic_diff 的应用净点数式:印张点数=应用+1(工单39
  实测),net = max(0,above−1) − max(0,below−1);
- 拍位按小节网格锚定:印张拍 = 4×全曲小节序(0 起) + 小节内拍;
  read_beats 累加漂移不进基线拍位(与 tab 草稿同一锚定约定);
- 小节序=印张小节号−1,与 tab/evalset 同源(layout 全曲小节序)。
"""

import json
from fractions import Fraction

from .eval_build import MAIN_AXIS_BEATS
from .vlm_poc import scope_filter, to_jsonable

CANDIDATE_SCHEMA = "ukeflow.eval.candidate/1"

# 进列的技术记号(50 可产出的);shaft=未定向箭头,评分器照实计错。
# 同拍冲突取此序优先(具体字形 > 泛化定向 > 近邻挂靠证据),败者入
# warnings 记账——不静默、不双记
COLUMN_TECHS = ("roll", "strumUp", "strumDown", "tremolo", "shaft")
_TECH_PRIORITY = {k: i for i, k in enumerate(COLUMN_TECHS)}

# 评分窗口(印张小节号闭区间):段窗对齐 evalset SEGMENTS,后两窗为
# 与 58③ dolce 复评直接可比而设
MELODY_WINDOWS = [
    ("verse-a(b6-9)", 6, 9),
    ("chorus(b21-27)", 21, 27),
    ("58p0(b6-13)", 6, 13),
    ("58p1(b14-24)", 14, 24),
    ("full(b6-27)", 6, 27),
]


def tab_to_candidate(tab_doc, main_axis=MAIN_AXIS_BEATS):
    """tab.json → 全时值轴候选(ukeflow.eval.candidate/1,score 前过
    scope_filter 由调用方决定)。返回 (cand, notes) 诊断计数 dict。"""
    cols_by_beat = {}
    rests = []
    skip = {"barline": 0, "slide": 0, "ellipse": 0}
    tech_conflicts = []
    for m in tab_doc["measures"]:
        for n in m["notes"]:
            col = _col_at(cols_by_beat, n["beat"])
            col["marks"].append({"string": n.get("string"),
                                 "kind": "digit", "fret": n["fret"]})
        for x in m["x_marks"]:
            if x["kind"] == "barline":
                skip["barline"] += 1
                continue
            col = _col_at(cols_by_beat, x["beat"])
            strings = x.get("strings") or []
            if strings:
                for s in strings:
                    col["marks"].append({"string": s, "kind": "x"})
            else:
                # × 读到但弦号全未知:保一条占位(key 不匹配→FP,不静默)
                col["marks"].append({"string": None, "kind": "x"})
        for t in m["techniques"]:
            if t["kind"] in skip:
                skip[t["kind"]] += 1
                continue
            col = _col_at(cols_by_beat, t["beat"])
            if col.get("tech") and col["tech"] != t["kind"]:
                cur, new = col["tech"], t["kind"]
                if _TECH_PRIORITY[new] < _TECH_PRIORITY[cur]:
                    col["tech"] = new
                    tech_conflicts.append({"beat": t["beat"], "kept": new,
                                           "dropped": cur})
                else:
                    tech_conflicts.append({"beat": t["beat"], "kept": cur,
                                           "dropped": new})
                continue
            col["tech"] = t["kind"]
        for r in m["rests"]:
            rests.append({"beat": Fraction(str(r["beat"])),
                          "beats": Fraction(str(r["beats"]))})
    cols = sorted(cols_by_beat.values(), key=lambda c: c["beat"])
    # 时值持续窗重算(与真值同规):cuts = attack 列拍 + 休止拍
    cuts = sorted({c["beat"] for c in cols} | {r["beat"] for r in rests})
    end = Fraction(main_axis)
    for c in cols:
        nxt = [b for b in cuts if c["beat"] < b <= end]
        c["duration"] = (min(nxt) if nxt else end) - c["beat"]
    warns = [f"跳过不进列:barline×{skip['barline']} slide×{skip['slide']}"
             f"(无端点)ellipse×{skip['ellipse']}——无对应计分项,不伪造"]
    warns += [f"@{c['beat']}: tech 冲突保 {c['kept']} 弃 {c['dropped']}"
              f"(优先级 {COLUMN_TECHS})" for c in tech_conflicts]
    cand = {"schema": CANDIDATE_SCHEMA, "columns": cols, "rests": rests,
            "ties": [], "slides": [], "warnings": warns}
    notes = {"skip": skip, "tech_conflicts": tech_conflicts,
             "no_duration_attacks": sum(
                 1 for m in tab_doc["measures"] for n in m["notes"]
                 if n.get("duration") is None)}
    return cand, notes


def _col_at(cols_by_beat, beat):
    key = Fraction(str(beat))
    if key not in cols_by_beat:
        cols_by_beat[key] = {"beat": key, "marks": [], "tech": None,
                             "tie": False}
    return cols_by_beat[key]


def scope_and_store(cand, out_path):
    """过筛已裁定拍段 + 标段 → rat 串 JSON 落盘(eval-joint CLI 直吃)。"""
    merged = scope_filter(cand)
    merged["columns"].sort(key=lambda c: c["beat"])
    doc = to_jsonable(merged)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    return merged


# ── 旋律草稿适配(melody_score 同尺)──────────────────────────────

def melody_draft_attacks(melody_doc, meter=4):
    """melody.json → (attacks, n_unknown_degree)。Attack 与 dolce 基线
    同形(composite_beat/melody_score 直吃);拍位=4×小节序+小节内拍。"""
    from .dolce_poc import C_MAJOR_BASE, Attack

    attacks = []
    n_unknown = 0
    for m in melody_doc["measures"]:
        for n in m["notes"]:
            if n["degree"] is None or not (1 <= n["degree"] <= 7):
                n_unknown += 1
                continue
            net = (max(0, n.get("octave_dots_above", 0) - 1)
                   - max(0, n.get("octave_dots_below", 0) - 1))
            midi = C_MAJOR_BASE[n["degree"]] + 12 * net
            attacks.append(Attack(
                midi=midi,
                printed_bar=m["index"] + 1,
                beat_in_bar=Fraction(str(n["beat"] - m["start_beat"])),
                printed_duration=Fraction(str(n.get("duration") or 0)),
            ))
    return attacks, n_unknown


def melody_window_scores(attacks, truth_doc, windows=MELODY_WINDOWS):
    """逐窗 melody_score(56 配对机制 × App 旋律真值,参照级)。"""
    from .dolce_poc import melody_score

    align = Fraction(str(truth_doc["melodyAlignBeats"]))
    truth_notes = truth_doc["notes"]
    out = {}
    for name, lo, hi in windows:
        w_lo, w_hi = Fraction(4 * (lo - 1)), Fraction(4 * hi)
        t_win = [n for n in truth_notes
                 if w_lo <= Fraction(str(n["beat"])) + align < w_hi]
        a_win = [a for a in attacks if lo <= a.printed_bar <= hi]
        rep = melody_score(t_win, a_win, align)
        rep["window_bars"] = [lo, hi]
        rep["window_printed_beats"] = [str(w_lo), str(w_hi)]
        out[name] = rep
    return out
