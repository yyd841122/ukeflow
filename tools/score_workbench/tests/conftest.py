"""共享 fixture 工厂(test_report/test_cli 复用)。"""

import numpy as np
import pymupdf
import pytest

W, H = 993, 1404


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


@pytest.fixture
def blank_pdf(tmp_path):
    path = tmp_path / "blank.pdf"
    doc = pymupdf.open()
    doc.new_page()
    doc.save(path)
    doc.close()
    return str(path)
