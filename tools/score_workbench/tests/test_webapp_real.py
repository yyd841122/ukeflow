"""校对台真数据冒烟(工单51 retro):gs-aini 全链路 → serve → 对照 → 导出。

合成 fixtures 盖不住的真几何/真 OCR 形态(69 小节/18 系统、真条带渲染、
对照面板复现 49/50 量级、force 导出装配)由此闸看护。无语料/无模型即跳
(test_smoke_real_pdf 同款纪律);阈值松(0.90/非零配对),只防机制回归,
识别质量本身是 diff 报告的展示物不是本闸的失败项。"""

import json
import os
from pathlib import Path

import pytest

from score_workbench.tab import recognize_tab_pdf
from score_workbench.webapp import create_app

REAL_PDF = os.path.expanduser("~/ukeflow-sources/gs-aini.pdf")
FIXTURES = Path(__file__).resolve().parent / "fixtures"


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


@pytest.fixture(scope="module")
def real_client():
    """真语料 + 真模型的整产物 out-dir(旋律+TAB 一次跑齐,module 级共享)。"""
    models = _real_models()
    if models is None or not os.path.isfile(REAL_PDF):
        pytest.skip("无语料或无 PP-OCR 模型")
    from score_workbench.melody import recognize_melody_pdf
    out = Path(__import__("tempfile").mkdtemp()) / "out"
    recognize_melody_pdf(REAL_PDF, str(out))
    recognize_tab_pdf(REAL_PDF, str(out))
    return create_app(str(out)).test_client()


def test_session_shapes_and_strips(real_client):
    s = real_client.get("/api/session").get_json()
    assert len(s["measures"]) == 69              # 工单48 实数
    assert len(s["systems"]) == 18
    assert s["meta"]["key"] and s["meta"]["tempo"]   # 页眉三件读出
    r = real_client.get("/api/strip/0.png")
    assert r.status_code == 200 and r.data[:8] == b"\x89PNG\r\n\x1a\n"
    assert real_client.get("/api/strip/17.png").status_code == 200


def test_diff_panel_reproduces_acceptance_numbers(real_client):
    rep = real_client.post("/api/diff", json={
        "kind": "melody",
        "truth": str(FIXTURES / "gs-aini-melody-gt.json"),
        "start_measure": 5,
    }).get_json()
    sm = rep["summary"]
    pairs = sm["degree_ok"] + sm["degree_bad"]
    assert pairs > 100 and sm["degree_ok"] / pairs >= 0.90   # 49 实测 95.2%
    rep = real_client.post("/api/diff", json={
        "kind": "tab",
        "truth": str(FIXTURES / "gs-aini-tab-gt.json"),
        "start_measure": 0,
    }).get_json()
    assert rep["summary"]["digit_matched"] >= 1            # 配对机制活着
    assert rep["techniques"]["tp"] + rep["techniques"]["fp"] >= 1


def test_force_export_assembles_full_ir(real_client):
    """识别墙未校时导出靠 force;装配链路(双声部+事件表)须完整。"""
    r = real_client.post("/api/export", json={"force": True})
    assert r.status_code == 200
    ir = r.get_json()["ir"]
    assert ir["schemaVersion"] == 1
    assert len(ir["voices"]["melody"]["notes"]) == 382     # 工单49 全曲实数
    assert len(ir["voices"]["accompaniment"]["notes"]) >= 1
    assert ir["review"]["reviewedAt"]
    assert json.dumps(ir, ensure_ascii=False)              # 可整体序列化
