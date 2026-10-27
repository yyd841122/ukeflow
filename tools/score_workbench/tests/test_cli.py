"""CLI 缝:triage/checkup 子命令,报告 JSON 可机读。"""

import json

import pytest

from score_workbench.cli import main

from .conftest import staff_bitmap_pdf, write_vector_pdf


def test_triage_stdout_json(capsys, tmp_path):
    rc = main(["triage", staff_bitmap_pdf(tmp_path)])
    assert rc == 0
    rep = json.loads(capsys.readouterr().out)
    assert rep["classification"]["score_type"] == "solo"


def test_triage_out_file_and_summary(capsys, tmp_path):
    out = tmp_path / "rep.json"
    rc = main(["triage", staff_bitmap_pdf(tmp_path), "--out", str(out)])
    assert rc == 0
    captured = capsys.readouterr().out
    assert "solo" in captured
    rep = json.loads(out.read_text())
    assert rep["classification"]["disposition"] == "process"


def test_triage_type_override_flag(capsys, tmp_path):
    rc = main(["triage", staff_bitmap_pdf(tmp_path), "--type", "strum"])
    assert rc == 0
    rep = json.loads(capsys.readouterr().out)
    assert rep["classification"]["score_type"] == "strum"
    assert rep["classification"]["auto_type"] == "solo"


def test_triage_rejects_bad_type(capsys, tmp_path):
    with pytest.raises(SystemExit):
        main(["triage", staff_bitmap_pdf(tmp_path), "--type", "guitar"])


def test_checkup_summary_and_json(capsys, tmp_path):
    path = write_vector_pdf(tmp_path, "v.pdf")
    rc = main(["checkup", str(path)])
    assert rc == 0
    assert "矢量" in capsys.readouterr().out
    rc = main(["checkup", str(path), "--json"])
    sig = json.loads(capsys.readouterr().out)
    assert sig["pages"] == 1
    assert sig["text_chars"] > 0


def test_missing_file_errors(capsys, tmp_path):
    rc = main(["triage", str(tmp_path / "nope.pdf")])
    assert rc == 2
    assert "打不开" in capsys.readouterr().err
