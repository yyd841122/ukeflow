"""版面切分缝(工单48):合成画布照谱全了原生位图几何(gap≈15.5、系统位 434/826/1165)。

常量全走 census 实测值,判据与实现解耦(独立真值=像素考古档案)。
画布工厂在 conftest(sb_* 前缀),此处 W/H/GAP 为其本测域别名。
"""

import cv2
import numpy as np
import pytest

from .conftest import (INK, LINE_GRAY, SH as H, SW as W, sb_block as block,
                       sb_canvas as canvas, paint_full_system,
                       sb_staff as staff)
from score_workbench.split import (
    build_measures,
    deskew,
    estimate_skew_deg,
    find_measure_boundaries,
    find_tab_systems,
    split_system_layers,
)

GAP = 15.5                 # 原生位图弦距(scale3 渲染 14px 的 1/0.8993)


def test_full_width_and_half_width_systems_both_found():
    """通栏系统 + 只占左半幅的末系统都要检出(工单47 漏半幅的回归锁)。"""
    img = canvas()
    staff(img, 434)                     # 通栏:x137..1846
    staff(img, 572, x1=988)             # 半幅末系统:x137..988
    systems = find_tab_systems(img)
    assert len(systems) == 2
    assert systems[0].top == pytest.approx(435, abs=2)
    assert systems[1].top == pytest.approx(573, abs=2)
    assert systems[0].gap == pytest.approx(GAP, abs=1.5)
    assert systems[0].x1 - systems[0].x0 > 1600   # 通栏
    assert systems[1].x1 - systems[1].x0 < 1000   # 半幅


def test_three_systems_at_print_positions():
    """照印张 sp1 的三系统位(434/826/1165),gap 逐组实测。"""
    img = canvas()
    for top in (434, 826, 1165):
        staff(img, top)
    systems = find_tab_systems(img)
    assert [s.top for s in systems] == pytest.approx([434.5, 826.5, 1165.5], abs=1)
    assert all(s.gap == pytest.approx(GAP, abs=1.5) for s in systems)


def test_five_uniform_lines_not_tab():
    """五根等距线 = 五线谱谱表,不算四线谱系统(计数可见即可,非目标)。"""
    img = canvas()
    staff(img, 400, n=5, gap=15.5)
    systems = find_tab_systems(img)
    assert systems == []


def _rotated(img, deg):
    h, w = img.shape
    mat = cv2.getRotationMatrix2D((w / 2, h / 2), deg, 1.0)
    return cv2.warpAffine(img, mat, (w, h), flags=cv2.INTER_LINEAR,
                          borderValue=255)


def test_skew_estimated_and_corrected():
    """0.6° 倾斜的谱线要估出来;纠正后系统照常检出(票面:倾斜纠正)。
    约定:估计值 = 纠正参数(getRotationMatrix2D 同号),内容倾角为其相反数。"""
    img = canvas()
    staff(img, 434)
    skewed = _rotated(img, 0.6)
    angle = estimate_skew_deg(skewed)
    assert angle == pytest.approx(-0.6, abs=0.2)
    fixed = deskew(skewed, angle)
    systems = find_tab_systems(fixed)
    assert len(systems) == 1
    assert systems[0].gap == pytest.approx(GAP, abs=2)


def test_skew_zero_for_clean_print():
    assert estimate_skew_deg(canvas()) == 0.0
    img = canvas()
    staff(img, 434)
    assert estimate_skew_deg(img) == pytest.approx(0.0, abs=0.05)


# ── 条带分类:照 aini sp1 系统2 的 census 实测块(t=826,gap 15.5) ─────────

def paint_full_system(img, top=826):
    """逐层照印张尺寸摆放:段落标注/和弦图/和弦名/谱表+梁杆+箭头/简谱/歌词。"""
    for x in (208, 389, 600, 769, 998, 1179, 1449):
        block(img, 728, x, 54, 52)                       # 和弦图框 52×54
    block(img, 791, 220, 19, 39)                         # 和弦名
    block(img, 796, 577, 19, 30)
    block(img, 818, 700, 8, 3)                           # 梁杆(上探,触谱线)
    staff(img, top)
    for x in (890, 1311):                                # 扫弦箭头杆(贯穿+下探,深墨)
        img[top:top + 94, x:x + 3] = INK
    for x in (213, 271, 309, 394, 451):                  # 简谱数字 14×20
        block(img, 970, x, 20, 14)
    for x in (217, 274, 313, 398, 455):                  # 高音点(数字上方)
        block(img, 957, x, 6, 6)
    for x0, w in ((211, 75), (307, 60), (392, 75)):      # 时值线
        block(img, 993, x0, 2, w)
    for x in (265, 346, 446, 599, 641):                  # 歌词 25px
        block(img, 1007, x, 25, 24)
    return img


def test_layers_of_full_system_block():
    img = paint_full_system(canvas())
    systems = find_tab_systems(img)
    assert len(systems) == 1
    layers = split_system_layers(img, systems[0], block_top=650, block_bottom=1090)
    kinds = {k for k, band in layers.items() if band is not None}
    assert kinds == {"tab", "chord_diagram", "chord_name", "jianpu", "lyrics"}
    assert layers["chord_diagram"].y0 == pytest.approx(728, abs=3)
    assert layers["chord_name"].y1 == pytest.approx(815, abs=4)
    assert layers["tab"].y0 <= 818 and layers["tab"].y1 >= 920  # 含上探梁杆+下探箭头
    assert layers["tab"].y0 <= 826 and layers["tab"].y1 >= 872  # 含全部谱线
    assert layers["jianpu"].y0 == pytest.approx(957, abs=4)     # 八度点起
    assert layers["jianpu"].y1 == pytest.approx(995, abs=4)     # 时值线收
    assert layers["lyrics"].y0 == pytest.approx(1007, abs=3)
    assert layers["lyrics"].y1 == pytest.approx(1032, abs=3)


def test_system_without_diagrams_labels_annotation():
    """无和弦图的系统(aini sys1 型):上方小字行 = annotation,不冒名层。"""
    img = canvas()
    for x in (506, 665, 837, 1175):                      # 段落标注小字 h13
        block(img, 333, x, 13, 12)
    staff(img, 434)
    block(img, 404, 700, 30, 3)                          # 梁杆(上探,触谱线)
    systems = find_tab_systems(img)
    layers = split_system_layers(img, systems[0], block_top=200, block_bottom=660)
    assert layers["chord_diagram"] is None
    assert layers["chord_name"] is None
    assert layers["annotation"].y0 == pytest.approx(333, abs=3)
    assert layers["annotation"].y1 == pytest.approx(346, abs=3)
    assert layers["tab"].y0 <= 405 and layers["tab"].y1 >= 436
    assert layers["jianpu"] is None
    assert layers["lyrics"] is None


# ── 小节线 + 拍位网格(照 aini sp1 系统2 实测:界 138/583/981/1432/1845,
#    小节宽 445/398/451/413 逐节不等宽;1311=扫弦箭头杆,176/185=双线对) ──

def paint_measures(img, top=826):
    staff(img, top)
    for x in (138, 583, 981, 1432, 1845):                # 小节线(灰,恰谱高)
        img[top:top + 47, x:x + 2] = LINE_GRAY
    img[top:top + 96, 1311:1313] = INK                   # 扫弦箭头(下探 49px)
    img[top:top + 47, 176:178] = LINE_GRAY               # 段落双线对
    img[top:top + 47, 185:187] = LINE_GRAY
    return img


def test_measure_boundaries_exclude_arrows_group_doubles():
    img = paint_measures(canvas())
    s = find_tab_systems(img)[0]
    bounds, marks = find_measure_boundaries(img, s)
    assert [b.x for b in bounds] == pytest.approx([138.5, 583.5, 981.5, 1432.5, 1845.5])
    assert len(marks) == 1                               # 双线对并成一名义界
    assert marks[0].x == pytest.approx(180.5, abs=2)
    assert len(marks[0].members) == 2                    # 成员线证据保留


def test_measures_and_beat_grid_candidates():
    img = paint_measures(canvas())
    s = find_tab_systems(img)[0]
    bounds, marks = find_measure_boundaries(img, s)
    measures = build_measures(s, bounds, marks)
    assert [m.x0 for m in measures] == pytest.approx([138.5, 583.5, 981.5, 1432.5])
    assert [m.x1 for m in measures] == pytest.approx([583.5, 981.5, 1432.5, 1845.5])
    g4 = measures[0].beat_grids["4"]
    assert len(g4) == 5
    assert g4[2] == pytest.approx((138 + 583) / 2, abs=1.0)   # 中点=候选拍 2
    assert g4[0] == pytest.approx(138, abs=1.0)
    assert set(measures[0].beat_grids) == {"2", "3", "4", "6", "8"}
    assert len(measures[0].beat_grids["3"]) == 4
    # 双线对落在首小节 3g 内 → 不劈小节(段记号不是小节线)
    assert all(m.x0 > 160 for m in measures[1:])
