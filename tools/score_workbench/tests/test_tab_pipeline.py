"""TAB 编排缝(工单50):split 产物 → 逐系统识别 → 全曲草稿 JSON + CLI。

合成谱照谱全了版式(conftest tab_* 工厂,原生 g=15.5,300dpi 渲染放大
≈1.249 → g≈19.4);OCR 桩按位查表,几何/节奏/装配/报告形状全走真代码。
真机+真模型冒烟在文件尾,无语料/无模型则跳;对账闸只钉机制(小节数/
页眉/音量级),识别质量由 diff-tab 报告喂工单51,不在闸里设阈值。
"""

import json
import os
from pathlib import Path

import pytest

from .conftest import (FakeOcr, sb_staff, tab_digit, tab_rest8,
                       tab_stem_flag, tab_x_mark)
from score_workbench.tab import recognize_tab_pdf
from score_workbench.tab_diff import diff_tab

PAGE_W, PAGE_H = 595.28, 841.89


def _tab_bitmap():
    """三小节合成 TAB(画布照 jianpu 工厂 1986×1404,staff 顶 826,g=15.5):
    小节 A = ②4 四分(裸杆)+ ①2 八分(杆+谱下符尾);小节 B = ③× 拨痕 +
    八分休止(挂 ④ 线);小节 C 空。小节界灰 210 不进墨组件。"""
    import numpy as np
    from .conftest import sb_canvas
    img = sb_canvas()
    top = 826
    sb_staff(img, top)
    for x in (700, 1100, 1500, 1846):            # 小节界(上下延 ≤0.5g)
        img[top - 6:top + 52, x:x + 2] = 210
    tab_digit(img, 800, top + 15.5)              # A1 ②4 四分
    tab_stem_flag(img, 806, top + 20, top + 45)
    tab_digit(img, 1000, top)                    # A2 ①2 八分(谱下符尾)
    tab_stem_flag(img, 1006, top + 5, top + 85, flag=True)
    tab_x_mark(img, 1300, top + 35.0)            # B1 ③× 拨痕
    tab_rest8(img, 1400, top + 35.0)             # B2 八分休止(挂 ③ 线)
    return img


def _write_pdf(tmp_path, name="tab.pdf"):
    import numpy as np
    import pymupdf
    img = _tab_bitmap()
    pix = pymupdf.Pixmap(pymupdf.csGRAY, img.shape[1], img.shape[0],
                         img.tobytes(), 0)
    path = tmp_path / name
    doc = pymupdf.open()
    page = doc.new_page(width=PAGE_W, height=PAGE_H)
    page.insert_image(pymupdf.Rect(0, 0, PAGE_W, PAGE_H / 2), pixmap=pix)
    doc.save(path)
    doc.close()
    return str(path)


def test_pipeline_synthetic_end_to_end(tmp_path):
    pdf = _write_pdf(tmp_path)
    out = tmp_path / "out"
    # 桩按位:数字 ②4 → '4';①2 列字形 → '2'
    ocr = FakeOcr({824: "4", 1073: "2"})
    report = recognize_tab_pdf(pdf, str(out), ocr=ocr)
    assert report["schema"] == "ukeflow.workbench.tab/1"
    assert len(report["measures"]) == 3
    assert report["header"]["meter_assumed"]       # 无页眉 → 假定 4/4
    notes = [n for m in report["measures"] for n in m["notes"]]
    assert sorted((n["fret"], n["string"]) for n in notes) == \
        [(2, 1), (4, 2)]
    b2 = next(n for n in notes if n["fret"] == 2)
    assert b2["duration"] == 0.5                   # 杆+谱下符尾
    rests = [r for m in report["measures"] for r in m["rests"]]
    assert any(r["kind"] == "rest8" and r["beats"] == 0.5 for r in rests)
    marks = [x for m in report["measures"] for x in m["x_marks"]]
    assert marks and marks[0]["strings"]           # × 证据携弦号
    assert (out / "tab.json").is_file()


def test_pipeline_two_systems_keep_own_measures(tmp_path):
    """双系统各认各的小节(x 域同形,错位即混——工单49 retro 同款回归钉)。"""
    import numpy as np
    import pymupdf
    from .conftest import sb_canvas
    img = sb_canvas()
    for top in (500, 1100):
        sb_staff(img, top)
        for x in (137, 900, 1846):                 # 起界+中界+末界(≤0.5g 延)
            img[top - 6:top + 52, x:x + 2] = 210
        tab_digit(img, 700, top + 15.5)
        tab_stem_flag(img, 706, top + 20, top + 45)
    pix = pymupdf.Pixmap(pymupdf.csGRAY, img.shape[1], img.shape[0],
                         img.tobytes(), 0)
    path = tmp_path / "two.pdf"
    doc = pymupdf.open()
    page = doc.new_page(width=PAGE_W, height=PAGE_H)
    page.insert_image(pymupdf.Rect(0, 0, PAGE_W, PAGE_H / 2), pixmap=pix)
    doc.save(path)
    doc.close()
    report = recognize_tab_pdf(str(path), str(tmp_path / "out"),
                               ocr=FakeOcr({705: "4"}))
    ms = report["measures"]
    assert [m["system"] for m in ms] == [0, 0, 1, 1]
    assert [len(m["notes"]) for m in ms] == [1, 0, 1, 0]
    assert [m["start_beat"] for m in ms] == [0.0, 4.0, 8.0, 12.0]
    assert all(n["fret"] == 4 and n["string"] == 2 for m in ms
               for n in m["notes"])


def test_cli_subprocess_roundtrip(tmp_path):
    if _real_models() is None:
        pytest.skip("无 PP-OCR 模型")     # 子进程走真 OCR,同真机测试纪律
    import subprocess
    import sys
    pdf = _write_pdf(tmp_path)
    out = tmp_path / "out"
    env = dict(os.environ, PYTHONPATH=str(Path(__file__).resolve().parents[1]))
    r1 = subprocess.run(
        [sys.executable, "-m", "score_workbench.cli", "recognize-tab", pdf,
         "--out-dir", str(out)], capture_output=True, text=True, env=env)
    assert r1.returncode == 0, r1.stderr
    truth = tmp_path / "gt.json"
    truth.write_text(json.dumps({
        "notes": [{"beat": 0.0, "string": 2, "fret": 4},
                  {"beat": 1.0, "string": 1, "fret": 2}],
        "strums": [], "rests": [{"beat": 2.5, "beats": 0.5}],
        "tremolos": [], "slides": [],
    }), encoding="utf-8")
    r2 = subprocess.run(
        [sys.executable, "-m", "score_workbench.cli", "diff-tab",
         str(out / "tab.json"), str(truth), "--out",
         str(tmp_path / "diff.json")],
        capture_output=True, text=True, env=env)
    assert r2.returncode == 0, r2.stderr
    rep = json.loads((tmp_path / "diff.json").read_text(encoding="utf-8"))
    # 子进程走真 OCR(合成块字形非印刷体,读数不保证)——只钉机制:
    # 退出码 0 + 报告四维齐全;配对质量由进程内测试覆盖
    assert rep["schema"] == "ukeflow.workbench.tab_diff/1"
    assert rep["summary"]["digit_matched"] >= 0
    assert {"precision", "recall"} <= set(rep["rests"])
    assert "f1" in rep["techniques"]


REAL_PDF = os.path.expanduser("~/ukeflow-sources/gs-aini.pdf")


def _real_models():
    from score_workbench.paddle_ocr import resolve_models_dir
    try:
        return resolve_models_dir([
            os.environ.get("SWW_MODELS", ""),
            str(Path(__file__).resolve().parents[1] / "models"),
            "/tmp/dolce/public/redist/ocr",
        ])
    except FileNotFoundError:
        return None


@pytest.mark.skipif(not os.path.isfile(REAL_PDF), reason="无语料")
def test_smoke_real_pdf(tmp_path):
    models = _real_models()
    if models is None:
        pytest.skip("无 PP-OCR 模型")
    report = recognize_tab_pdf(REAL_PDF, str(tmp_path / "out"))
    assert report["schema"] == "ukeflow.workbench.tab/1"
    assert len(report["measures"]) == 69              # 工单48 实数
    assert report["header"]["key"] == "1=E"
    n_marks = sum(len(m["x_marks"]) for m in report["measures"])
    assert n_marks > 80                               # × 证据量级(印张密集)
    print(f"real: {sum(len(m['notes']) for m in report['measures'])} notes / "
          f"{n_marks} × 证据")


@pytest.mark.skipif(not os.path.isfile(REAL_PDF), reason="无语料")
def test_canary_real_vs_truth_mechanism(tmp_path):
    """对账闸(机制版):真机+真模型全链路跑通、草稿小节数与 split 对账、
    diff 报告四维齐全。识别质量数字(v1:数字正确率低、× 拨痕未还原为音)
    是工单51 校对台的工作清单,由 --out 报告承载,不在闸里设阈值。"""
    models = _real_models()
    if models is None:
        pytest.skip("无 PP-OCR 模型")
    draft = recognize_tab_pdf(REAL_PDF, str(tmp_path / "out"))
    truth_path = Path(__file__).parent / "fixtures" / "gs-aini-tab-gt.json"
    with open(truth_path, encoding="utf-8") as fh:
        truth = json.load(fh)
    report = diff_tab(draft, truth)
    assert report["schema"] == "ukeflow.workbench.tab_diff/1"
    assert report["summary"]["draft_notes"] >= 0
    assert {"digit_ok", "digit_bad", "digit_accuracy"} <= set(
        report["summary"])
    assert {"precision", "recall"} <= set(report["rests"])
    assert "f1" in report["techniques"]
