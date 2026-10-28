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


# ── recognize / diff-melody(工单49;OCR 用桩,几何装配走真代码)────────

from score_workbench.melody import recognize_melody_pdf  # noqa: E402

from .conftest import FakeOcr, write_jianpu_pdf as _write_pdf  # noqa: E402


def test_recognize_cli_synthetic(capsys, tmp_path):
    pdf = _write_pdf(tmp_path)
    out = tmp_path / "out"
    rc = main(["recognize", pdf, "--out-dir", str(out),
               "--models", str(tmp_path)])  # 无模型 → 报错消息可操作(exit 2)
    assert rc == 2
    assert "PP-OCR" in capsys.readouterr().err


def test_recognize_cli_uses_injected_ocr(tmp_path):
    """CLI 路径的 ocr 注入缝:models_dir 未配时 resolve 报错消息可操作。"""
    from score_workbench.paddle_ocr import resolve_models_dir
    with pytest.raises(FileNotFoundError) as ei:
        resolve_models_dir([str(tmp_path / "none")])
    assert "SWW_MODELS" in str(ei.value)


def test_diff_melody_cli(capsys, tmp_path):
    out = tmp_path / "out"
    recognize_melody_pdf(_write_pdf(tmp_path), str(out), ocr=FakeOcr(
        ["5", "6", "7", "1", "3", "3", "0", "2"]))
    truth = tmp_path / "gt.json"
    truth.write_text(json.dumps({"notes": [
        {"beat": 0.0, "midi": 67}, {"beat": 1.0, "midi": 69},
        {"beat": 2.0, "midi": 71}, {"beat": 3.0, "midi": 72},
        {"beat": 4.0, "midi": 64}, {"beat": 4.5, "midi": 65},
        {"beat": 5.0, "midi": 64}, {"beat": 5.5, "midi": 65},
        {"beat": 6.0, "midi": 64}, {"beat": 6.5, "midi": 67},
    ]}), encoding="utf-8")
    diff_out = tmp_path / "diff.json"
    rc = main(["diff-melody", str(out / "melody.json"), str(truth),
               "--start-measure", "0", "--out", str(diff_out)])
    assert rc == 0
    captured = capsys.readouterr().out
    assert "度数" in captured and "热点" in captured
    rep = json.loads(diff_out.read_text())
    assert rep["schema"] == "ukeflow.workbench.melody_diff/1"
    assert rep["summary"]["degree_ok"] + rep["summary"]["degree_bad"] > 0


def test_diff_melody_cli_missing_truth(capsys, tmp_path, monkeypatch):
    """无 pdf 位的子命令报错时不被 args.pdf AttributeError 遮掩。"""
    draft = tmp_path / "m.json"
    draft.write_text(json.dumps({"measures": []}), encoding="utf-8")
    rc = main(["diff-melody", str(draft), str(tmp_path / "nope.json")])
    assert rc == 2
    assert "nope.json" in capsys.readouterr().err
