"""版面信号(工单47②判别的证据侧):位图渲染 → 四线谱系统/文本带/简谱证据。

几何基准(census 档案,工单39/41 实测):render scale=3,谱全了页宽 993px,
弦距 14px;谱线浅灰(census T_LINE=235 才够到),字形墨深(census T_INK=195)。
只报结构信号,不做任何符号识别(工单48-50 的活)。
"""

from dataclasses import dataclass

import cv2
import numpy as np
import pymupdf

from .classify import LayoutSignals

LINE_GRAY_MAX = 235       # 谱线/小节线灰度阈(census T_LINE)
INK_GRAY_MAX = 195        # 字形墨阈(census T_INK)
LINE_ROW_SUM_FRAC = 0.30  # 行墨量 ≥ 页宽此比例 → 谱线行候选,真闸是等距四线验证
                          # (工单48 纠正:旧 0.75 全宽判据漏「无右半配对的半幅
                          # 末系统」(实测覆盖 0.43),aini/bbw 因此少计 1 组)
GAP_MIN, GAP_MAX = 10, 18     # 四线谱弦距范围 @scale3(标称 14)
NOTATION_GAP_MIN, NOTATION_GAP_MAX = 18, 40  # 五线谱线距范围
STAFF_MAX_GAP = 56        # 相邻线距 ≤ 4×弦距 → 同组
GAP_UNIFORM_MAX = 3       # 组内线距 max-min ≤ 此 → 等距
LINE_ROW_MERGE = 2        # 相邻行 ≤2px 并成一根线
DIGIT_W = (6, 15)         # 数字字形宽(census 档案 8×12~10×13)
DIGIT_H = (8, 22)         # 数字字形高
GLYPH_MIN_H = 8           # 字形组件最短边
GLYPH_MIN_AREA = 12
BAND_MIN_H = 8            # 文本带最矮高度
BAND_MERGE_GAP = 10       # 带内空隙 ≤ 此并带(数字行与其时值线)
BAND_ROW_INK_MIN = 20     # 计带的行墨量下限(px)
STAFF_MARGIN = 8          # staff 跨度外扩,带检测跳过谱上字形
UNDERLINE_MIN_LEN = 22    # 简谱时值线最短横 run(汉字横笔画 ≤18,以此分界)
UNDERLINE_MAX_THICK = 3
UNDERLINE_MIN_COUNT = 2   # 带内 ≥ 此根时值线 → 时值线带
DIGIT_BAND_MIN = 4        # 数字 ≥ 此且占比达标 → 数字带
DIGIT_BAND_FRAC = 0.3


@dataclass(frozen=True)
class _Line:
    y: float
    thick: int


def extract_layout_pixmap(pix: pymupdf.Pixmap) -> LayoutSignals:
    if pix.n != 1:
        pix = pymupdf.Pixmap(pymupdf.csGRAY, pix)
    gray = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width)
    return extract_layout_gray(gray)


def extract_layout_gray(gray: np.ndarray) -> LayoutSignals:
    gray = np.asarray(gray)
    height, width = gray.shape
    lines = _find_lines(gray, width)
    groups = _group_lines(lines)
    tab = notation = other = 0
    spans = []
    for g in groups:
        quad = _uniform_quad(g)
        if quad is not None and _has_fifth(g, quad):
            notation += 1
            spans.append((quad[0].y - STAFF_MARGIN, quad[-1].y + STAFF_MARGIN))
        elif quad is not None:
            tab += 1
            spans.append((quad[0].y - STAFF_MARGIN, quad[-1].y + STAFF_MARGIN))
        else:
            other += 1
            spans.append((g[0].y - STAFF_MARGIN, g[-1].y + STAFF_MARGIN))
    bands = _find_bands(gray, width, spans)
    text_bands = digit_bands = underline_bands = 0
    for band_mask in bands:
        glyph_n, digit_n = _band_glyph_stats(band_mask)
        if glyph_n >= 4:
            text_bands += 1
        if digit_n >= DIGIT_BAND_MIN and glyph_n > 0 and digit_n / glyph_n >= DIGIT_BAND_FRAC:
            digit_bands += 1
        if _count_underlines(band_mask) >= UNDERLINE_MIN_COUNT:
            underline_bands += 1
    return LayoutSignals(tab_systems=tab, notation_staves=notation,
                         text_bands=text_bands, digit_bands=digit_bands,
                         underline_bands=underline_bands, other_line_groups=other)


def _line_rows(gray: np.ndarray, width: int) -> np.ndarray:
    """谱线行号(行墨量判据,_find_lines 与 _line_row_mask 共用)。"""
    dark = gray < LINE_GRAY_MAX
    return np.flatnonzero(dark.sum(axis=1) > width * LINE_ROW_SUM_FRAC)


def _find_lines(gray: np.ndarray, width: int) -> list:
    out = []
    rows = _line_rows(gray, width)
    for y in rows:
        if out and y - out[-1][-1] <= LINE_ROW_MERGE:
            out[-1].append(y)
        else:
            out.append([y])
    return [_Line(float(np.mean(g)), len(g)) for g in out]


def _group_lines(lines: list) -> list:
    groups = []
    for ln in lines:
        if groups and ln.y - groups[-1][-1].y <= STAFF_MAX_GAP:
            groups[-1].append(ln)
        else:
            groups.append([ln])
    return groups


def _uniform(gaps, lo, hi, slack):
    return all(lo <= g <= hi for g in gaps) and max(gaps) - min(gaps) <= slack


def _uniform_quad(group) -> list | None:
    """组内首个等距四线窗(线距 GAP_MIN..NOTATION_GAP_MAX,tab 与五线谱同扫;
    tab/notation 由第 5 线是否延续等距定)。无则 None。
    (行墨量 0.30 会放进杂行,整组==4 不再成立,须扫窗;工单48。)"""
    for i in range(len(group) - 3):
        quad = group[i:i + 4]
        gaps = [b.y - a.y for a, b in zip(quad, quad[1:])]
        if _uniform(gaps, GAP_MIN, NOTATION_GAP_MAX, GAP_UNIFORM_MAX):
            return quad
    return None


def _has_fifth(group, quad) -> bool:
    """四线之后是否续一根等距线(五线谱谱表):第 5 线距须延续同等等距,
    杂行(距 20-40px 的随机行)不算。"""
    idx = group.index(quad[-1])
    if idx + 1 >= len(group):
        return False
    mean = (quad[-1].y - quad[0].y) / 3
    g4 = group[idx + 1].y - quad[-1].y
    return (GAP_MIN <= g4 <= NOTATION_GAP_MAX
            and abs(g4 - mean) <= GAP_UNIFORM_MAX)


def _is_tab(group) -> bool:
    if len(group) != 4:
        return False
    gaps = [b.y - a.y for a, b in zip(group, group[1:])]
    return _uniform(gaps, GAP_MIN, GAP_MAX, GAP_UNIFORM_MAX)


def _is_notation(group) -> bool:
    if len(group) != 5:
        return False
    gaps = [b.y - a.y for a, b in zip(group, group[1:])]
    return _uniform(gaps, NOTATION_GAP_MIN, NOTATION_GAP_MAX, GAP_UNIFORM_MAX + 2)


def _find_bands(gray: np.ndarray, width: int, staff_spans: list) -> list:
    """谱跨度之外的墨带(和弦名/简谱/歌词候选),返回每带的墨掩码。"""
    ink = (gray < INK_GRAY_MAX).copy()
    line_mask = _line_row_mask(gray, width)
    ink[line_mask] = False
    h = gray.shape[0]
    row_ink = ink.sum(axis=1)
    in_staff = np.zeros(h, dtype=bool)
    for y0, y1 in staff_spans:
        in_staff[max(0, int(y0)):min(h, int(y1)) + 1] = True
    dense = (row_ink >= BAND_ROW_INK_MIN) & ~in_staff
    bands = []
    ys = np.flatnonzero(dense)
    if len(ys) == 0:
        return bands
    run = [ys[0]]
    for y in ys[1:]:
        if y - run[-1] <= BAND_MERGE_GAP:
            run.append(y)
        else:
            bands.append(run)
            run = [y]
    bands.append(run)
    out = []
    for rows in bands:
        y0, y1 = rows[0], rows[-1]
        if y1 - y0 + 1 < BAND_MIN_H:
            continue
        mask = np.zeros_like(ink)
        mask[y0:y1 + 1] = ink[y0:y1 + 1]
        out.append(mask)
    return out


def _line_row_mask(gray: np.ndarray, width: int) -> np.ndarray:
    mask = np.zeros(gray.shape, dtype=bool)
    for y in _line_rows(gray, width):
        mask[max(0, y - 1):y + 2] = True
    return mask


def _band_glyph_stats(band_mask: np.ndarray) -> tuple:
    n, _, stats, _ = cv2.connectedComponentsWithStats(band_mask.astype(np.uint8))
    glyphs = 0
    digits = 0
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if w < 4 or h < GLYPH_MIN_H or area < GLYPH_MIN_AREA:
            continue
        glyphs += 1
        if DIGIT_W[0] <= w <= DIGIT_W[1] and DIGIT_H[0] <= h <= DIGIT_H[1]:
            digits += 1
    return glyphs, digits


def _count_underlines(band_mask: np.ndarray) -> int:
    """带内短横 run(≥22px,厚 ≤3 行)计数——简谱时值线证据。"""
    count = 0
    active = []  # (x0, x1, y0) 上一行的 run,跨行合并算厚度
    for y in range(band_mask.shape[0]):
        row = band_mask[y]
        runs = []
        if row.any():
            edges = np.flatnonzero(np.diff(np.concatenate(([0], row.view(np.uint8), [0]))))
            runs = [(int(a), int(b)) for a, b in zip(edges[::2], edges[1::2])]
        nxt = []
        for x0, x1 in runs:
            if x1 - x0 < UNDERLINE_MIN_LEN:
                continue
            prev = next((s for s in active if s[0] < x1 and x0 < s[1]), None)
            y_start = prev[2] if prev else y
            nxt.append((x0, x1, y_start))
        for s in active:
            if not any(s[0] < n1[1] and n1[0] < s[1] for n1 in nxt):
                if y - s[2] <= UNDERLINE_MAX_THICK and s[1] - s[0] >= UNDERLINE_MIN_LEN:
                    count += 1
        active = nxt
    for s in active:
        if band_mask.shape[0] - s[2] <= UNDERLINE_MAX_THICK:
            count += 1
    return count
