"""分流报告缝:合成 PDF 端到端(体检→版面→判别→报告 JSON)。"""

import json

import pytest

from score_workbench.report import triage_pdf
from .conftest import staff_bitmap_pdf, write_vector_pdf


def test_triage_bitmap_solo_end_to_end(tmp_path):
    rep = triage_pdf(staff_bitmap_pdf(tmp_path))
    assert rep["schema"] == "ukeflow.workbench.triage/1"
    assert rep["checkup"]["image_coverage"] == pytest.approx(1.0, abs=0.01)
    assert rep["layout"]["tab_systems"] >= 1
    c = rep["classification"]
    assert c["score_type"] == "solo"
    assert c["disposition"] == "process"
    assert c["overridden"] is False
    assert len(rep["sha256"]) == 64
    assert rep["checked_at"]


def test_triage_override_recorded(tmp_path):
    rep = triage_pdf(staff_bitmap_pdf(tmp_path), override="strum")
    c = rep["classification"]
    assert c["score_type"] == "strum"
    assert c["auto_type"] == "solo"
    assert c["overridden"] is True


def test_triage_vector_pdf_layout_null(tmp_path):
    rep = triage_pdf(write_vector_pdf(tmp_path, "v.pdf"))
    assert rep["layout"] is None
    assert rep["classification"]["score_type"] == "vector"
    assert rep["classification"]["disposition"] == "report_only"


def test_report_json_serializable(tmp_path):
    rep = triage_pdf(staff_bitmap_pdf(tmp_path))
    s = json.dumps(rep, ensure_ascii=False)
    assert "solo" in s
