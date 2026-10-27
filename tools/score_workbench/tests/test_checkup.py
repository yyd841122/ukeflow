"""体检缝:合成 PDF fixture(矢量/位图/空白)驱动。"""

import pytest
import pymupdf

from score_workbench.checkup import checkup_pdf


@pytest.fixture
def vector_pdf(tmp_path):
    """矢量谱 fixture:born-digital,文本+矢量绘图指令,无位图。"""
    path = tmp_path / "vector.pdf"
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
def bitmap_pdf(tmp_path):
    """位图扫描谱 fixture:整页灰位图,零文本零矢量。"""
    import numpy as np

    path = tmp_path / "bitmap.pdf"
    img = np.full((300, 200), 255, dtype=np.uint8)
    pix = pymupdf.Pixmap(pymupdf.csGRAY, 200, 300, img.tobytes(), 0)
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


def test_vector_pdf_has_text_and_drawings_no_coverage(vector_pdf):
    s = checkup_pdf(vector_pdf)
    assert s.pages == 1
    assert s.text_chars >= 100
    assert s.n_drawings >= 20
    assert s.image_coverage == pytest.approx(0.0, abs=0.01)
    assert s.n_images == 0


def test_bitmap_pdf_full_coverage_no_text(bitmap_pdf):
    s = checkup_pdf(bitmap_pdf)
    assert s.image_coverage == pytest.approx(1.0, abs=0.01)
    assert s.n_images >= 1
    assert s.text_chars == 0
    assert s.n_drawings == 0


def test_blank_pdf_all_zero(blank_pdf):
    s = checkup_pdf(blank_pdf)
    assert s.pages == 1
    assert s.text_chars == 0
    assert s.n_images == 0
    assert s.image_coverage == pytest.approx(0.0, abs=0.01)
    assert s.n_drawings == 0
