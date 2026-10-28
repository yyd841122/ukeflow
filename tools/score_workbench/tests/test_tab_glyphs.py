"""TAB 字形分类与节奏解释单测(工单50):合成画布上的符号 → 角色。

合成几何照 gs-aini 像素考古档案(conftest tab_* 工厂,原生 g=15.5);
OCR 桩按 x 序给标签,几何/节奏/装配全走真代码。
"""

import pytest

from .conftest import (FakeOcr, GAP, sb_block, sb_staff, tab_beam,
                       tab_digit, tab_rest8, tab_rest_whole, tab_roll,
                       tab_slide, tab_stem_flag, tab_x_mark)
from score_workbench.tab import (classify_symbols, cluster_attacks,
                                 drop_bound_barlines, read_duration,
                                 staff_components, _tall_column,
                                 Attack)


def _canvas_with_staff():
    import numpy as np
    img = np.full((400, 900), 255, dtype=np.uint8)
    sb_staff(img, 200)                       # 四线 @200/215.5/235/254.5… g=15.5
    return img, [200.0, 215.5, 235.0, 254.5]


def _syms(img, ocr=None):
    lys = [200.0, 215.5, 235.0, 254.5]
    ci, cb = staff_components(img, lys, lys[0], lys[3], GAP, 0, 900)
    return classify_symbols(ci, cb, GAP, lys, 0, img, ocr)


def test_digit_on_line_ocr_whitelist():
    """压线数字 → pending → OCR 白名单分流 digit;× 读数非数字归 x_mark。"""
    img, _ = _canvas_with_staff()
    tab_digit(img, 300, 215.5)               # ②弦品位数字(压 ② 线)
    tab_x_mark(img, 400, 235.0)              # ③弦 ×
    syms = _syms(img, FakeOcr({295: "3"}))
    roles = {s.role for s in syms}
    assert "digit" in roles and "x_mark" in roles
    digit = next(s for s in syms if s.role == "digit")
    assert digit.label == "3"
    assert abs(digit.cy - 215.5) < 0.6 * GAP


def test_x_mark_rejects_digit_label_from_two_stroke_top():
    """× 被穿线读成数字(实测 0/7/8)→ 顶部双笔行兜回 x_mark,读数留证。"""

    class LyingOcr:
        def digit_labels(self, img, glyphs):
            return [("8", 0.9)] * len(glyphs)

    img, _ = _canvas_with_staff()
    tab_x_mark(img, 400, 215.5)
    syms = _syms(img, LyingOcr())
    marks = [s for s in syms if s.role == "x_mark"]
    assert marks and marks[0].label == "8"   # 读数留证(ADR-0009)


def test_roll_zigzag_vs_arrow_shaft():
    """波浪(蛇形振荡)→ roll;细杆+单端加宽 → 箭头定向。"""
    import numpy as np
    img, _ = _canvas_with_staff()
    lys = [200.0, 215.5, 235.0, 254.5]
    tab_roll(img, 300, 180, 280)             # 蛇形贯穿
    # 箭头:2px 细杆 + 顶端 9×4 加宽头(头在 ①线上方,照印张 0.26g 矮头)
    img[150:270, 500:502] = 30
    img[148:152, 496:505] = 30
    # 波浪的行宽剖面直接喂判据(tab_roll 的蛇形 = 3-5px 振荡)
    roll_img = np.full((100, 24), 255, dtype=np.uint8)
    tab_roll(roll_img, 10, 0, 100, g=GAP)
    assert _tall_column(roll_img, 6, 0, 8, 100, GAP, lys)[0] == "roll"
    assert _tall_column(img, 496, 148, 9, 122, GAP, lys) == \
        ("strum", "strumUp")


def test_rest8_and_rest_whole():
    img, _ = _canvas_with_staff()
    tab_rest8(img, 300, 235.0)               # 八分休止:点+尾钩(挂 ③ 线)
    tab_rest_whole(img, 400, 215.5)          # 全小节休止:扁杠挂 ② 线下
    syms = _syms(img, FakeOcr([]))
    kinds = sorted(s.role for s in syms if s.role.startswith("rest"))
    assert kinds == ["rest8", "rest_whole"]


def test_slide_between_digits():
    img, _ = _canvas_with_staff()
    tab_digit(img, 300, 215.5)
    tab_digit(img, 360, 215.5)
    tab_slide(img, 318, 342, 209.0)          # 弦线高度斜杠(线带上方,照印张)
    syms = _syms(img, FakeOcr({295: "7", 354: "4"}))
    assert any(s.role == "slide" for s in syms)


def test_barline_at_measure_bound_dropped():
    """小节界上的贯穿细杆且近旁无音位 → barline(非箭头)。"""
    img, _ = _canvas_with_staff()
    img[190:270, 500:504] = 30               # 贯穿杆
    syms = _syms(img, FakeOcr([]))
    syms = drop_bound_barlines(syms, [500.0], GAP)
    assert any(s.role == "barline" for s in syms)
    assert not any(s.role == "shaft" for s in syms)


# ── 节奏解释:attack 聚簇 + 时值 ──────────────────────────────────────

def _attack_from(img, ocr=None):
    syms = _syms(img, ocr)
    attacks, _ = cluster_attacks(syms, GAP)
    for a in attacks:
        a.duration = read_duration(a, GAP, 4.0)
    return attacks


def test_duration_flag_and_beam_and_dot():
    img, _ = _canvas_with_staff()
    tab_digit(img, 300, 215.5)
    tab_stem_flag(img, 306, 220, 300, flag=True)     # 杆+谱下符尾 = 八分
    tab_digit(img, 380, 215.5)
    tab_stem_flag(img, 386, 220, 250)                # 裸杆 = 四分(杆在带内)
    tab_beam(img, 380, 430, 262)                     # 双符杠盖 ② 杆
    tab_beam(img, 380, 430, 267)                     # = 十六分
    attacks = _attack_from(img, FakeOcr({295: "1", 375: "5"}))
    by_x = sorted(attacks, key=lambda a: a.cx)
    assert by_x[0].duration == 0.5
    assert by_x[1].duration == 0.25


def test_duration_bracket_quarter_default():
    """无杆尾杠而有延音括线 = 四分攻+延音(印张长音画法)。"""
    import numpy as np
    img, _ = _canvas_with_staff()
    tab_digit(img, 300, 215.5)
    # 空心括线(④线下,∪ 形整块,照印张 53×59)
    img[264:310, 280:283] = 30
    img[264:310, 330:333] = 30
    img[307:310, 280:333] = 30
    attacks = _attack_from(img, FakeOcr({295: "4"}))
    assert attacks[0].duration == 1.0
    assert attacks[0].bracket


def test_duration_none_warns():
    img, _ = _canvas_with_staff()
    tab_digit(img, 300, 215.5)               # 孤数字,无任何节奏记号
    attacks = _attack_from(img, FakeOcr({295: "2"}))
    assert attacks[0].duration is None


def test_x_stack_strings_decoded():
    """同 x 多弦 × 纵连(桥接成堆)→ 折合弦数落证据。"""
    img, _ = _canvas_with_staff()
    for cy in (215.5, 235.0, 254.5):         # ②③④ 三弦 × 堆
        tab_x_mark(img, 300, cy)
    attacks = _attack_from(img, FakeOcr([]))
    stacks = [a for a in attacks if a.x_marks]
    assert stacks and stacks[0].x_marks[0].role == "x_stack"
    assert stacks[0].x_marks[0].h / GAP == pytest.approx(3.0, abs=0.6)
