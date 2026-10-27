"""版面切分(工单48):位图渲染 → 倾斜纠正 → 谱表系统 → 四层条带 → 小节/拍位网格。

几何常量以「弦距 gap」为单位(census 直移:谱全了原生位图 gap≈15.5px、
谱线浅灰 235 才够到、字形墨 195;工单39/41 实测档案)。只切结构不做符号
识别(工单49/50 的活);输出 bbox 证据全程携带。

实测版式(census+本轮像素考古):谱全了 PDF 每页 2×2 排 4 条 993×1404 位图
= 上下两个整谱页;整谱页内系统通栏(左右两半的谱线同高相接),每系统条带
自上而下 = 段落标注(小字,h≈13) / 和弦图(框 h≈54) / 和弦名(h≈19-25) /
TAB(谱线+梁杆+扫弦箭头) / 简谱(数字 h≈20+八度点+时值线) / 歌词(h≈18-31)。
逐小节不等宽(census 教训),拍位只给候选拍网格不标定(工单41 撞墙点)。
"""

from dataclasses import dataclass
from pathlib import Path
import json

import cv2
import numpy as np

from . import __version__

LINE_GRAY_MAX = 235       # 谱线/小节线灰度阈(census T_LINE)
INK_GRAY_MAX = 195        # 字形墨阈(census T_INK)

# 谱表检测(绝对 px 域,覆盖原生位图 15.5 与 300dpi 渲染 19.3 两档)
LINE_ROW_FRAC = 0.30      # 行墨量 ≥ 页宽此比例 → 谱线行候选(通栏实测 0.83、
                          # 半幅末系统 0.43、歌词行 ≤0.25;工单47 的 0.75 漏半幅)
LINE_ROW_MERGE = 2        # 相邻行 ≤2px 并成一根线
LAYER_KINDS = ("tab", "chord_diagram", "chord_name", "jianpu", "lyrics",
               "annotation")
TAB_GAP_MIN, TAB_GAP_MAX = 10, 36   # 弦距范围 px(原生 15.5 / 300dpi 19.3;
                          # 与 layout.py 同名常量值域不同,勿共导入)
GAP_UNIFORM_MAX = 3       # 组内线距 max-min ≤ 此 → 等距
STAFF_GROUP_DY = 40       # 相邻线 dy ≤ 此 → 同组扫描窗(≈2.5 弦距)


@dataclass(frozen=True)
class TabStaff:
    """一组四线谱系统:四根弦线 + 横向范围(px,y 向下)。"""

    top: float              # ①线 y
    gap: float              # 平均弦距
    line_ys: tuple          # 四线 y
    x0: float
    x1: float

    @property
    def bottom(self) -> float:
        return self.line_ys[-1]


# ── 条带分类(组件级,gap 为单位;census 实测:和弦图框 h≈3.5g、和弦名/数字
#    h≈1.2-1.6g、段落标注 h≈0.84g、时值线 h≈0.16g、歌词 h≈1.2-2.0g) ──────

COMP_MIN_AREA = 12        # 组件最小面积(px,同 layout.py 字形下限)
STAFF_TOUCH_FRAC = 0.3    # 组件与谱线行带 [t−0.3g, t_b+0.3g] 相交 → TAB 附属
DIAGRAM_MIN_H_FRAC = 2.0  # 谱上浮空组件 h ≥ 2.0g → 和弦图框
TEXT_MAX_H_FRAC = 1.7     # 谱上浮空组件 h ≤ 1.7g → 文本(和弦名/标注)
NAME_WINDOW_FRAC = 2.6    # 和弦名窗口:组件底 ≥ ①线 − 2.6g(实测 −0.7..−1.8g)
UNDERLINE_H_FRAC = 0.25   # 时值线:厚 ≤ 0.25g 且长 ≥ 1.2g(实测 2-3px 厚)
UNDERLINE_W_FRAC = 1.2
CLUSTER_GAP_FRAC = 0.35   # 行带外扩(实测:时值线↔歌词 0.45g,取其下不粘连)
LYRIC_MIN_H_FRAC = 1.4    # 无时值线时的高字锚:h ≥ 1.4g 且 w ≥ 0.8g(字块)
LYRIC_ANCHOR_W_FRAC = 0.8
TAB_TAIL_W_FRAC = 0.3     # 谱下细竖尾(w ≤ 0.3g,h ≥ 1.2g)= 杆/箭头残段 → TAB
                          # (谱线行清零把贯穿杆切成触带主体+谱下细尾)
TAB_TAIL_H_FRAC = 1.2


@dataclass(frozen=True)
class LayerBand:
    """一层条带(渲染 px,bbox 证据)。"""

    kind: str               # tab | chord_diagram | chord_name | jianpu |
                            # lyrics | annotation
    x0: float
    y0: float
    x1: float
    y1: float


def split_system_layers(gray: np.ndarray, staff: TabStaff,
                        block_top: float, block_bottom: float) -> dict:
    """单系统条带分类:组件 → 按位置/尺寸归层。

    输入块窗口 [block_top, block_bottom](编排层按相邻系统距算,见
    system_blocks);返回六层键,空层为 None。谱上:触谱线带=tab 附属,
    浮空高框=和弦图,窗口内小字=和弦名,更上小字=annotation(段落标注,
    语义未考);谱下:首簇=简谱(携八度点/时值线),次簇=歌词,余=annotation。
    """
    g = staff.gap
    t, tb = staff.top, staff.bottom
    zone_top, zone_bot = t - STAFF_TOUCH_FRAC * g, tb + STAFF_TOUCH_FRAC * g
    ink = (np.asarray(gray) < INK_GRAY_MAX).astype(np.uint8)
    ink[:max(0, int(block_top))] = 0
    ink[min(ink.shape[0], int(block_bottom) + 1):] = 0
    # 谱线是浅灰(<235 才可见),墨阈组件天然不含;削掉线行防箭头/数字粘连误并
    ink[int(t) - 1:int(tb) + 2] = 0
    n, _, stats, _ = cv2.connectedComponentsWithStats(ink)
    tab_c, dia_c, name_c, anno_c, below = [], [], [], [], []
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if area < COMP_MIN_AREA:
            continue
        x1c, y1c = x + w, y + h
        if y < zone_bot and y1c > zone_top:          # 触谱线带
            tab_c.append((x, y, x1c, y1c))
        elif y1c <= zone_top:                        # 谱上浮空
            if h >= DIAGRAM_MIN_H_FRAC * g:
                dia_c.append((x, y, x1c, y1c))
            elif h <= TEXT_MAX_H_FRAC * g:
                (name_c if y1c >= t - NAME_WINDOW_FRAC * g else anno_c).append(
                    (x, y, x1c, y1c))
            else:
                anno_c.append((x, y, x1c, y1c))
        else:                                        # 谱下
            if h <= UNDERLINE_H_FRAC * g and w >= UNDERLINE_W_FRAC * g:
                below.append((x, y, x1c, y1c, True))   # 时值线
            elif w <= TAB_TAIL_W_FRAC * g and h >= TAB_TAIL_H_FRAC * g:
                tab_c.append((x, y, x1c, y1c))         # 杆/箭头谱下细尾
            else:
                below.append((x, y, x1c, y1c, False))
    layers = {k: None for k in LAYER_KINDS}
    # TAB 层恒含谱线本身
    xs0 = [tab[0] for tab in tab_c] + [staff.x0]
    xs1 = [tab[2] for tab in tab_c] + [staff.x1]
    ys0 = [tab[1] for tab in tab_c] + [t - STAFF_TOUCH_FRAC * g]
    ys1 = [tab[3] for tab in tab_c] + [tb + STAFF_TOUCH_FRAC * g]
    layers["tab"] = LayerBand("tab", min(xs0), min(ys0), max(xs1), max(ys1))
    layers["chord_diagram"] = _band(dia_c, "chord_diagram")
    layers["chord_name"] = _band(name_c, "chord_name")
    jp, ly, rest = _below_clusters(below, g)
    layers["jianpu"] = _band(jp, "jianpu")
    layers["lyrics"] = _band(ly, "lyrics")
    anno_c += rest
    layers["annotation"] = _band(anno_c, "annotation")
    return layers


def _band(comps, kind):
    if not comps:
        return None
    return LayerBand(kind, min(c[0] for c in comps), min(c[1] for c in comps),
                     max(c[2] for c in comps), max(c[3] for c in comps))


# ── 小节线与拍位网格(census 判据直移:贯穿谱高的竖线;箭头杆下探过④线
#    实测 49px,以下延/上延 ≤0.5g 排除;逐小节不等宽 → 拍位只出候选网格) ──

BAR_EXTEND_FRAC = 0.5     # 小节线上/下延超出谱线带 ≤ 0.5g(箭头头/尾 0.6-3.2g、
                          # 密集段长音杆上探 1.2g 排除;线与杆同为 4px 厚,
                          # 厚度分不开,单列延伸才是有效缝)
BAR_GROUP_FRAC = 0.8      # 相邻竖线 ≤ 0.8g 并成一个名义界(双线/段落线)
MIN_MEASURE_FRAC = 10.0   # 相邻界距 < 10g → 段落记号/漏网长杆,迭代丢非端点界
                          # (实测真小节最窄 12g、census 最窄 23g;杆距≈1/4 小节)
BEAT_METERS = ("2", "3", "4", "6", "8")   # 候选拍网格的每小节拍数假设


@dataclass(frozen=True)
class Boundary:
    """小节界(名义 x + 成员线证据;双线/段落线成员 >1)。"""

    x: float
    members: tuple


@dataclass(frozen=True)
class Measure:
    index: int
    x0: float
    x1: float
    left: Boundary
    right: Boundary
    beat_grids: dict      # 拍数(str) → 候选拍位 x(含首尾界)


def find_measure_boundaries(gray: np.ndarray, staff: TabStaff) -> tuple:
    """贯穿谱高的竖线 → (小节界, 非小节界记号)。命名界已按 MIN_MEASURE 并。"""
    g = staff.gap
    t, tb = staff.top, staff.bottom
    dark = np.asarray(gray) < LINE_GRAY_MAX
    y0, y1 = max(0, int(t - 2)), min(dark.shape[0], int(tb + BAR_EXTEND_FRAC * g) + 1)
    band = dark[y0:y1]
    need = (tb - t) - 2
    cols = np.flatnonzero(band.sum(axis=0) >= need)
    cands = []
    for x in cols:
        col = dark[:, x]
        y = int(t)
        while y > 0 and col[y - 1]:
            y -= 1
        up = t - y
        y = int(tb)
        while y < dark.shape[0] - 1 and col[y + 1]:
            y += 1
        down = y - tb
        if up <= BAR_EXTEND_FRAC * g and down <= BAR_EXTEND_FRAC * g:
            cands.append(float(x))
    lines = _merge_runs(cands, 2.0)              # 竖线本体(≤2px 列并一根线)
    groups = []
    for x in lines:
        if groups and x - groups[-1][-1] <= BAR_GROUP_FRAC * g:
            groups[-1].append(x)
        else:
            groups.append([x])
    named = [Boundary(float(np.mean(gp)), tuple(gp)) for gp in groups]
    return _separate_measures(named, g)


def _separate_measures(named: list, g: float) -> tuple:
    """分小节界与段落记号:反复丢弃「相邻距 <10g 且非端点」中邻距最小的一根
    (首尾系统线恒保留),被丢的归 marks(证据不丢)。"""
    bounds, marks = list(named), []
    while len(bounds) > 2:
        gaps = [b.x - a.x for a, b in zip(bounds, bounds[1:])]
        i = int(np.argmin(gaps))
        if gaps[i] >= MIN_MEASURE_FRAC * g:
            break
        drop = i + 1 if i == 0 else i  # 端点邻位丢另一根,保护系统首尾线
        marks.append(bounds.pop(drop))
    marks.sort(key=lambda b: b.x)
    return bounds, marks


def _merge_runs(xs: list, tol: float) -> list:
    """有序 x 并 run(隙 ≤ tol),返回各 run 均值。"""
    out = []
    for x in xs:
        if out and x - out[-1][-1] <= tol:
            out[-1].append(x)
        else:
            out.append([x])
    return [float(np.mean(g)) for g in out]


def build_measures(staff: TabStaff, bounds: list, marks: list) -> list:
    """相邻界成小节;每小节给各拍数假设下的等分候选拍位网格。"""
    measures = []
    for i, (a, b) in enumerate(zip(bounds, bounds[1:])):
        width = b.x - a.x
        grids = {m: tuple(a.x + width * k / int(m) for k in range(int(m) + 1))
                 for m in BEAT_METERS}
        measures.append(Measure(i, a.x, b.x, a, b, grids))
    return measures


# ── 系统分块与编排(渲染 → 纠偏 → 系统 → 分块分层 → 裁图 + 骨架 JSON) ────

BLOCK_STRIP_TOP_FRAC = 11.5   # 切缝搜索带上界:本系统时值线底(实测 11.2g)之下
BLOCK_STRIP_BOT_FRAC = 5.5    # 带下界:下系统段标注顶(实测 5.7g)之上
BLOCK_FIRST_TOP_FRAC = 8.8    # 首系统块顶(t − 8.8g,含段标注 −8.3g,排除页眉)
BLOCK_LAST_FRAC = 14.0        # 页内末系统块底(t + 14g,含歌词底 13.3g)
LAYER_PAD_PX = 2              # 裁图外扩 px

SCHEMA = "ukeflow.workbench.layout/1"


def block_cuts(gray: np.ndarray, systems: list, page_h: float) -> list:
    """相邻系统间的切缝 y:在「本系统时值线之下、下系统段标注之上」的带内找
    最大空行隙取中点;无空隙退化为带中点。首块顶=t₀−8.8g(含段标注,排除
    页眉标题/调号行);返回 len(systems)+1 个块边界。"""
    cuts = [max(0.0, systems[0].top - BLOCK_FIRST_TOP_FRAC * systems[0].gap)]
    for a, b in zip(systems, systems[1:]):
        strip0 = a.top + BLOCK_STRIP_TOP_FRAC * a.gap
        strip1 = min(b.top - BLOCK_STRIP_BOT_FRAC * b.gap, page_h)
        cut = _largest_gap_cut(gray, strip0, strip1)
        cuts.append(cut if cut is not None else (strip0 + strip1) / 2)
    last = systems[-1]
    cuts.append(min(last.top + BLOCK_LAST_FRAC * last.gap, page_h))
    return cuts


def _largest_gap_cut(gray: np.ndarray, y0: float, y1: float):
    """[y0,y1) 内最大空行隙的中点 y;带内全墨则 None。"""
    r0, r1 = max(0, int(y0)), min(gray.shape[0], int(y1))
    if r1 <= r0:
        return None
    dark = (np.asarray(gray) < LINE_GRAY_MAX)[r0:r1].sum(axis=1) > 0
    best_len, best_mid, run_start = 0, None, None
    for i, ink in enumerate(dark):
        if not ink:
            if run_start is None:
                run_start = i
        else:
            if run_start is not None and i - run_start > best_len:
                best_len, best_mid = i - run_start, r0 + (run_start + i) / 2
            run_start = None
    if run_start is not None and len(dark) - run_start > best_len:
        best_mid = r0 + (run_start + len(dark)) / 2
    return best_mid


def split_page_systems(gray: np.ndarray) -> dict:
    """单渲染页:纠偏 → 系统检测 → 分块分层 + 小节/拍位。返回编排 dict。"""
    angle = estimate_skew_deg(gray)
    corrected = False
    if abs(angle) > SKEW_EPS:
        gray = deskew(gray, angle)
        corrected = True
    systems = sorted(find_tab_systems(gray), key=lambda s: s.top)
    page_h = gray.shape[0]
    cuts = block_cuts(gray, systems, page_h) if systems else []
    out_systems = []
    for i, s in enumerate(systems):
        top, bottom = cuts[i], cuts[i + 1]
        layers = split_system_layers(gray, s, top, bottom)
        bounds, marks = find_measure_boundaries(gray, s)
        out_systems.append({
            "staff": s,
            "block": (top, bottom),
            "layers": layers,
            "measures": build_measures(s, bounds, marks),
            "marks": marks,
        })
    return {"gray": gray, "angle_deg": angle, "corrected": corrected,
            "systems": out_systems}


def split_pdf(path: str, out_dir: str, dpi: int = 300) -> dict:
    """票面主入口:位图 PDF → 逐系统逐层裁图 + 小节/拍位骨架 JSON。

    谱全了每页 2×2 排 4 条位图 = 上下两个整谱页;系统按渲染页 y 序归属
    上/下半(score_page = pdf_page×2 + half)。产物:out_dir/layout.json +
    out_dir/crops/p<页>h<半>s<序>_<层>.png。bbox 证据全程携带(渲染 px)。
    """
    import pymupdf

    from .classify import is_vector_score
    from .checkup import checkup_pdf
    from .report import sha256_file

    if not (300 <= dpi <= 400):
        raise ValueError(f"dpi 须在 300-400,得 {dpi}")
    checkup = checkup_pdf(path)
    if checkup.n_images == 0 or is_vector_score(checkup):
        # 工单47 分流:矢量谱 report_only,位图路径不接(spec Non-goal);
        # 闸=「有位图且非矢量谱特征」,不用 triage 的 0.5 覆盖率线
        # (半页位图摆放是合法输入,浮点 0.4999 会误触)。
        raise ValueError(
            f"非位图谱(位图对象 {checkup.n_images}、覆盖率 "
            f"{checkup.image_coverage:.2f}、矢量指令 {checkup.n_drawings}),"
            "矢量/空白谱按工单47 只报告不切分")
    scale = dpi / 72.0
    out = Path(out_dir)
    (out / "crops").mkdir(parents=True, exist_ok=True)
    score_pages, warnings, deskews, sys_no = [], [], [], 0
    doc = pymupdf.open(path)
    try:
        for pno, page in enumerate(doc):
            pix = page.get_pixmap(matrix=pymupdf.Matrix(scale, scale),
                                  colorspace=pymupdf.csGRAY)
            arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(
                pix.height, pix.width).copy()
            result = split_page_systems(arr)
            deskews.append({"pdf_page": pno,
                            "angle_deg": round(result["angle_deg"], 3),
                            "applied": result["corrected"]})
            if result["corrected"]:
                warnings.append(f"pdf页{pno}:纠偏 {result['angle_deg']:.2f}°")
            mid = arr.shape[0] / 2
            for half in (0, 1):
                entry = {"index": pno * 2 + half, "pdf_page": pno, "half": half,
                         "systems": []}
                limit = mid if half == 0 else arr.shape[0]
                for item in result["systems"]:
                    s = item["staff"]
                    if (s.top < mid) != (half == 0):
                        continue
                    item["truncated"] = (s.top + BLOCK_LAST_FRAC * s.gap
                                         > limit)  # 位图半页硬边裁内容
                    entry["systems"].append(_system_json(
                        item, sys_no, pno, half, out, result["gray"]))
                    sys_no += 1
                score_pages.append(entry)
    finally:
        doc.close()
    report = {
        "schema": SCHEMA,
        "tool_version": __version__,
        "source": {"file": str(Path(path).resolve()), "sha256": sha256_file(path),
                   "dpi": dpi, "render_scale": scale},
        "deskew": deskews,
        "score_pages": score_pages,
        "warnings": warnings,
    }
    with open(out / "layout.json", "w", encoding="utf-8") as fh:
        fh.write(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    return report


def _round(v):
    return round(float(v), 1)


def _system_json(item, sys_no, pno, half, out, gray):
    s = item["staff"]
    layers_json = {}
    for kind in LAYER_KINDS:
        band = item["layers"].get(kind)
        if band is None:
            layers_json[kind] = None
            continue
        name = f"p{pno:02d}h{half}s{sys_no:02d}_{kind}.png"
        _save_crop(gray, band, out / "crops" / name)
        layers_json[kind] = {
            "bbox": [_round(band.x0), _round(band.y0), _round(band.x1),
                     _round(band.y1)],
            "crop": f"crops/{name}",
        }
    return {
        "index": sys_no,
        "staff": {"top": _round(s.top), "bottom": _round(s.bottom),
                  "gap": _round(s.gap), "line_ys": [_round(y) for y in s.line_ys],
                  "x0": _round(s.x0), "x1": _round(s.x1),
                  "bbox": [_round(s.x0), _round(s.top), _round(s.x1),
                           _round(s.bottom)]},
        "block": [_round(item["block"][0]), _round(item["block"][1])],
        "truncated": item["truncated"],
        "layers": layers_json,
        "measures": [{
            "index": m.index, "x0": _round(m.x0), "x1": _round(m.x1),
            "left": {"x": _round(m.left.x),
                     "members": [_round(x) for x in m.left.members]},
            "right": {"x": _round(m.right.x),
                      "members": [_round(x) for x in m.right.members]},
            "beat_grids": {k: [_round(x) for x in v]
                           for k, v in m.beat_grids.items()},
        } for m in item["measures"]],
        "non_measure_marks": [{
            "x": _round(b.x), "members": [_round(x) for x in b.members],
        } for b in item["marks"]],
    }


def _save_crop(gray: np.ndarray, band: LayerBand, path: Path) -> None:
    pad = LAYER_PAD_PX
    y0 = max(0, int(band.y0) - pad)
    y1 = min(gray.shape[0], int(band.y1) + 1 + pad)
    x0 = max(0, int(band.x0) - pad)
    x1 = min(gray.shape[1], int(band.x1) + 1 + pad)
    cv2.imwrite(str(path), gray[y0:y1, x0:x1])


def _below_clusters(below, g):
    """谱下组件 → (简谱, 歌词, 其余)。有简谱时值线(h≤0.25g 长横)则以最深
    一根 +0.35g 为分界:其上=简谱(数字/八度点/休止),其下=歌词;无时值线
    退化为高字锚行带(h ≥ 1.4g 且 w ≥ 0.8g)。组件形=(x, y, x1, y1, 时值线?)。
    (bbw 歌词仅 1.16g 高,与 aini 数字 1.29g 交叠,高度单独不可分。)"""
    if not below:
        return [], [], []
    underlines = [c for c in below if c[4]]
    if underlines:
        divider = max(c[3] for c in underlines) + CLUSTER_GAP_FRAC * g
        jianpu = [c for c in below if c[3] <= divider]
        lyrics = [c for c in below if c[3] > divider]
        return jianpu, lyrics, []
    lyric_h = LYRIC_MIN_H_FRAC * g
    anchors = [c for c in below if not c[4]
               and c[3] - c[1] >= lyric_h
               and c[2] - c[0] >= LYRIC_ANCHOR_W_FRAC * g]
    if not anchors:
        return below, [], []
    ly0 = min(c[1] for c in anchors) - CLUSTER_GAP_FRAC * g
    ly1 = max(c[3] for c in anchors) + CLUSTER_GAP_FRAC * g
    lyrics, rest = [], []
    for c in below:
        (lyrics if c[3] >= ly0 and c[1] <= ly1 else rest).append(c)
    jianpu = [c for c in rest if c[3] <= ly0]
    rest = [c for c in rest if c[3] > ly0]
    return jianpu, lyrics, rest


SKEW_KERNEL_FRAC = 50     # 横向开运算核长 = 页宽此比例(桥接字形,留谱线)
SKEW_MIN_LINE_W = 16      # 参与估角的线组件最短宽
SKEW_MIN_POINTS = 100     # 线像素少于此不估(空页),返回 0
SKEW_EPS = 0.05           # |角| ≤ 此视为零(谱全了原生位图为 0)


def estimate_skew_deg(gray: np.ndarray) -> float:
    """谱线倾角估计(度,顺时针为正):横向开运算取出长横线组件,逐件拟合取中位。"""
    gray = np.asarray(gray)
    h, w = gray.shape
    dark = (gray < LINE_GRAY_MAX).astype(np.uint8)
    kernel = max(SKEW_MIN_LINE_W, w // SKEW_KERNEL_FRAC)
    horiz = cv2.morphologyEx(dark, cv2.MORPH_OPEN,
                             cv2.getStructuringElement(cv2.MORPH_RECT, (kernel, 1)))
    n, labels, stats, _ = cv2.connectedComponentsWithStats(horiz)
    angles = []
    for i in range(1, n):
        if stats[i][2] < w // 4:  # 线组件须近全宽
            continue
        ys, xs = np.nonzero(labels == i)
        if len(xs) < SKEW_MIN_POINTS:
            continue
        vx, vy, _, _ = cv2.fitLine(np.column_stack([xs, ys]).astype(np.float32),
                                   cv2.DIST_L2, 0, 0.01, 0.01)
        angles.append(float(np.arctan2(vy.item(), vx.item()) * 180.0 / np.pi))
    if not angles:
        return 0.0
    angle = float(np.median(angles))
    return 0.0 if abs(angle) <= SKEW_EPS else angle


def deskew(gray: np.ndarray, angle_deg: float) -> np.ndarray:
    """按估计角反向旋转(双线性,白底填充)。"""
    if abs(angle_deg) <= SKEW_EPS:
        return gray
    h, w = gray.shape[:2]
    mat = cv2.getRotationMatrix2D((w / 2, h / 2), angle_deg, 1.0)
    border = 255 if gray.dtype == np.uint8 else 0
    return cv2.warpAffine(gray, mat, (w, h), flags=cv2.INTER_LINEAR,
                          borderValue=border)


def find_tab_systems(gray: np.ndarray) -> list:
    """四线谱系统检测:长横线行 → 并线 → 等距四线组。

    行墨量判据取宽下限(0.30,半幅末系统 0.43 也够到;工单47 的 0.75
    全页宽判据会漏掉无右半配对的末系统),真正的闸门是「等距四线」验证。
    """
    gray = np.asarray(gray)
    width = gray.shape[1]
    lines = _find_lines(gray, width)
    systems = []
    for group in _group_lines(lines):
        quad = _uniform_quad(group)
        if quad is not None:
            x0 = max(ln.x0 for ln in quad)
            x1 = min(ln.x1 for ln in quad)
            gaps = [b.y - a.y for a, b in zip(quad, quad[1:])]
            systems.append(TabStaff(top=quad[0].y, gap=float(np.mean(gaps)),
                                    line_ys=tuple(ln.y for ln in quad),
                                    x0=float(x0), x1=float(x1)))
    return systems


@dataclass(frozen=True)
class _Line:
    y: float
    x0: float
    x1: float


def _find_lines(gray: np.ndarray, width: int) -> list:
    dark = gray < LINE_GRAY_MAX
    rows = np.flatnonzero(dark.sum(axis=1) >= width * LINE_ROW_FRAC)
    out = []
    for y in rows:
        if out and y - out[-1][-1] <= LINE_ROW_MERGE:
            out[-1].append(y)
        else:
            out.append([y])
    lines = []
    for grp in out:
        band = dark[grp[0]:grp[-1] + 1]
        xs = np.flatnonzero(band.any(axis=0))
        lines.append(_Line(float(np.mean(grp)), float(xs.min()), float(xs.max())))
    return lines


def _group_lines(lines: list) -> list:
    groups = []
    for ln in lines:
        if groups and ln.y - groups[-1][-1].y <= STAFF_GROUP_DY:
            groups[-1].append(ln)
        else:
            groups.append([ln])
    return groups


def _uniform_quad(group: list):
    """组内找 4 根等距线(TAB_GAP_MIN..TAB_GAP_MAX);若第 5 根延续等距 = 五线谱谱表,
    整组 run 跳过不算(非目标,不消费)。"""
    i = 0
    while i < len(group):
        quad = group[i:i + 4]
        if len(quad) < 4:
            return None
        gaps = [b.y - a.y for a, b in zip(quad, quad[1:])]
        if not (all(TAB_GAP_MIN <= g <= TAB_GAP_MAX for g in gaps)
                and max(gaps) - min(gaps) <= GAP_UNIFORM_MAX):
            i += 1
            continue
        fifth = group[i + 4] if i + 4 < len(group) else None
        if fifth is not None:
            g4 = fifth.y - quad[-1].y
            if (TAB_GAP_MIN <= g4 <= TAB_GAP_MAX
                    and abs(g4 - np.mean(gaps)) <= GAP_UNIFORM_MAX):
                i += 5  # 五根等距 → 五线谱谱表,整个 run 跳过
                continue
        return quad
    return None
