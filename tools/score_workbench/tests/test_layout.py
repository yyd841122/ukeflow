"""版面信号缝:合成位图 fixture(照谱全了渲染几何:页宽993、弦距14@scale3)。"""

import numpy as np

from score_workbench.layout import extract_layout_gray, extract_layout_pixmap

W, H = 993, 1404
LINE_GRAY = 210   # 谱线浅灰(介于 census T_INK=195 与 T_LINE=235 之间)
INK = 30          # 字形墨


def canvas():
    return np.full((H, W), 255, dtype=np.uint8)


def hline(img, y, x0, x1, gray=INK, thick=1):
    img[y:y + thick, x0:x1] = gray


def block(img, y0, x0, h, w, gray=INK):
    img[y0:y0 + h, x0:x0 + w] = gray


def staff(img, top, n=4, gap=14):
    for k in range(n):
        hline(img, top + k * gap, 40, W - 40, gray=LINE_GRAY)


def digit_glyphs(img, y, xs, w=10, h=13):
    """数字字形:实心小块(尺寸照 census 档案 8×12~10×13)。"""
    for x in xs:
        block(img, y, x, h, w)


def test_blank_image_zero_signals():
    sig = extract_layout_gray(canvas())
    assert sig.tab_systems == 0
    assert sig.notation_staves == 0
    assert sig.text_bands == 0
    assert sig.digit_bands == 0
    assert sig.underline_bands == 0
    assert sig.other_line_groups == 0


def test_single_tab_staff_detected():
    img = canvas()
    staff(img, 200, n=4, gap=14)
    digit_glyphs(img, 208, [100, 160, 220, 300, 380, 460])  # 弦上数字
    sig = extract_layout_gray(img)
    assert sig.tab_systems == 1
    assert sig.other_line_groups == 0


def test_five_line_staff_is_notation_not_tab():
    img = canvas()
    staff(img, 300, n=5, gap=24)
    sig = extract_layout_gray(img)
    assert sig.tab_systems == 0
    assert sig.notation_staves == 1


def test_tab_plus_jianpu_and_lyrics_bands():
    img = canvas()
    staff(img, 200)                                   # TAB 系统
    digit_glyphs(img, 300, [100, 130, 160, 190, 220, 250, 280, 310])
    hline(img, 318, 100, 126, thick=2)                # 时值下划线(≥22px)
    hline(img, 318, 190, 240, thick=2)
    digit_glyphs(img, 350, [400, 430, 460, 490, 520])
    hline(img, 368, 400, 448, thick=2)
    for i in range(6):                                # 歌词块(汉字尺寸)
        block(img, 420, 100 + i * 40, 18, 18)
    sig = extract_layout_gray(img)
    assert sig.tab_systems == 1
    assert sig.digit_bands >= 1
    assert sig.underline_bands >= 1
    assert sig.text_bands >= 2


def test_strum_like_page_no_staff():
    img = canvas()
    for i in range(8):                                # 和弦名行(较大文本块)
        block(img, 150, 60 + i * 60, 20, 24)
    digit_glyphs(img, 260, [100, 130, 160, 190, 220, 250, 280, 310])
    hline(img, 278, 100, 150, thick=2)                # 时值线
    hline(img, 278, 220, 270, thick=2)
    for i in range(6):                                # 歌词
        block(img, 340, 100 + i * 40, 18, 18)
    sig = extract_layout_gray(img)
    assert sig.tab_systems == 0
    assert sig.digit_bands >= 1
    assert sig.underline_bands >= 1
    assert sig.text_bands >= 2


def test_irregular_four_lines_not_tab():
    # 4 根横线但间距不均(和弦图框残段之类)→ 不算四线谱系统
    img = canvas()
    for y in (200, 260, 350, 356):
        hline(img, y, 40, W - 40, gray=LINE_GRAY)
    sig = extract_layout_gray(img)
    assert sig.tab_systems == 0


def test_pixmap_entry_matches_gray_entry():
    import pymupdf
    img = canvas()
    staff(img, 200)
    pix = pymupdf.Pixmap(pymupdf.csGRAY, W, H, img.tobytes(), 0)
    a = extract_layout_gray(img)
    b = extract_layout_pixmap(pix)
    assert a == b


def test_chinese_stroke_bars_not_underlines():
    # 汉字横笔画(~16px,≤22 阈)不构成时值线带——判别线必须咬合
    img = canvas()
    for i in range(8):                                # 汉字块:块身+内部横笔画
        x = 60 + i * 50
        block(img, 200, x, 18, 18)
        hline(img, 207, x + 1, x + 17, thick=1)
    sig = extract_layout_gray(img)
    assert sig.text_bands >= 1
    assert sig.underline_bands == 0
