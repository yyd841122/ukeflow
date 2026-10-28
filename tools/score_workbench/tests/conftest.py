"""共享 fixture 工厂(test_report/test_cli 复用)+ 版面切分画布工厂(工单48)。"""

import numpy as np
import pymupdf
import pytest

W, H = 993, 1404

# ── 版面切分画布工厂(test_split/test_split_pipeline 复用)────────────────
# 整谱页原生几何:左右两半位图拼合 1986×1404,弦距 15.5,系统位/小节界照
# aini sp1 的 census 实测值。

SW, SH = 1986, 1404        # 整谱页(与上方 triage fixture 的 W,H 同名异值,勿混)
LINE_GRAY = 210            # 谱线浅灰(介于 census T_INK=195 与 T_LINE=235 之间)
INK = 30                   # 字形墨


def sb_canvas():
    return np.full((SH, SW), 255, dtype=np.uint8)


def sb_staff(img, top, x0=137, x1=1846, n=4, gap=15.5):
    for k in range(n):
        img[int(top + k * gap):int(top + k * gap) + 2, x0:x1] = LINE_GRAY


def sb_block(img, y0, x0, h, w, gray=INK):
    img[y0:y0 + h, x0:x0 + w] = gray


def paint_full_system(img, top=826):
    """逐层照印张尺寸摆一个完整系统块(aini sp1 系统2 为模板):
    段落标注/和弦图/和弦名/谱表+梁杆+扫弦箭头/简谱/歌词。"""
    for x in (208, 389, 600, 769, 998, 1179, 1449):
        sb_block(img, 728, x, 54, 52)                    # 和弦图框 52×54
    sb_block(img, 791, 220, 19, 39)                      # 和弦名
    sb_block(img, 796, 577, 19, 30)
    sb_block(img, 818, 700, 8, 3)                        # 梁杆(上探,触谱线)
    sb_staff(img, top)
    for x in (890, 1311):                                # 扫弦箭头杆(贯穿+下探,深墨)
        img[top:top + 94, x:x + 3] = INK
    for x in (213, 271, 309, 394, 451):                  # 简谱数字 14×20
        sb_block(img, 970, x, 20, 14)
    for x in (217, 274, 313, 398, 455):                  # 高音点(数字上方)
        sb_block(img, 957, x, 6, 6)
    for x0, w in ((211, 75), (307, 60), (392, 75)):      # 时值线
        sb_block(img, 993, x0, 2, w)
    for x in (265, 346, 446, 599, 641):                  # 歌词 25px
        sb_block(img, 1007, x, 25, 24)
    return img


def staff_bitmap_pdf(tmp_path, name="solo.pdf"):
    """整页位图、内含一组四线谱系统的合成扫描谱(页 1/3 尺寸照 A4 比例)。"""
    img = np.full((H, W), 255, dtype=np.uint8)
    for k in range(4):
        y = 400 + k * 14
        img[y:y + 2, 40:W - 40] = 210
    for x in (120, 180, 240, 300, 360):
        img[410:422, x:x + 10] = 30
    pix = pymupdf.Pixmap(pymupdf.csGRAY, W, H, img.tobytes(), 0)
    path = tmp_path / name
    doc = pymupdf.open()
    page = doc.new_page(width=W / 3, height=H / 3)
    page.insert_image(page.rect, pixmap=pix)
    doc.save(path)
    doc.close()
    return str(path)


def write_vector_pdf(tmp_path, name="vector.pdf"):
    """矢量谱内容:born-digital,文本+矢量绘图指令,无位图。"""
    path = tmp_path / name
    doc = pymupdf.open()
    page = doc.new_page()
    page.insert_text((72, 72), "Score Title " + "lyrics text " * 10)
    for i in range(30):
        y = 100 + i * 5
        page.draw_line((72, y), (500, y))
    doc.save(path)
    doc.close()
    return str(path)


@pytest.fixture
def vector_pdf(tmp_path):
    return write_vector_pdf(tmp_path)


@pytest.fixture
def bitmap_pdf(tmp_path):
    """位图扫描谱 fixture:整页灰位图,零文本零矢量。"""
    img = np.full((300, 200), 255, dtype=np.uint8)
    pix = pymupdf.Pixmap(pymupdf.csGRAY, 200, 300, img.tobytes(), 0)
    path = tmp_path / "bitmap.pdf"
    doc = pymupdf.open()
    page = doc.new_page(width=200, height=300)
    page.insert_image(page.rect, pixmap=pix)
    doc.save(path)
    doc.close()
    return str(path)


def jianpu_bitmap():
    """两系统简谱合成谱(工单49 retro):每系统 2 小节、每小节数字数不同
    (4/2 与 2/4),专钉「跨系统 spans 拼接错位」一类 bug——各系统 x 域同形,
    单系统 fixture 结构上测不出。"""
    img = sb_canvas()
    for top in (826, 1165):
        sb_staff(img, top)
        for x in (138, 583, 981):                      # 每系统 2 小节界
            img[top:top + 47, x:x + 2] = LINE_GRAY
    for x in (220, 290, 360, 430):                     # 系统0 小节A:4 数字
        sb_block(img, 970, x, 20, 14)
    for x in (640, 710):                               # 系统0 小节B:2 数字
        sb_block(img, 970, x, 20, 14)
    for x in (220, 290):                               # 系统1 小节A:2 数字
        sb_block(img, 1309, x, 20, 14)
    for x in (640, 710, 780, 850):                     # 系统1 小节B:4 数字
        sb_block(img, 1309, x, 20, 14)
    return img


def write_jianpu_pdf(tmp_path, name="two-system.pdf"):
    """jianpu_bitmap → 上半 PDF 页(谱全了位图摆法)。"""
    img = jianpu_bitmap()
    pix = pymupdf.Pixmap(pymupdf.csGRAY, img.shape[1], img.shape[0],
                         img.tobytes(), 0)
    path = tmp_path / name
    doc = pymupdf.open()
    page = doc.new_page(width=595.28, height=841.89)
    page.insert_image(pymupdf.Rect(0, 0, 595.28, 841.89 / 2), pixmap=pix)
    doc.save(path)
    doc.close()
    return str(path)


class FakeOcr:
    """OCR 测试桩:按数字 x 序查表给标签(几何/装配全走真代码)。

    labels 为 list 时按下标;为 dict 时按 glyph x(取整)查,缺 x 给
    (None, 0) —— × 与数字同走 pending 的场合(tab 层)按位给标签。"""

    def __init__(self, labels):
        self._labels = labels

    def digit_labels(self, img, digits):
        if isinstance(self._labels, dict):
            out = []
            for g in digits:
                near = min(self._labels, key=lambda k: abs(k - int(g.x)),
                           default=None)
                lab = self._labels[near] \
                    if near is not None and abs(near - int(g.x)) <= 12 \
                    else None
                out.append((lab, 1.0) if lab is not None else (None, 0.0))
            return out
        return [(self._labels[i], 1.0) for i in range(len(digits))]


# ── TAB 层画布工厂(工单50:test_tab_* 复用)────────────────────────────
# 照 gs-aini 像素考古档案画(300dpi 渲染后 g≈19.4,画布用原生 g=15.5 同
# jianpu 工厂):数字/× 压线(圆心在线上),× 双笔交叉,波浪 8px 蛇形,
# 八分休止点+尾钩,全休止扁杠挂②线下,符杆下行+符尾楔+谱下符杠。

GAP = 15.5


def tab_x_mark(img, cx, cy, g=GAP):
    """×:两笔交叉,~11×14(g=15.5 时 0.7g×0.9g,300dpi 渲染后落档案域)。"""
    w, h = int(g * 0.72), int(g * 0.95)
    x0, y0 = int(cx - w / 2), int(cy - h / 2)
    for k in range(h):
        xa = x0 + int(k * (w - 2) / max(1, h - 1))
        xb = x0 + w - 2 - int(k * (w - 2) / max(1, h - 1))
        img[y0 + k, xa:xa + 2] = INK
        img[y0 + k, xb:xb + 2] = INK
    return img


def tab_digit(img, cx, cy, g=GAP):
    """品位数字占位块(OCR 走桩,几何为主):11×14 压线。"""
    w, h = int(g * 0.68), int(g * 0.9)
    img[int(cy - h / 2):int(cy - h / 2) + h, int(cx - w / 2):int(cx - w / 2) + w] = INK
    return img


def tab_roll(img, cx, top, bottom, g=GAP):
    """卷弦波浪:竖向蛇形,短宽段(8px)长窄段(3px)交替——行宽剖面振荡
    (std ≥0.45、均值 ≤0.35g,照 gs-aini 实测剖面)。"""
    import numpy as np
    period = max(10, int(g) * 14 // 10)
    wide_len = max(3, period // 4)
    ys = np.arange(int(top), int(bottom))
    for y in ys:
        off = (y - int(top)) % period
        if off < wide_len:
            img[y, int(cx) - 4:int(cx) + 4] = INK
        else:
            img[y, int(cx) - 1:int(cx) + 2] = INK
    return img


def tab_rest8(img, cx, cy, g=GAP):
    """八分休止:实心点 15×8 + 右下尾杆(桥接后 15×25,上段致密)。"""
    img[int(cy - 4):int(cy + 4), int(cx - 7):int(cx + 8)] = INK
    for k in range(int(g * 0.75)):
        img[int(cy + 4 + k):int(cy + 5 + k), int(cx + 2):int(cx + 5)] = INK
    return img


def tab_rest_whole(img, cx, ly2, g=GAP):
    """全小节休止:17×4 扁杠挂②线下。"""
    img[int(ly2 + 4):int(ly2 + 8), int(cx - 8):int(cx + 9)] = INK
    return img


def tab_stem_flag(img, x, y0, y1, g=GAP, flag=False):
    """符杆(2px 下行)+ 可选符尾楔(挂杆末 40%,左下垂渐细)。"""
    img[int(y0):int(y1), int(x):int(x) + 2] = INK
    if flag:
        h = max(6, int((y1 - y0) * 0.4))
        for k in range(h):
            w = max(2, int(10 * (1 - k / h)) + 2)
            img[int(y1 - h) + k:int(y1 - h) + k + 1,
                int(x) - w:int(x) + 2] = INK
    return img


def tab_beam(img, x0, x1, y, g=GAP):
    """符杠:3px 厚横杠。"""
    img[int(y):int(y) + 3, int(x0):int(x1)] = INK
    return img


def tab_slide(img, x0, x1, cy):
    """滑音斜杠:24×6 上升斜线。"""
    w = int(x1 - x0)
    for k in range(w):
        y = int(cy + 3 - 6 * k / max(1, w - 1))
        img[y:y + 2, int(x0) + k] = INK
    return img


@pytest.fixture
def blank_pdf(tmp_path):
    path = tmp_path / "blank.pdf"
    doc = pymupdf.open()
    doc.new_page()
    doc.save(path)
    doc.close()
    return str(path)
