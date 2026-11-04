"""工单61 m0:oracle-glyph 天花板实验(ADR-0010 追记二)。

问题:字形识别全对时,50 管线剩下的自动定位+节奏解码能把联合事件 F1
抬到几?≥0.90 → 缺口确认在字形层(m1 只训字形成立);<0.90 → 定位/
节奏解码同为缺口(分类目标须纳入杆底符杠或明确降级)。

切拼契约(与 m1「格子分类器替换 50 字形识别级」同构):
- **oracle = 真值 marks**(adjudicated 列的 digit/×/muted,m1 TAB 层
  词表 = {×, digit, muted, empty}):配对上的 attack 整束换成真值 marks
  (含弦号——m1 格子天然按 (拍位格×弦) 出内容,弦轴来自几何);
- **定位保持自动**:attack 存在性(组件检测+聚簇)、小节归属、拍位
  (小节网格锚+小节内时值累加)全走 50 原样;配不上的 attack=多余检测
  (清空音位记号、保留事件/节奏 Machinery),配不上的真值列=漏检(FN);
- **节奏解码保持自动**:时值读数(杆/尾/杠/点/括线)与休止模板原样
  (variant=marks);variant=marks+durations 额外把真值时值注进配对
  attack,作「节奏解码是否唯一剩余缺口」的归因诊断(非票面主数);
- 技巧记号(roll/箭头)不在 m1 词表,保持管线检测原样;ties 管线不读,
  tie 列照注 marks(候选无 tie 标记会照展开——50 的 tie 盲是节奏解释
  层的缺口,如实计罚不掩盖)。

对齐(注入口径,实验管线非评分):小节内单调 1:1 DP,配对数最大、
平手取 Σ|Δnorm| 最小;Δnorm = attack 在小节 span 的归一 x 与真值列
归一拍的差,超 POS_TOL 不许配(位置守卫)。逐小节独立(50 拍位漂移
不跨小节级联,同一假设下对齐误差也不跨小节)。对齐统计全量落盘
(alignment 段),配错/漏配是定位缺口的直接读数。

OCR 旁路:注入替换全部音位标签,OCR 不参与(load_ocr=False,纯几何
确定可复现);注入字形 bbox 为合成几何(cy 钉在弦线上),conf=1.0 表
oracle。meter 用 4/4 假定(= baseline 页眉实读,亦 = 评测集 meta)。
"""

import datetime
import json
from fractions import Fraction
from pathlib import Path

from . import __version__
from .tab import SCHEMA, Sym, _sym_json, assemble_measures

POS_TOL = 0.3      # 归一位置差上限(配对守卫;小节宽比例)
MARK_W = 0.72      # 注入字形合成宽(比例 g,照 tests 字形工厂口径)
MARK_H = 0.9

# gs-aini 系统→真值小节映射(实验配置,非管线行为;依据=工单57 报告冻结
# 的裁块映射「谱页1 sys4[18-21]/sys5[22-24]、谱页2 sys6[25-27]」(1-based
# 印张小节号,此处 −1)+ 像素探针:split 在 sys4 探得 5 根小节界,其中
# x≈2035.8 实为震音椭圆(真值 tremolo@82,h≈5.2g)右缘的贯穿竖线误判
# → 幻影第 5 小节 → sys5/sys6 全局小节号 +1。其他曲跑 m0 须提供同形
# 映射。(系统序, [(span 局部序, 真值小节 0-based)];同小节跨 span = 并)
GS_AINI_BAR_MAP = {
    0: [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)],
    1: [(0, 5), (1, 6), (2, 7), (3, 8)],
    2: [(0, 9), (1, 10), (2, 11), (3, 12)],
    3: [(0, 13), (1, 14), (2, 15), (3, 16)],
    4: [(0, 17), (1, 18), (2, 19), (3, 20), (4, 20)],
    5: [(0, 21), (1, 22), (2, 23)],
    6: [(0, 24), (1, 25), (2, 26)],
}


def _repair_spans(systems, si, bar_map):
    """span → 修复后小节段 [(true_bar, x0, x1, [局部 span 序])]:
    按映射并同小节相邻 span(幻影界)。bar_map 无此系统 → 按全曲累计
    小节号原样(1 span = 1 小节)。"""
    system = systems[si]
    spec = (bar_map or {}).get(si)
    spans = system["measures"]
    if spec is None:
        base = sum(len(x["measures"]) for x in systems[:si])
        return [(base + m["index"], m["x0"], m["x1"], [m["index"]])
                for m in spans]
    by_bar = {}
    for local, bar in spec:
        m = spans[local]
        by_bar.setdefault(bar, []).append((bar, m["x0"], m["x1"], local))
    return [(bar, min(x0 for _, x0, _, _ in g),
             max(x1 for _, _, x1, _ in g), [l for _, _, _, l in g])
            for bar, g in sorted(by_bar.items())]


# ── 对齐:小节内 attack ↔ 真值列 单调 1:1 DP ─────────────────────────

def align_columns(attacks, cols, span, meter, pos_tol=POS_TOL):
    """单小节对齐。attacks 按 cx 序、cols 按 beat 序传入(调用方排序)。

    返回 (pairs, extra, missed):pairs=[(attack 下标, col 下标)],
    extra=未配 attack 下标(多余检测),missed=未配 col 下标(漏检列)。
    DP 目标 = 配对数最大,平手取 Σ|Δnorm| 最小(元组序即字典序)。"""
    x0, x1 = span["x0"], span["x1"]
    width = x1 - x0
    start = span.get("start_beat")
    anorm = [min(1.0, max(0.0, (a.cx - x0) / width)) if width > 0 else 0.0
             for a in attacks]
    bnorm = []
    for c in cols:
        beat = Fraction(str(c["beat"]))
        bnorm.append(float((beat - Fraction(int(start))) / Fraction(meter)))
    m, n = len(attacks), len(cols)
    # dp[i][j] = (配对数, -Σcost);比较字典序
    dp = [[(0, 0.0)] * (n + 1) for _ in range(m + 1)]
    take = [[None] * (n + 1) for _ in range(m + 1)]   # 'skip-a'|'skip-c'|'pair'
    for i in range(m + 1):
        for j in range(n + 1):
            if i == 0 and j == 0:
                continue
            best, how = None, None
            if i > 0:
                best, how = dp[i - 1][j], "skip-a"
            if j > 0 and (best is None or dp[i][j - 1] > best):
                best, how = dp[i][j - 1], "skip-c"
            if i > 0 and j > 0:
                cost = abs(anorm[i - 1] - bnorm[j - 1])
                if cost <= pos_tol:
                    cnt, neg = dp[i - 1][j - 1]
                    cand = (cnt + 1, neg - cost)
                    if best is None or cand > best:
                        best, how = cand, "pair"
            dp[i][j] = best
            take[i][j] = how
    pairs, extra, missed = [], [], []
    i, j = m, n
    while i > 0 or j > 0:
        how = take[i][j]
        if how == "pair":
            pairs.append((i - 1, j - 1))
            i, j = i - 1, j - 1
        elif how == "skip-a":
            extra.append(i - 1)
            i -= 1
        else:
            missed.append(j - 1)
            j -= 1
    pairs.reverse()
    extra.reverse()
    missed.reverse()
    return pairs, extra, missed


# ── 注入:换字形、清多余、(可选)注时值 ─────────────────────────────

def _oracle_sym(role, cx, line_y, gap, label=None):
    """注入字形合成 bbox:cy 钉弦线(弦号几何即真值),conf=1.0=oracle。"""
    w, h = MARK_W * gap, MARK_H * gap
    return Sym(role, cx - w / 2, line_y - h / 2, w, h,
               label=label, conf=1.0)


def inject_bar(attacks, cols, span, gap, line_ys, variant,
               pos_tol=POS_TOL, stats=None):
    """单小节注入(原地改 attacks)。attacks 传整系统清单,内部按 span
    过滤(与 assemble_measures 同口径);返回本小节统计 dict。"""
    inside = sorted((a for a in attacks
                     if span["x0"] <= a.cx < span["x1"]), key=lambda a: a.cx)
    cols = sorted(cols, key=lambda c: Fraction(str(c["beat"])))
    pairs, extra, missed = align_columns(inside, cols, span,
                                         span.get("meter", 4.0), pos_tol)
    paired_a = {ai for ai, _ in pairs}
    n_marks = n_digits = n_muted = 0
    for ai, ci in pairs:
        att, col = inside[ai], cols[ci]
        att.digits = []
        att.x_marks = []
        for mk in col.get("marks") or []:
            s = mk.get("string")
            if s not in (1, 2, 3, 4):
                if stats is not None:
                    stats["bad_marks"].append(
                        {"bar": span["index"], "beat": col["beat"],
                         "mark": mk})
                continue
            ly = line_ys[s - 1]
            if mk.get("kind") == "digit":
                att.digits.append(_oracle_sym("digit", att.cx, ly, gap,
                                              label=str(mk.get("fret"))))
                n_digits += 1
            elif mk.get("kind") == "x":
                att.x_marks.append(_oracle_sym("x_mark", att.cx, ly, gap))
                n_marks += 1
            elif mk.get("kind") == "muted":
                # 真值 muted 挂独立字段、评分器两侧均不进计分槽——注入即
                # 单向 FP。计数留档,不注入(m1 词表含 muted,届随评分器
                # 语义扩展另行处理)
                n_muted += 1
            else:
                if stats is not None:
                    stats["bad_marks"].append(
                        {"bar": span["index"], "beat": col["beat"],
                         "mark": mk})
        if variant == "marks+durations" and col.get("duration") is not None:
            att.duration = float(Fraction(str(col["duration"])))
    for ai in extra:                      # 多余检测:真值说此处无列 → 清空
        inside[ai].digits = []
        inside[ai].x_marks = []
    rep = {"bar": span["index"], "n_attacks": len(inside),
           "n_cols": len(cols),
           "n_pairs": len(pairs), "n_extra": len(extra),
           "n_missed": len(missed),
           "missed_beats": [str(Fraction(str(cols[c]["beat"])))
                            for c in missed]}
    if stats is not None:
        stats["bars"].append(rep)
        stats["n_pairs"] += len(pairs)
        stats["n_extra"] += len(extra)
        stats["n_missed"] += len(missed)
        stats["n_injected"] += n_digits + n_marks
        stats["n_muted_skipped"] = stats.get("n_muted_skipped", 0) + n_muted
    return rep


# ── 编排:split → 逐系统识别 → 注入 → 装配 → tab-doc ────────────────

def truth_columns_by_bar(evalset_doc, meter=4.0):
    """adjudicated 列按小节归组(0 起全曲小节序,beat//meter 整除)。"""
    from .eval_truth import in_scope

    by_bar = {}
    for c in evalset_doc["payload"]["columns"]:
        if not in_scope(c):
            continue
        bar = int(Fraction(str(c["beat"])) / Fraction(meter))
        by_bar.setdefault(bar, []).append(c)
    return by_bar


def build_oracle_tab(pdf: str, out_dir: str, evalset_doc,
                     variant: str = "marks", dpi: int = 300,
                     bar_map=None, skeleton: str = "split") -> dict:
    """oracle-glyph 主入口:位图 PDF → 50 定位/节奏(原样)→ 真值字形
    注入 → tab-doc(ukeflow.workbench.tab/1 同形 + oracle 段)。

    variant:marks(票面主数)| marks+durations(归因诊断:时值亦真值)。
    skeleton:split(装配吃 split 小节界与全局小节号,幻影界照罚)|
    repaired(按 bar_map 并幻影 span、起点锚真值小节号——「48 小节线
    缺陷已修」的可行动上限诊断,非管线行为)。
    注入锚恒按 bar_map(真值小节 → 印张实际 x 域);skeleton=split 时
    装配仍用 split 标签,幻影界导致的整体 +4 拍错位如实进分。
    产物落 out_dir/oracle-tab*.json;随后 tab-candidate → eval-joint 与
    59a 基线同链可比。"""
    if variant not in ("marks", "marks+durations"):
        raise ValueError(f"未知 variant {variant!r}(marks|marks+durations)")
    if skeleton not in ("split", "repaired"):
        raise ValueError(f"未知 skeleton {skeleton!r}(split|repaired)")
    import cv2

    from .report import sha256_file
    from .tab import recognize_tab_attacks

    meter = 4.0        # = baseline 页眉实读 = 评测集 meta.beats_per_bar
    run = recognize_tab_attacks(pdf, out_dir, dpi=dpi, load_ocr=False)
    truth_by_bar = truth_columns_by_bar(evalset_doc, meter)
    stats = {"variant": variant, "skeleton": skeleton, "bars": [],
             "n_pairs": 0, "n_extra": 0, "n_missed": 0, "n_injected": 0,
             "bad_marks": []}
    measures, unmapped = [], []
    for si, (s, attacks, evidence) in enumerate(zip(
            run["systems"], run["attacks"], run["evidence"])):
        gap = s["staff"]["gap"]
        line_ys = s["staff"]["line_ys"]
        repaired = _repair_spans(run["systems"], si, bar_map)
        # 注入锚:按修复后真值小节段(真值小节 → 印张实际 x 域)
        for true_bar, x0, x1, _locals in repaired:
            if true_bar not in truth_by_bar:
                continue
            sp = {"index": true_bar, "x0": x0, "x1": x1, "meter": meter,
                  "start_beat": meter * true_bar}
            inject_bar(attacks, truth_by_bar[true_bar], sp, gap,
                       line_ys, variant, stats=stats)
        # 装配:split 原样(含幻影界,错位照罚)| repaired(并幻影、
        # 起点锚真值小节号——非管线行为,上限诊断)
        if skeleton == "repaired":
            spans = [{"index": true_bar, "x0": x0, "x1": x1,
                      "meter": meter, "start_beat": meter * true_bar}
                     for true_bar, x0, x1, _ in repaired]
        else:
            base = sum(len(x["measures"]) for x in run["systems"][:si])
            spans = [{"index": base + m["index"], "x0": m["x0"],
                      "x1": m["x1"], "meter": meter,
                      "start_beat": meter * (base + m["index"])}
                     for m in s["measures"]]
        asm, un = assemble_measures(attacks, evidence, spans, meter,
                                    line_ys, gap, start_index=len(measures))
        for mm in asm:
            mm["index"] = len(measures)
            mm["system"] = s["index"]
            measures.append(mm)
        unmapped.extend(un)
    doc = {
        "schema": SCHEMA,
        "tool_version": __version__,
        "created_at": datetime.datetime.now().astimezone().isoformat(
            timespec="seconds"),
        "source": {"file": str(Path(pdf).resolve()),
                   "sha256": sha256_file(pdf), "dpi": dpi},
        "header": run["header"],
        "systems": run["per_system"],
        "measures": measures,
        "unmapped_attacks": [{
            "x": round(a.cx, 1),
            "digits": [_sym_json(s) for s in a.digits],
            "x_marks": [_sym_json(s) for s in a.x_marks],
            "events": [_sym_json(s) for s in a.events],
        } for a in unmapped],
        "oracle": {
            "experiment": "61-m0 oracle-glyph",
            "evalset": {"id": evalset_doc.get("id"),
                        "version": evalset_doc.get("version"),
                        "payload_sha256": evalset_doc.get("payload_sha256")},
            "variant": variant,
            "skeleton": skeleton,
            "bar_map": {str(k): v for k, v in (bar_map or {}).items()},
            "pos_tol": POS_TOL,
            "meter_assumed": meter,
            "ocr_bypassed": True,
            "alignment": stats,
        },
    }
    out = Path(out_dir)
    name = "oracle-tab.json" if variant == "marks" \
        else "oracle-tab-durations.json"
    if skeleton == "repaired":
        name = name.replace(".json", "-repaired.json")
    with open(out / name, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    return doc
