"""校对台 web 层(工单51):Flask test client 打全路由,不动网络。

合成 out-dir 走真旋律管线(conftest.build_proof_out_dir);strip 渲染走
真 PDF 重渲染(pymupdf/cv2 都在依赖里)。持久化断言「重开 app 还在」
(proof.json 即会话)。"""

import json

import pytest

from score_workbench.webapp import create_app

from .conftest import build_proof_out_dir

FIXTURES = "tests/fixtures"


@pytest.fixture
def out_dir(tmp_path):
    return build_proof_out_dir(tmp_path)


@pytest.fixture
def client(out_dir):
    return create_app(str(out_dir)).test_client()


def _post(client, path, body):
    resp = client.post(path, json=body)
    return resp.status_code, resp.get_json()


def test_index_serves_page(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert "校对台" in resp.get_data(as_text=True)


def test_session_payload(client):
    resp = client.get("/api/session")
    assert resp.status_code == 200
    s = resp.get_json()
    assert len(s["measures"]) == 4
    assert s["progress"] == {"confirmed": 0, "total": 4}
    assert s["meta"]["id"] == "proof"
    assert s["systems"] and s["systems"][0]["measures"][0]["index"] == 0
    assert s["validation"]                  # 原始草稿有 tempo/闭合错误


def test_strip_png_and_cache(client):
    r1 = client.get("/api/strip/0.png")
    assert r1.status_code == 200
    assert r1.mimetype == "image/png"
    assert r1.data[:8] == b"\x89PNG\r\n\x1a\n"
    assert len(r1.data) > 1000
    r2 = client.get("/api/strip/0.png")
    assert r2.data == r1.data               # 缓存命中同字节


def test_strip_unknown_system_404(client):
    resp = client.get("/api/strip/99.png")
    assert resp.status_code == 404


def test_crop_serving(client, out_dir):
    layout = json.loads((out_dir / "layout.json").read_text())
    crop = layout["score_pages"][0]["systems"][0]["layers"]["jianpu"]["crop"]
    resp = client.get("/" + crop)
    assert resp.status_code == 200
    assert resp.mimetype == "image/png"


def test_meta_persist_and_reload(out_dir):
    app1 = create_app(str(out_dir))
    code, body = _post(app1.test_client(), "/api/meta",
                       {"tempo": "78", "title": "爱你不是两三天"})
    assert code == 200 and body["meta"]["tempo"] == 78.0
    s2 = create_app(str(out_dir)).test_client().get("/api/session").get_json()
    assert s2["meta"]["tempo"] == 78.0
    assert s2["meta"]["title"] == "爱你不是两三天"


def test_confirm_persists(client, out_dir):
    code, body = _post(client, "/api/confirm", {"measure": 0, "value": True})
    assert code == 200 and body["progress"]["confirmed"] == 1
    assert body["measure"]["confirmed"] is True
    s2 = create_app(str(out_dir)).test_client().get("/api/session").get_json()
    assert s2["progress"]["confirmed"] == 1


def test_edit_melody_note_and_reload(out_dir):
    app1 = create_app(str(out_dir))
    code, body = _post(app1.test_client(), "/api/edit",
                       {"kind": "note", "op": "edit", "layer": "melody",
                        "measure": 1, "row": 0, "data": {"duration": "2.0"}})
    assert code == 200
    assert body["measure"]["melody"]["notes"][0]["duration"] == 2.0
    s2 = create_app(str(out_dir)).test_client().get("/api/session").get_json()
    assert s2["measures"][1]["melody"]["notes"][0]["duration"] == 2.0


def test_edit_bad_row_is_400(client):
    code, body = _post(client, "/api/edit",
                       {"kind": "note", "op": "edit", "layer": "melody",
                        "measure": 0, "row": 99, "data": {"duration": 1}})
    assert code == 400 and "越界" in body["error"]


def test_edit_unknown_op_is_400(client):
    code, body = _post(client, "/api/edit",
                       {"kind": "note", "op": "transmogrify", "layer": "melody",
                        "measure": 0, "row": 0})
    assert code == 400


def test_anchor_endpoint(client):
    code, body = _post(client, "/api/anchor", {"layer": "melody"})
    assert code == 200 and body["moved"] == 2      # 欠拍小节让系统1漂 2 小节
    starts = [m["melody"]["start_beat"] for m in body["measures"]]
    assert starts == [0.0, 4.0, 8.0, 12.0]


def test_batch_and_x_expand_endpoints(client):
    code, body = _post(client, "/api/edit",
                       {"kind": "technique", "op": "batch",
                        "data": {"kind": "strumDown", "beat": 0.0,
                                 "from_measure": 0, "to_measure": 3}})
    assert code == 200 and body["written"] == 4
    code, body = _post(client, "/api/edit",
                       {"kind": "x", "op": "expand", "measure": 3, "row": 0,
                        "data": {"label": "E", "frets": [-1, 4, 4, 2],
                                 "baseFret": 1}})
    assert code == 200 and body["created"]["created"] == 1
    assert body["measure"]["tab"]["x_marks"] == []
    assert any(n["beat"] == 13.0 and n["string"] == 3
               for n in body["measure"]["tab"]["notes"])


def _proof_via_api(client):
    """走 API 把合成谱校到 preflight 全绿 + 全确认(端到端主路径)。"""
    _post(client, "/api/meta", {"tempo": "78"})
    _post(client, "/api/anchor", {"layer": "melody"})
    for mi, durs in ((1, ("1.0", "3.0")), (2, ("1.0", "3.0"))):
        for row, d in enumerate(durs):
            _post(client, "/api/edit",
                  {"kind": "note", "op": "edit", "layer": "melody",
                   "measure": mi, "row": row, "data": {"duration": d}})
    _post(client, "/api/confirm-all", {})


def test_export_blocked_then_allowed(client, out_dir):
    code, body = _post(client, "/api/export", {})
    assert code == 409 and body["validation"]
    _proof_via_api(client)
    code, body = _post(client, "/api/export", {})
    assert code == 200 and body["ok"] is True
    ir = body["ir"]
    assert ir["schemaVersion"] == 1
    assert ir["review"]["reviewedAt"]
    assert ir["voices"]["melody"]["notes"][0]["midi"] == 67   # 度5+印张1点
    assert (out_dir / "ir.json").is_file()
    again = json.loads((out_dir / "ir.json").read_text())
    assert again == ir


def test_export_blocked_without_measure_confirms(client, out_dir):
    """票面「全曲确认 → 导出」:preflight 全绿但没逐小节确认照样 409。"""
    _post(client, "/api/meta", {"tempo": "78"})
    _post(client, "/api/anchor", {"layer": "melody"})
    for mi, durs in ((1, ("1.0", "3.0")), (2, ("1.0", "3.0"))):
        for row, d in enumerate(durs):
            _post(client, "/api/edit",
                  {"kind": "note", "op": "edit", "layer": "melody",
                   "measure": mi, "row": row, "data": {"duration": d}})
    code, body = _post(client, "/api/export", {})
    assert code == 409 and "确认" in body["error"]
    assert not (out_dir / "ir.json").exists()
    _post(client, "/api/confirm-all", {})
    code, body = _post(client, "/api/export", {})
    assert code == 200


def test_export_force_bypasses_preflight(client, out_dir):
    code, body = _post(client, "/api/export", {"force": True})
    assert code == 200                              # 人工担责的强行导出
    assert (out_dir / "ir.json").is_file()


def test_diff_melody_and_tab(client):
    code, body = _post(client, "/api/diff",
                       {"kind": "melody", "truth": "tests/fixtures/"
                        "gs-aini-melody-gt.json", "start_measure": 0})
    assert code == 200
    assert body["schema"] == "ukeflow.workbench.melody_diff/1"
    assert "summary" in body
    code, body = _post(client, "/api/diff",
                       {"kind": "tab", "truth": "tests/fixtures/"
                        "gs-aini-tab-gt.json", "start_measure": 0})
    assert code == 200
    assert body["schema"] == "ukeflow.workbench.tab_diff/1"
    assert "digit_accuracy" in body["summary"]


def test_diff_bad_truth_is_400(client):
    code, body = _post(client, "/api/diff",
                       {"kind": "melody", "truth": "no/such.json"})
    assert code == 400 and "真值" in body["error"]


def test_cli_serve_missing_artifacts(capsys, tmp_path):
    from score_workbench.cli import main
    rc = main(["serve", str(tmp_path / "empty")])
    assert rc == 2
    assert "先跑" in capsys.readouterr().err
