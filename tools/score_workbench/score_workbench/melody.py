"""简谱旋律层识别(工单49):字形几何 → OCR 数字 → 拍位装配 → IR 草稿。

输入=工单48 split 产物(layout.json + jianpu 层裁图);主识别路径自带证据链
(逐符号 bbox/裁图/置信度,ADR-0009),拍位由「逐音时值符号在所属小节内
累加」得出——x 位置只定小节归属与音序,不做 px→拍标定(工单41 撞墙点照守,
split 的候选拍网格只当互证证据)。已考记号外一律落警告不静默丢。

几何档案(300dpi,g≈19.2,工单48/49 实测):数字 h≈1.3g、w 0.55-0.95g
('1' 最窄);八度点/附点 ≤0.5g;时值线 h≈0.16g、共享梁可跨多音(主梁=八分,
副梁叠其下=十六分,逐音按「梁是否盖过音心 x」计数);延音杠(延音线 '-'){
h 同时值线但行中高度;延音弧宽 ≥2g 空心(同音连线/连音,证据不改 attack);
小节线竖段会伸进简谱行(w≈0.2g);歌词窄偏旁与数字同尺寸,靠「最大簇」选
数字行(sys01 实测 33>5;歧证上报不静默)。
"""

import datetime
import json
from dataclasses import dataclass
from pathlib import Path

from . import __version__
from .split import INK_GRAY_MAX

# ── 字形几何(单位=g,即弦距;实测档案见模块 docstring)─────────────────

DIGIT_H = (1.05, 1.6)       # 数字高范围(1.3g 实测,'1' 同高)
DIGIT_W = (0.45, 1.1)       # 数字宽范围(0.55-0.95g 实测)
DOT_SIZE = 0.5              # 八度点/附点宽上限('1' 数字宽 0.55g 不相侵)
DOT_H_MAX = 1.3             # 八度点高上限:竖排双点/三点连成一件(实测双点 h≈0.75g)
DOT_PITCH = 0.375           # 单点高(实测 6-8px@g19.2),连排件按 round(h/此) 计数
BAR_H = 0.25                # 时值线/延音杠厚度上限(实测 0.16g)
BAR_MIN_W = 0.5             # 薄横最短长(低于此归点/碎屑)
DASH_MAX_W = 1.3            # 延音杠最长(共享梁实测 1.0-6.4g,超即非杠)
ARC_W = 1.8                 # 延音弧最短宽度(实测 2.03g)
ARC_SOLIDITY = 0.55         # 弧空心判据:area/(w·h) 低于此
VERTICAL_W = 0.35           # 小节线竖段宽上限
VERTICAL_H = 1.5            # 小节线竖段最短高
BAND_SPREAD = 0.5           # 数字簇内 y 中心散布上限
AMBIG_FRAC = 0.8            # 次簇 ≥ 主簇此比例且在上方 → 歧证
UNDERLINE_ZONE = 0.9        # 数字行底之下此时值线有效(共享梁第二排 0.5g)
DOT_ABOVE_ZONE = 1.6        # 高音点心带:[行顶−1.6g, 行顶)——再往上是 TAB
                            # 段残杆/斜线区(m20 实测误计 5 点即此,宁窄勿滥)
DOT_BELOW_ZONE = (0.7, 1.8)   # 低音点心带(比例自行底,实测下点紧贴时值线下)


@dataclass(frozen=True)
class Glyph:
    """一个组件的分类结果(渲染 px,bbox 证据)。"""

    role: str               # digit|dot|bar|arc|vertical|other
    x: float
    y: float
    w: float
    h: float

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2

    @property
    def x1(self) -> float:
        return self.x + self.w


def find_digit_band(comps: list[tuple], gap: float) -> tuple[tuple, bool]:
    """数字行选举:数字尺寸组件按 y 中心聚类(隙 ≤0.8g),取最大簇。

    返回 (band(y0,y1), ambiguous)。任一次簇计数 ≥ AMBIG_FRAC×主簇 →
    ambiguous=True(TAB 残段/歌词偏旁均可能同尺寸,证据上报不静默;
    真机 18 系统实测主簇 16-33,次簇 ≤6,不触)。
    """
    cands = [c for c in comps
             if DIGIT_H[0] * gap <= c[3] <= DIGIT_H[1] * gap
             and DIGIT_W[0] * gap <= c[2] <= DIGIT_W[1] * gap]
    if not cands:
        return (0.0, 0.0), False
    cands = sorted(cands, key=lambda c: c[1] + c[3] / 2)
    clusters = [[cands[0]]]
    for c in cands[1:]:
        cy = c[1] + c[3] / 2
        if cy - _cy(clusters[-1][-1]) <= BAND_SPREAD * gap:
            clusters[-1].append(c)
        else:
            clusters.append([c])
    clusters.sort(key=len, reverse=True)
    main = clusters[0]
    ambiguous = any(len(c) >= AMBIG_FRAC * len(main) for c in clusters[1:])
    y0 = min(c[1] for c in main)
    y1 = max(c[1] + c[3] for c in main)
    return (float(y0), float(y1)), ambiguous


def _cy(c: tuple) -> float:
    return c[1] + c[3] / 2


def classify_glyphs(comps: list[tuple], gap: float, band: tuple) -> list:
    """组件 → 角色。顺序判定:数字(行内同尺寸)→ 薄横杠 → 小点 → 宽扁空心弧
    → 细高竖段 → 其余(other,证据保留)。杠与点的细分(时值线/延音杠、
    高音点/附点/低音点)在归属层按 y 域与相邻数字定。"""
    b0, b1 = band
    glyphs = []
    for x, y, w, h, area in comps:
        cy = y + h / 2
        if (DIGIT_H[0] * gap <= h <= DIGIT_H[1] * gap
                and DIGIT_W[0] * gap <= w <= DIGIT_W[1] * gap
                and b0 - 0.35 * gap <= cy <= b1 + 0.35 * gap):
            role = "digit"
        elif h <= BAR_H * gap and w >= BAR_MIN_W * gap:
            role = "bar"
        elif w <= DOT_SIZE * gap and h <= DOT_H_MAX * gap:
            role = "dot"
        elif (w >= ARC_W * gap and h <= 0.7 * gap
                and area < ARC_SOLIDITY * w * h):
            role = "arc"
        elif w <= VERTICAL_W * gap and h >= VERTICAL_H * gap:
            role = "vertical"
        else:
            role = "other"
        glyphs.append(Glyph(role, float(x), float(y), float(w), float(h)))
    return glyphs


# ── 归属层:点/杠挂到数字,弧/竖段/无主点落证据 ───────────────────────

DOT_HUG = 0.6               # 点心在数字 x 区间内的贴身余量(八度点)
DOT_LATERAL = 0.5           # 点心在数字 x 区间外时,距数字缘 ≤ 此才可挂
AUG_INNER = 0.35            # 附点心距数字心最近距离(实测 0.94-1.04g,取其下)
AUG_OUTER = 1.3             # 附点心距数字心最远距离(窄字 '1' 缘距 0.78g 仍盖)
DASH_REACH = 1.2            # 延音杠到其左侧数字右缘的距离上限


@dataclass(frozen=True)
class RawNote:
    """一个数字音位的原始读数(OCR 前几何量全齐)。"""

    glyph: Glyph
    above_dots: int
    below_dots: int
    aug: bool
    n_underlines: int
    n_dashes: int


@dataclass(frozen=True)
class Mark:
    """非音符记号证据(延音弧/反复记号/小节竖段等)。"""

    kind: str
    glyph: Glyph


@dataclass(frozen=True)
class AttachResult:
    notes: list
    marks: list
    leftovers: list            # 未归类点/杠等(证据保留,不静默)


def _dot_count(g, gap: float) -> int:
    """连排八度点折合点数:单点 h≈0.31-0.42g,双点连成一件 h≈0.7-0.85g。"""
    return max(1, min(3, round(g.h / (DOT_PITCH * gap))))


def attach_marks(glyphs: list, gap: float) -> AttachResult:
    """几何归属:高音点 x 对齐数字心,附点在数字右中,时值线按「盖过音心 x」
    计数(共享主梁各音各计),延音杠归左邻数字;挂不上的点/杠与弧、竖段落
    证据。行中薄长横(w 超 DASH_MAX_W)不认作延音杠,落 leftovers。"""
    digits = sorted((g for g in glyphs if g.role == "digit"), key=lambda g: g.x)
    b0 = min(g.y for g in digits) if digits else 0.0
    b1 = max(g.y + g.h for g in digits) if digits else 0.0
    notes = [RawNote(d, 0, 0, False, 0, 0) for d in digits]
    marks, leftovers = [], []
    underlines, dash_cands, other_bars = [], [], []
    for g in glyphs:
        if g.role != "bar":
            continue
        if b1 - 0.05 * gap <= g.cy <= b1 + UNDERLINE_ZONE * gap:
            underlines.append(g)
        elif b0 - 0.1 * gap <= g.cy <= b1:
            (dash_cands if g.w <= DASH_MAX_W * gap else other_bars).append(g)
        else:
            other_bars.append(g)
    for g in glyphs:
        if g.role != "dot":
            continue
        def lateral(d):
            return max(d.x - g.cx, 0.0, g.cx - d.x1)

        aug_i = next((i for i, d in enumerate(digits)
                      if d.cx + AUG_INNER * gap <= g.cx
                      <= d.cx + AUG_OUTER * gap
                      and b0 + 0.25 * gap <= g.cy <= b1 - 0.05 * gap), None)
        if aug_i is not None:
            d = digits[aug_i]
            notes[aug_i] = RawNote(d, notes[aug_i].above_dots,
                                   notes[aug_i].below_dots, True,
                                   notes[aug_i].n_underlines,
                                   notes[aug_i].n_dashes)
            continue
        nearest = min(digits, key=lateral, default=None)
        if (nearest is None
                or (lateral(nearest) > DOT_LATERAL * gap
                    and abs(nearest.cx - g.cx) > DOT_HUG * gap)):
            if b0 - 0.35 * gap <= g.cy <= b1 + 0.35 * gap:
                marks.append(Mark("repeat_dot", g))
            else:
                leftovers.append(g)
            continue
        ni = digits.index(nearest)
        if b0 - DOT_ABOVE_ZONE * gap <= g.cy < b0 - 0.1 * gap:
            k = _dot_count(g, gap)
            notes[ni] = RawNote(nearest, notes[ni].above_dots + k,
                                notes[ni].below_dots, notes[ni].aug,
                                notes[ni].n_underlines, notes[ni].n_dashes)
        elif b1 + DOT_BELOW_ZONE[0] * gap <= g.cy <= b1 + DOT_BELOW_ZONE[1] * gap:
            k = _dot_count(g, gap)
            notes[ni] = RawNote(nearest, notes[ni].above_dots,
                                notes[ni].below_dots + k, notes[ni].aug,
                                notes[ni].n_underlines, notes[ni].n_dashes)
        else:
            marks.append(Mark("stray_dot", g))
    for i, n in enumerate(notes):
        d = n.glyph
        ul = sum(1 for u in underlines if u.x <= d.cx <= u.x + u.w)
        ds = sum(1 for dash in dash_cands
                 if 0 <= dash.x - (d.x + d.w) <= DASH_REACH * gap
                 and (i + 1 == len(notes)
                      or dash.x < notes[i + 1].glyph.x))
        notes[i] = RawNote(d, n.above_dots, n.below_dots, n.aug, ul, ds)
    for g in glyphs:
        if g.role == "arc":
            marks.append(Mark("arc", g))
        elif g.role == "vertical":
            marks.append(Mark("vertical", g))
        elif g.role == "other":
            marks.append(Mark("other", g))   # 考域外组件,证据保留不静默
    return AttachResult(notes, marks, leftovers + list(other_bars))


# ── 装配层:时值符号 → 拍位累加 + 小节归属 + 闭合对账 ─────────────────

MAX_UNDERLINES = 3          # 三十二分以上不考(落警告)


def note_duration(underlines: int, aug: bool, dashes: int) -> float:
    """简谱时值:基拍四分,n 层时值线 ÷2ⁿ,附点 ×1.5,延音杠各 +1 拍。"""
    dur = 0.5 ** min(underlines, MAX_UNDERLINES)
    if aug:
        dur *= 1.5
    return dur + dashes


def assemble_measures(notes: list, spans: list, meter_beats: float,
                      start_beat: float = 0.0) -> "MeasuresOut":
    """拍位装配:notes = OCR 后音位(x/label/时值符号/置信度),spans =
    split 的小节骨架(x0/x1,**单系统**页坐标系——各系统 x 域都是 173-2308,
    跨系统拼 spans 会把全谱音符灌进首个系统的小节,49 实测翻车)。
    音序=小节内 x 升序;beat=小节内累加;read_beats=全小节读出长度,≠拍号
    即闭合警告(start_beat 仍按读出累加,漂移可见不遮掩——错漏在小节边界处
    显形)。未知数字保槽位落警告(ADR-0009:禁止静默丢)。"""
    out_measures, warnings = [], []
    beat0 = start_beat
    for span in spans:
        inside = sorted((n for n in notes
                         if span["x0"] <= n["x"] < span["x1"]),
                        key=lambda n: n["x"])
        start = out_measures[-1]["start_beat"] + out_measures[-1]["read_beats"] \
            if out_measures else beat0
        m_notes, m_rests, m_warn, cum = [], [], [], 0.0
        for n in inside:
            label = n["label"]
            dur = note_duration(n["underlines"], n["aug"], n["dashes"])
            if n["underlines"] > MAX_UNDERLINES:
                m_warn.append(f"时值线 {n['underlines']} 层超考域,按"
                              f"{MAX_UNDERLINES} 层读")
            entry = {
                "degree": None,
                "octave_dots_above": n.get("above_dots", 0),
                "octave_dots_below": n.get("below_dots", 0),
                "aug": n["aug"],
                "underlines": n["underlines"],
                "dashes": n["dashes"],
                "beat": start + cum,
                "duration": dur,
                "confidence": n["confidence"],
                "x": n["x"],
                "evidence": {"bbox": n["bbox"],
                             "confidence": n["confidence"]}
                if n.get("bbox") is not None else None,
            }
            if label == "0":
                m_rests.append({"beat": start + cum, "beats": dur,
                                "x": n["x"],
                                "evidence": {"bbox": n["bbox"],
                                             "confidence": n["confidence"]}
                                if n.get("bbox") is not None else None})
            elif label is not None and label in "1234567":
                entry["degree"] = int(label)
                m_notes.append(entry)
            else:
                m_warn.append(f"未知数字 {label!r}(x={n['x']:.0f}),保槽位"
                              "待人工(不静默丢)")
                m_notes.append(entry)
            cum += dur
        closure_ok = bool(inside) and abs(cum - meter_beats) < 1e-9
        if inside and not closure_ok:
            m_warn.append(f"小节拍长闭合 {cum:g} ≠ 拍号 {meter_beats:g},"
                          "逐符号人工核对")
        out_measures.append({
            "index": span["index"], "x0": span["x0"], "x1": span["x1"],
            "start_beat": start, "read_beats": cum, "closure_ok": closure_ok,
            "notes": m_notes, "rests": m_rests, "warnings": m_warn,
        })
    unmapped = [n for n in notes
                if not any(sp["x0"] <= n["x"] < sp["x1"] for sp in spans)]
    return MeasuresOut(out_measures, unmapped)


@dataclass(frozen=True)
class MeasuresOut:
    measures: list
    unmapped: list             # 落不进任何小节的音位(证据保留)


# ── 编排层:单系统识别 + 全曲草稿 ─────────────────────────────────────

COMP_MIN_AREA = 12         # 组件最小面积(与 split 同源)
CROP_PAD = 2               # split 裁图外扩 px(_save_crop 实测)
SCHEMA = "ukeflow.workbench.melody/1"
DEFAULT_METER = 4.0        # 页眉读不出时的假定拍号(报告里 meter_assumed=True)


class FakeOcr:
    """测试桩:按数字 x 序查表给标签(几何/装配全走真代码)。"""

    def __init__(self, labels):
        self._labels = labels

    def digit_labels(self, img, digits):
        return [(self._labels[i], 1.0) for i in range(len(digits))]


def _components(gray):
    import cv2
    import numpy as np
    ink = (np.asarray(gray) < INK_GRAY_MAX).astype(np.uint8)
    n, _, stats, _ = cv2.connectedComponentsWithStats(ink)
    return [tuple(int(v) for v in stats[i]) for i in range(1, n)
            if stats[i][4] >= COMP_MIN_AREA]


def recognize_system(crop_gray, system, ocr) -> dict:
    """单系统:裁图 → 组件 → 数字行选举 → 角色 → 归属 → OCR → 音位。

    返回 {notes(页坐标 x), marks, warnings, digit_band, ambiguous}。
    crop_x → 页 x 偏移 = int(layer.x0) − CROP_PAD(split._save_crop 口径)。
    """
    gap = system["staff"]["gap"]
    warnings = []
    comps = _components(crop_gray)
    band, ambiguous = find_digit_band(comps, gap)
    if ambiguous:
        warnings.append(f"数字行选举有同量级次簇(歧证),band={band}")
    if band == (0.0, 0.0):
        return {"notes": [], "marks": [], "leftovers": [],
                "warnings": warnings or ["无数字尺寸组件"],
                "digit_band": None, "ambiguous": ambiguous}
    glyphs = classify_glyphs(comps, gap, band)
    att = attach_marks(glyphs, gap)
    labels = ocr.digit_labels(crop_gray, [n.glyph for n in att.notes])
    x_off = float(system["layers"]["jianpu"]["bbox"][0]) - CROP_PAD
    notes = []
    for n, (label, conf) in zip(att.notes, labels):
        g = n.glyph
        notes.append({
            "x": g.cx + x_off,
            "label": label,
            "above_dots": n.above_dots,
            "below_dots": n.below_dots,
            "aug": n.aug,
            "underlines": n.n_underlines,
            "dashes": n.n_dashes,
            "confidence": conf,
            "bbox": [g.x + x_off, g.y, g.w, g.h],
        })
    if att.leftovers:
        warnings.append(f"{len(att.leftovers)} 个未归类小组件,证据落 leftovers")
    return {"notes": notes,
            "marks": [{"kind": m.kind,
                       "bbox": [m.glyph.x + x_off, m.glyph.y,
                                m.glyph.w, m.glyph.h]}
                      for m in att.marks],
            "leftovers": [{"bbox": [g.x + x_off, g.y, g.w, g.h]}
                          for g in att.leftovers],
            "warnings": warnings, "digit_band": list(band),
            "ambiguous": ambiguous}


def recognize_melody_pdf(pdf: str, out_dir: str, dpi: int = 300,
                         ocr=None, header_reader=None,
                         models_dir: str | None = None) -> dict:
    """票面主入口:位图 PDF → split → 逐系统识别 → melody.json。

    ocr 缺省走 PP-OCR(模型目录按 resolve 默认序找);header_reader 缺省
    走页眉行 rec(同模型),读不出 key/meter/tempo → 落警告并按 4/4 假定
    (meter_assumed=True,校对台人工确认)。
    """
    from .split import split_pdf
    from .report import sha256_file

    layout = split_pdf(pdf, out_dir, dpi=dpi)
    if ocr is None:
        from .paddle_ocr import DigitOCR
        ocr = DigitOCR(models_dir)
    if header_reader is None and hasattr(ocr, "line_text"):
        first_top = layout["score_pages"][0]["systems"][0]["staff"]["top"] \
            if layout["score_pages"] and layout["score_pages"][0]["systems"] \
            else 200.0
        header_reader = lambda: read_header(pdf, dpi, first_top, ocr)
    systems = [s for pg in layout["score_pages"] for s in pg["systems"]]
    import cv2
    per_system, all_notes = [], []
    for s in systems:
        jp = s["layers"]["jianpu"]
        if jp is None:
            per_system.append({"index": s["index"],
                               "warnings": ["无简谱层"],
                               "marks": [], "leftovers": [],
                               "digit_band": None, "ambiguous": False,
                               "n_digits": 0, "n_rests": 0})
            all_notes.append([])               # 占位保 zip 对齐(此系统无音)
            continue
        crop = cv2.imread(str(Path(out_dir) / jp["crop"]),
                          cv2.IMREAD_GRAYSCALE)
        res = recognize_system(crop, s, ocr)
        per_system.append({"index": s["index"],
                           "warnings": res["warnings"],
                           "marks": res["marks"],
                           "leftovers": res["leftovers"],
                           "digit_band": res["digit_band"],
                           "ambiguous": res["ambiguous"],
                           "n_digits": sum(1 for n in res["notes"]
                                           if n["label"] not in ("0", None)),
                           "n_rests": sum(1 for n in res["notes"]
                                          if n["label"] == "0")})
        all_notes.append(res["notes"])
    header = {"key": None, "meter": None, "tempo_bpm": None,
              "meter_assumed": True, "evidence": None, "warnings": []}
    meter_beats = DEFAULT_METER
    if header_reader is not None:
        header = header_reader()
        if header.get("meter"):
            meter_beats = float(header["meter"].split("/")[0])
    # 逐系统装配(各系统 x 域同形,不可跨系统拼 spans),再全局串接
    measures, unmapped = [], []
    for s, notes in zip(systems, all_notes):
        spans = [{"index": m["index"], "x0": m["x0"], "x1": m["x1"]}
                 for m in s["measures"]]
        asm = assemble_measures(notes, spans, meter_beats,
                                start_beat=measures[-1]["start_beat"]
                                + measures[-1]["read_beats"] if measures else 0.0)
        grids = {sm["index"]: sm["beat_grids"] for sm in s["measures"]}
        for m in asm.measures:
            span_index = m["index"]          # 装配层保留的 split 小节序
            m["index"] = len(measures)
            m["system"] = s["index"]
            m["grid_fit"] = _grid_fit(m, grids.get(span_index))
            measures.append(m)
        unmapped.extend(asm.unmapped)
    draft = {
        "schema": SCHEMA,
        "tool_version": __version__,
        "created_at": datetime.datetime.now().astimezone().isoformat(
            timespec="seconds"),
        "source": {"file": str(Path(pdf).resolve()),
                   "sha256": sha256_file(pdf), "dpi": dpi},
        "header": header,
        "systems": per_system,
        "measures": measures,
        "unmapped_notes": unmapped,
    }
    out = Path(out_dir)
    with open(out / "melody.json", "w", encoding="utf-8") as fh:
        fh.write(json.dumps(draft, ensure_ascii=False, indent=2) + "\n")
    return draft


# ── 页眉:调号/拍号/速度(行 rec + 叠排分数组件判读)────────────────────

HEADER_MIN_ROW_H = 6       # 页眉文本行最小高(渲染 px)


def read_header(pdf: str, dpi: float, first_staff_top: float, ocr) -> dict:
    """页 0 顶部带(首系统谱表之上)逐文本行 rec → key/meter/tempo。

    key=`1=X` 行正则;tempo=其后的 `=nnn` 行;meter=调号行里「竖排分数」
    (两只 ≤0.45 行高的小组件 x 重叠上下叠)逐只 rec。读不出 → 警告 +
    None(调用方按 4/4 假定并显形),不静默。"""
    import re

    import numpy as np
    import pymupdf

    out = {"key": None, "meter": None, "tempo_bpm": None, "meter_assumed": True,
           "evidence": None, "warnings": []}
    scale = dpi / 72.0
    doc = pymupdf.open(pdf)
    try:
        page = doc[0]
        clip_h = max(10.0, first_staff_top - 2.0) / scale
        pix = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale),
                              colorspace=pymupdf.csGRAY,
                              clip=pymupdf.Rect(0, 0, page.rect.width, clip_h))
        arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(
            pix.height, pix.width).copy()
    finally:
        doc.close()
    ink = arr < INK_GRAY_MAX
    rows = ink.sum(axis=1) > 0
    runs, inr = [], False
    for y, v in enumerate(rows):
        if v and not inr:
            y0, inr = y, True
        elif not v and inr:
            runs.append((y0, y))
            inr = False
    if inr:
        runs.append((y0, len(rows)))
    texts = []
    for y0, y1 in runs:
        if y1 - y0 < HEADER_MIN_ROW_H:
            continue
        cols = np.flatnonzero(ink[y0:y1].any(axis=0))
        strip = arr[y0:y1 + 1, max(0, cols[0] - 3):cols[-1] + 4]
        texts.append((y0, y1, int(cols[0]), int(cols[-1]),
                      ocr.line_text(strip)))
    key_bbox = None
    for i, (y0, y1, x0, x1, text) in enumerate(texts):
        m = re.search(r"1\s*=\s*([A-G])", text)
        if m:
            out["key"] = f"1={m.group(1)}"
            key_bbox = [x0, y0, x1, y1]
            out["evidence"] = {"page": 0, "bbox": key_bbox, "text": text}
            # 竖排分数:同带内小组件上下叠
            meter = _stacked_fraction(arr, y0, y1, x0, x1, ocr)
            if meter:
                out["meter"] = meter
                out["meter_assumed"] = False
            else:
                out["warnings"].append(f"拍号竖排分数未读出(行文本 {text!r})"
                                       "，按 4/4 假定")
            # 速度行:调号行之后首个 =nnn
            for y0b, y1b, _, _, tb in texts[i + 1:]:
                mt = re.search(r"=\s*[^\d]{0,3}(\d{2,3})", tb)
                if mt:
                    out["tempo_bpm"] = int(mt.group(1))
                    break
            break
    if out["key"] is None:
        out["warnings"].append("页眉未读出 1=X 调号行,调号/拍号待人工")
    return out


def _stacked_fraction(arr, y0, y1, x0, x1, ocr):
    """调号行带内找竖排分数(两只小数字 x 重叠上下叠)→ 'n/d';无则 None。"""
    from .paddle_ocr import digit_cell

    band = arr[y0:y1 + 1, x0:x1 + 1]
    comps = _components(band)
    small = [c for c in comps
             if c[3] <= 0.45 * (y1 - y0) and c[2] <= 0.45 * (y1 - y0)]
    for a in small:
        for b in small:
            if a is b or a[1] >= b[1]:
                continue
            ax0, ax1c = a[0], a[0] + a[2]
            bx0, bx1c = b[0], b[0] + b[2]
            overlap = min(ax1c, bx1c) - max(ax0, bx0)
            if overlap <= 0.5 * min(a[2], b[2]):
                continue
            gap = b[1] - (a[1] + a[3])
            if not (0 <= gap <= 0.3 * (y1 - y0)):
                continue
            cells = [Glyph("fraction_digit", float(c[0]), float(c[1]),
                           float(c[2]), float(c[3])) for c in (a, b)]
            labels = ocr.digit_labels(band, cells)
            top, bot = labels[0][0], labels[1][0]
            if top.isdigit() and bot.isdigit():
                return f"{top}/{bot}"
    return None


def _grid_fit(measure: dict, grid: dict | None) -> dict | None:
    """候选拍网格互证(工单41 教训:只出证据不标定):本小节各音 x 到
    「按拍号取的候选拍位 x 网格」的最近距离。残差大=锚位漂移或读错,
    交校对台目验;拍位本身仍以时值累加为准,此字段不做决策。"""
    if grid is None or not measure["notes"]:
        return None
    key = str(int(measure["read_beats"])) if measure["read_beats"] > 0 else "4"
    xs = grid.get(key) or grid.get("4")
    if not xs:
        return None
    res = []
    for n in measure["notes"]:
        d = min(abs(n["x"] - gx) for gx in xs)
        res.append(d)
    return {"grid": key, "mean_px": round(sum(res) / len(res), 1),
            "max_px": round(max(res), 1), "n": len(res)}
