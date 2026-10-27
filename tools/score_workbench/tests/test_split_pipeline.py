"""编排缝(工单48):split_pdf 渲染→分块→分层→裁图→骨架 JSON + CLI 分流。

合成 fixture 照谱全了真实结构:整页宽位图(左右两半拼合的原生几何 1986×1404)
放上半个 PDF 页;系统/小节界照 aini sp1 系统2 的 census 实测值。
真机语料冒烟 skipif 无 ~/ukeflow-sources/。
"""

import json
import os
from pathlib import Path

import pymupdf
import pytest

from .conftest import (INK, LINE_GRAY, SH as H, SW as W, sb_block as block,
                       sb_canvas as canvas, paint_full_system,
                       sb_staff as staff)

from score_workbench.cli import main
from score_workbench.split import split_pdf

PAGE_W, PAGE_H = 595.28, 841.89          # A4 pt(谱全了实测)


def scorebook_pdf(tmp_path, name="scorebook.pdf"):
    """上半个 PDF 页放 1986×1404 谱页图(三系统+页眉),下半空白。"""
    img = paint_full_system(canvas())
    staff(img, 434)
    staff(img, 1165)
    for x in (138, 583, 981, 1432, 1845):  # 系统2 的小节界(census 实测)
        img[826:873, x:x + 2] = LINE_GRAY
    block(img, 107, 816, 46, 360)          # 页眉标题(高字块,aini 实测位)
    block(img, 166, 952, 24, 78)           # 调号行
    pix = pymupdf.Pixmap(pymupdf.csGRAY, W, H, img.tobytes(), 0)
    path = tmp_path / name
    doc = pymupdf.open()
    page = doc.new_page(width=PAGE_W, height=PAGE_H)
    page.insert_image(pymupdf.Rect(0, 0, PAGE_W, PAGE_H / 2), pixmap=pix)
    doc.save(path)
    doc.close()
    return str(path)


@pytest.fixture
def scorebook(tmp_path):
    return scorebook_pdf(tmp_path)


def test_split_pdf_skeleton_and_crops(scorebook, tmp_path):
    out = tmp_path / "layout_out"
    report = split_pdf(scorebook, str(out))
    assert report["schema"] == "ukeflow.workbench.layout/1"
    assert report["source"]["dpi"] == 300
    systems = [s for pg in report["score_pages"] for s in pg["systems"]]
    assert len(systems) == 3                       # 上半 3 系统,下半空谱页
    empty = [pg for pg in report["score_pages"] if not pg["systems"]]
    assert len(empty) == 1
    s2 = systems[1]
    assert s2["staff"]["gap"] == pytest.approx(15.5 * 1.2489, abs=1.5)
    kinds = {k for k, layer in s2["layers"].items() if layer}
    assert kinds == {"tab", "chord_diagram", "chord_name", "jianpu", "lyrics"}
    assert len(s2["measures"]) == 4                # census 实测 5 界 4 小节
    # 页眉(标题/调号行)不得并进首系统条带
    s1 = systems[0]
    for kind in ("chord_diagram", "annotation", "chord_name"):
        band = s1["layers"][kind]
        assert band is None or band["bbox"][1] > 300
    widths = [m["x1"] - m["x0"] for m in s2["measures"]]
    native = [445, 398, 451, 413]
    for got, want in zip(widths, native):
        assert got == pytest.approx(want * 1.2489, rel=0.02)
    for layer in s2["layers"].values():
        if layer:
            assert (out / layer["crop"]).exists()  # 裁图落盘且路径可解析
    assert (out / "layout.json").exists()
    on_disk = json.loads((out / "layout.json").read_text(encoding="utf-8"))
    assert on_disk["schema"] == report["schema"]


def test_cli_split_writes_outdir_and_summarizes(scorebook, tmp_path, capsys):
    out = tmp_path / "cli_out"
    rc = main(["split", scorebook, "--out-dir", str(out)])
    assert rc == 0
    text = capsys.readouterr().out
    assert "检出 3 系统" in text and "layout.json" in text  # 系统数与产物都在摘要里
    assert (out / "layout.json").exists()


def test_split_rejects_vector_and_bad_dpi(vector_pdf, scorebook, tmp_path):
    """矢量谱/越界 dpi 大声拒绝(工单47 分流 + repo 先例 override 报错)。"""
    with pytest.raises(ValueError, match="非位图"):
        split_pdf(vector_pdf, str(tmp_path / "v"))
    with pytest.raises(ValueError, match="dpi"):
        split_pdf(scorebook, str(tmp_path / "d"), dpi=500)


SOURCES = Path(os.environ.get("UKEFLOW_SOURCES", Path.home() / "ukeflow-sources"))
AINI = SOURCES / "gs-aini.pdf"
BBW = SOURCES / "gs-bbw.pdf"


@pytest.mark.skipif(not AINI.exists(), reason="无 gs-aini 语料")
def test_real_gs_aini_eighteen_systems(tmp_path):
    """真机冒烟:aini 全 3 页 18 系统(工单47 的 17 漏了半幅末系统),
    谱页系统数 [3,3,3,3,4,2],每系统简谱层非空。"""
    out = tmp_path / "aini"
    report = split_pdf(str(AINI), str(out))
    pages = report["score_pages"]
    counts = [len(pg["systems"]) for pg in pages]
    assert counts == [3, 3, 3, 3, 4, 2]
    all_systems = [s for pg in pages for s in pg["systems"]]
    assert len(all_systems) == 18
    assert all(s["layers"]["jianpu"] for s in all_systems)
    # census 逐小节不等宽实证:同系统小节宽不恒定
    widths = [m["x1"] - m["x0"] for m in all_systems[1]["measures"]]
    assert len(widths) >= 3 and max(widths) - min(widths) > 10


@pytest.mark.skipif(not BBW.exists(), reason="无 gs-bbw 语料")
def test_real_gs_bbw_sixteen_systems(tmp_path):
    out = tmp_path / "bbw"
    report = split_pdf(str(BBW), str(out))
    counts = [len(pg["systems"]) for pg in report["score_pages"]]
    assert counts == [3, 3, 3, 3, 4, 0]            # 末谱页无系统


@pytest.mark.skipif(not AINI.exists(), reason="无 gs-aini 语料")
def test_triage_and_split_system_counts_agree(tmp_path):
    """双实现对账闸(工单48 retro):triage 版面信号(layout.py)与切分
    (split.py)各自检测系统,曾各漏半幅末系统同错 17/15;两数必须相等,
    防任一侧判据再漂移。"""
    from score_workbench.report import triage_pdf

    for pdf in (AINI, BBW):
        tri = triage_pdf(str(pdf))
        rep = split_pdf(str(pdf), str(tmp_path / ("chk_" + pdf.stem)))
        n = sum(len(pg["systems"]) for pg in rep["score_pages"])
        assert tri["layout"]["tab_systems"] == n, f"{pdf.name}: triage vs split"
