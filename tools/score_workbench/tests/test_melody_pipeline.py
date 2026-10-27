"""编排缝(工单49):split 产物 → 逐系统识别 → 全曲草稿 JSON。

合成谱照谱全了版式(conftest 工厂,原生位图几何 g=15.5,300dpi 渲染
放大 ≈1.249 → g≈19.4);OCR 用桩(按 x 序查表),几何/装配/报告形状全
走真代码。真机+真模型冒烟在文件尾,无语料/无模型则跳。
"""

import json
import os
from pathlib import Path

import pytest

from .conftest import INK, sb_block as block, sb_canvas as canvas, sb_staff as staff
from score_workbench.melody import FakeOcr, recognize_melody_pdf

PAGE_W, PAGE_H = 595.28, 841.89


def _staff_bitmap(name="melody.pdf"):
    """一个系统:小节 A 四个四分数字;小节 B 附点八+十六+八分休止+附点四
    分带延音杠(读出 4 拍闭合);小节 C/D 空行。"""
    img = canvas()
    staff(img, 826)
    for x in (138, 583, 981, 1432, 1845):        # 4 小节界(灰 210,不进墨组件)
        img[826:873, x:x + 2] = 210
    for x in (220, 290, 360, 430):               # A:四个四分数字
        block(img, 970, x, 20, 14)
    block(img, 970, 620, 20, 14)                 # B1 附点八分:高音点+主梁+附点
    block(img, 957, 624, 6, 6)
    block(img, 993, 617, 2, 90)                  # 主梁盖 B1/B2 音心
    block(img, 977, 638, 6, 6)                   # 附点(数字右中,距缘 0.26g)
    block(img, 970, 680, 20, 14)                 # B2 十六分:副梁
    block(img, 998, 676, 2, 30)
    block(img, 970, 760, 20, 14)                 # B3 八分休止 0+主梁段
    block(img, 993, 757, 2, 26)
    block(img, 970, 850, 20, 14)                 # B4 附点四分
    block(img, 977, 868, 6, 6)                   # 附点(距缘 0.26g)
    block(img, 978, 878, 2, 16)                  # 延音杠(行中,距缘 0.91g)
    return img


def _write_pdf(tmp_path, name="melody.pdf"):
    import numpy as np
    import pymupdf
    img = _staff_bitmap()
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
    ocr = FakeOcr(["5", "6", "7", "1", "3", "3", "0", "2"])
    report = recognize_melody_pdf(pdf, str(out), ocr=ocr)
    assert report["schema"] == "ukeflow.workbench.melody/1"
    assert len(report["systems"]) == 1
    assert report["header"]["meter_assumed"]          # 无页眉 → 假定 4/4 落警告
    ms = report["measures"]
    assert len(ms) == 4
    m0 = ms[0]
    assert [n["degree"] for n in m0["notes"]] == [5, 6, 7, 1]
    assert [n["beat"] for n in m0["notes"]] == [0.0, 1.0, 2.0, 3.0]
    assert m0["closure_ok"]
    m1 = ms[1]
    assert [n["beat"] for n in m1["notes"]] == [4.0, 4.75, 5.5]
    assert [n["duration"] for n in m1["notes"]] == [0.75, 0.25, 2.5]
    assert m1["rests"] and abs(m1["rests"][0]["beat"] - 5.0) < 1e-9
    assert m1["closure_ok"] and m1["read_beats"] == 4.0
    assert not ms[2]["closure_ok"]                    # 空行闭合警告可见
    # 证据链:逐音 bbox 携带(渲染 px,页坐标)
    n0 = m0["notes"][0]
    assert n0["evidence"]["bbox"] and n0["evidence"]["confidence"] == pytest.approx(1.0)
    assert (out / "melody.json").is_file()


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
    out = tmp_path / "out"
    report = recognize_melody_pdf(REAL_PDF, str(out))
    assert report["schema"] == "ukeflow.workbench.melody/1"
    n_notes = sum(len(m["notes"]) for m in report["measures"])
    n_rests = sum(len(m["rests"]) for m in report["measures"])
    assert len(report["measures"]) == 69              # 工单48 实数
    assert n_notes > 300                              # 全曲音量级(粗闸)
    assert report["header"]["key"] is not None        # 页眉调号读出
    print(f"real: {n_notes} notes / {n_rests} rests, key={report['header']['key']}")


@pytest.mark.skipif(not os.path.isfile(REAL_PDF), reason="无语料")
def test_canary_real_vs_truth(tmp_path):
    """对账闸(工单48 同款纪律):真机+真模型全链路 × builtin 168 音逐位,
    阈值松(0.90)只防识别层回归;逐位差异本身是印张↔人工转录的微观出入,
    是校对台(51)的输入,不是本闸的失败项。"""
    models = _real_models()
    if models is None:
        pytest.skip("无 PP-OCR 模型")
    draft = recognize_melody_pdf(REAL_PDF, str(tmp_path / "out"))
    truth_path = Path(__file__).parent / "fixtures" / "gs-aini-melody-gt.json"
    from score_workbench.melodic_diff import diff_melody
    with open(truth_path, encoding="utf-8") as fh:
        truth = json.load(fh)
    report = diff_melody(draft, truth, start_measure=5)
    s = report["summary"]
    pairs = s["degree_ok"] + s["degree_bad"]
    assert pairs == 167                          # 真值窗口 168 音含尾拍跨块
    assert s["degree_bad"] / pairs < 0.10, f"度数正确率跌破 0.90: {s}"
    assert s["beat_bad"] / (s["beat_ok"] + s["beat_bad"]) < 0.10
    print(f"canary: degree {s['degree_ok']}/{pairs}, "
          f"beat {s['beat_ok']}/{s['beat_ok'] + s['beat_bad']}, "
          f"duration {s['duration_ok']}/{s['duration_compared']}")
