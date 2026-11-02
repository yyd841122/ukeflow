"""工单57 vlm_poc 单测(全离线,transport 注入,零网络零 key)。"""

import calendar
import json
import os

import pytest

from score_workbench import vlm_poc as vp
from score_workbench.vlm_poc import (assemble, build_payload, call_cost_usd,
                                     call_model, extract_json, is_peak,
                                     normalize, run_image, scope_filter,
                                     to_jsonable)


# ── extract_json ────────────────────────────────────────────

def test_extract_json_plain():
    assert extract_json('{"a":1}') == {"a": 1}


def test_extract_json_fenced_and_prose():
    text = '好的,以下是结果:\n```json\n{"a": [1,2]}\n```\n以上。'
    assert extract_json(text) == {"a": [1, 2]}


def test_extract_json_missing_raises():
    with pytest.raises(ValueError, match="没有 JSON"):
        extract_json("完全没有对象")


def test_extract_json_broken_raises():
    with pytest.raises(ValueError, match="解析失败"):
        extract_json('{"a": 1,,}')


# ── normalize ───────────────────────────────────────────────

def _mk_doc(**over):
    doc = {
        "columns": [
            {"beat": 4.0, "duration": 0.5,
             "marks": [{"string": 1, "kind": "digit", "fret": 2},
                       {"string": "2", "kind": "x"}]},
            {"beat": 4.5, "duration": 0.5, "tech": "up"},          # 别名收拢
            {"beat": 6.0, "duration": 0.5,
             "marks": [{"string": 3}], "muted": [{"string": 4}]},  # 缺品位→unknown
            {"beat": 6.5, "duration": 0.5,
             "marks": [{"string": 9, "kind": "x"}]},               # 弦号非法→丢
        ],
        "rests": [{"beat": 7.0, "beats": 0.5}],
        "ties": [{"from_beat": 9.5, "to_beat": 9.0}],             # 颠倒→丢
        "slides": [],
    }
    doc.update(over)
    return doc


def test_normalize_marks_tech_and_warnings():
    cand = normalize(_mk_doc())
    col4 = cand["columns"][0]
    assert col4["marks"][0] == {"string": 1, "kind": "digit", "fret": 2}
    assert col4["marks"][1] == {"string": 2, "kind": "x"}   # 字符串数字居容
    assert cand["columns"][1]["tech"] == "strumUp"
    col6 = cand["columns"][2]
    assert col6["marks"][0]["kind"] == "unknown"
    assert cand["columns"][3]["marks"] == []
    assert any("弦号非法" in w for w in cand["warnings"])
    assert any("muted" in w for w in cand["warnings"])


def test_normalize_duration_sustain_window():
    """持续窗 = 至下一 attack/休止,封顶 main_axis;连音列不拦。"""
    cand = normalize(_mk_doc())
    by_beat = {c["beat"]: c for c in cand["columns"]}
    assert by_beat[4.0]["duration"] == 0.5          # 4 → 4.5
    assert by_beat[4.5]["duration"] == 1.5          # 4.5 → 6(下一 attack)
    assert by_beat[6.0]["duration"] == 0.5          # 6 → 6.5(下一 attack)
    assert by_beat[6.5]["duration"] == 0.5          # 6.5 → 7(休止截断)
    assert all(c["printed_duration"] == 0.5 for c in cand["columns"])


def test_normalize_duration_tie_chain_cap():
    """⑨@17 延音链 17→20(连音列除外只算 attack);曲尾封顶 main_axis。"""
    doc = {"columns": [
        {"beat": 17.0, "duration": 0.5, "marks": [{"string": 1, "kind": "digit", "fret": 9}]},
        {"beat": 17.5, "duration": 0.25, "marks": [{"string": 1, "kind": "x"}], "tie": True},
        {"beat": 17.75, "duration": 0.25, "marks": [{"string": 1, "kind": "x"}], "tie": True},
        {"beat": 20.0, "duration": 0.5, "marks": [{"string": 2, "kind": "digit", "fret": 4}]},
        {"beat": 107.75, "duration": 0.25, "marks": [{"string": 3, "kind": "x"}]},
    ], "rests": [], "ties": [], "slides": []}
    cand = normalize(doc)
    by_beat = {c["beat"]: c for c in cand["columns"]}
    assert by_beat[17.0]["duration"] == 3           # 17 → 20(tie 列不算 attack)
    assert by_beat[17.5]["duration"] == 2.5
    assert by_beat[20.0]["duration"] == 87.75       # 到 107.75(下一 attack)
    assert by_beat[107.75]["duration"] == 0.25      # 封顶 108


def test_normalize_ties_and_slides_kept_when_forward():
    doc = _mk_doc(ties=[{"from_beat": 9.5, "to_beat": 10.0},
                        {"from_beat": 17.0, "to_beat": 17.5}],
                  slides=[{"from_beat": 5.0, "to_beat": 5.5}])
    cand = normalize(doc)
    assert len(cand["ties"]) == 2
    assert cand["slides"] == [{"from_beat": 5.0, "to_beat": 5.5}]


# ── scope_filter ────────────────────────────────────────────

def test_scope_filter_ranges_and_segments():
    doc = _mk_doc(columns=[
        {"beat": 0.5, "duration": 1, "marks": []},
        {"beat": 10, "duration": 1, "marks": []},      # <36 在范围内
        {"beat": 35.5, "duration": 0.5, "marks": []},
        {"beat": 50, "duration": 1, "marks": []},      # uncovered→弃
        {"beat": 80, "duration": 1, "tech": "strumUp"},
        {"beat": 108, "duration": 1, "marks": []},     # ≥108→弃
        {"beat": 107.75, "duration": 0.25, "marks": []},
    ], rests=[{"beat": 0.0, "beats": 4.0}, {"beat": 40, "beats": 4.0}],
        ties=[{"from_beat": 9.5, "to_beat": 10.0},
              {"from_beat": 60, "to_beat": 61}], slides=[])
    out = scope_filter(normalize(doc))
    beats = [float(c["beat"]) for c in out["columns"]]
    assert beats == [0.5, 10.0, 35.5, 80.0, 107.75]
    segs = {float(c["beat"]): c["segment"] for c in out["columns"]}
    assert segs[0.5] == "b1" and segs[35.5] == "verse-a"
    assert segs[80.0] == "chorus"
    assert [r["beat"] for r in out["rests"]] == [0.0]
    assert [t["from_beat"] for t in out["ties"]] == [9.5]


# ── 持久化往返 ───────────────────────────────────────────────

def test_to_jsonable_roundtrip_via_eval_rat():
    cand = normalize(_mk_doc())
    j = json.loads(json.dumps(to_jsonable(cand)))
    col = j["columns"][0]
    assert col["beat"] == "4" and col["duration"] == "1/2"
    # eval_expand.rat 能原样吃回
    from score_workbench.eval_expand import rat
    assert rat(col["duration"]) == cand["columns"][0]["duration"]


# ── 调用与成本 ───────────────────────────────────────────────

def test_is_peak_official_windows():
    off = lambda y, mo, d, h: calendar.timegm((y, mo, d, h, 0, 0))
    assert is_peak(off(2026, 11, 1, 2)) is False   # 周日
    assert is_peak(off(2026, 11, 3, 2)) is True    # 周二 01-04 UTC
    assert is_peak(off(2026, 11, 3, 5)) is False
    assert is_peak(off(2026, 11, 3, 7)) is True    # 06-10 UTC
    assert is_peak(off(2026, 11, 3, 12)) is False


def test_call_cost_usd_flash_prices():
    assert call_cost_usd(None, False) is None
    u = {"prompt_tokens": 1000, "completion_tokens": 1000}
    assert call_cost_usd(u, False) == pytest.approx((1000 * 0.15 + 1000 * 0.60) / 1e6)
    u_hit = {"prompt_tokens": 1000, "completion_tokens": 1000,
             "prompt_cache_hit_tokens": 800}
    assert call_cost_usd(u_hit, True) == pytest.approx(
        (200 * 0.30 + 800 * 0.006 + 1000 * 1.20) / 1e6)


def test_build_payload_frozen_shape(tmp_path):
    from PIL import Image as PILImage
    img = tmp_path / "t.png"
    PILImage.new("RGB", (4, 4), "white").save(img)
    pl = build_payload(str(img), prompt="读谱输出 json", model="m1")
    assert pl["model"] == "m1"
    assert pl["temperature"] == 0
    assert pl["max_tokens"] == vp.MAX_TOKENS
    assert pl["thinking"] == {"type": "enabled"}
    assert pl["reasoning_effort"] == "low"
    assert pl["response_format"] == {"type": "json_object"}
    content = pl["messages"][0]["content"]
    assert content[0]["type"] == "image_url"
    assert content[0]["image_url"]["url"].startswith("data:image/png;base64,")
    assert content[1]["text"] == "读谱输出 json"


def test_prompt_frozen_anchors():
    """提示词定版锚(改提示词必须升 PROMPT_VERSION,防批量期漂移)。"""
    assert vp.PROMPT_VERSION == "57-v1"
    for anchor in ("ukeflow.eval.candidate/1",
                   "第 n 小节起始拍 = (n−1)×4",
                   "①=顶线",
                   '"unknown"',
                   "strumUp",
                   "rests[].beats"):
        assert anchor in vp.PROMPT, anchor


def test_call_model_json_object_fallback():
    import io
    import urllib.error
    calls = []

    def transport(pl):
        calls.append(pl)
        if "response_format" in pl:
            body = io.BytesIO(
                json.dumps({"error": {"message":
                                      "response_format unsupported"}})
                .encode())
            raise urllib.error.HTTPError(vp.API_URL, 400, "bad", None, body)
        return {"ok": True}

    resp = call_model({"x": 1, "response_format": {"type": "json_object"}},
                      transport=transport)
    assert resp == {"ok": True}
    assert len(calls) == 2 and "response_format" not in calls[1]


def test_call_model_http_error_surfaces():
    import io
    import urllib.error

    def transport(pl):
        raise urllib.error.HTTPError(
            vp.API_URL, 401, "unauthorized", None,
            io.BytesIO(b'{"error":{"message":"bad key"}}'))
    with pytest.raises(RuntimeError, match="401"):
        call_model({"x": 1}, transport=transport)


# ── run_image 端到端(tmp 目录,fake transport)───────────────

RESP = {
    "created": calendar.timegm((2026, 11, 2, 12, 0, 0)),   # 周日=谷
    "model": vp.MODEL_DEFAULT,
    "choices": [{"finish_reason": "stop",
                 "message": {"content": json.dumps(_mk_doc())}}],
    "usage": {"prompt_tokens": 2000, "completion_tokens": 1500},
}


def test_run_image_e2e(tmp_path, monkeypatch):
    monkeypatch.delenv("DEEPSEEK_API_KEY", raising=False)  # 证明注入路不用 key
    img = tmp_path / "in.png"
    from PIL import Image as PILImage
    PILImage.new("RGB", (8, 8), "white").save(img)
    out_dir = tmp_path / "runs"

    cand = run_image(str(img), "page0", str(out_dir), transport=lambda pl: RESP)

    assert (out_dir / "raw" / "page0.resp.json").exists()
    cand_file = out_dir / "cand" / "page0.cand.json"
    assert cand_file.exists()
    on_disk = json.loads(cand_file.read_text(encoding="utf-8"))
    assert on_disk["schema"] == "ukeflow.eval.candidate/1"
    rows = [json.loads(l) for l in
            (out_dir / "ledger.jsonl").read_text().splitlines()]
    assert len(rows) == 1
    row = rows[0]
    assert row["unit"] == "page0" and row["usage"]["prompt_tokens"] == 2000
    assert row["peak_hours"] is False
    # 谷价:(2000×0.15 + 1500×0.60)/1e6 × 7.1,落盘按 4 位小数
    assert row["cost_cny"] == round(
        (2000 * 0.15 + 1500 * 0.60) / 1e6 * vp.CNY_PER_USD, 4)
    assert cand["meta"]["image_sha256"]
    assert cand["meta"]["finish_reason"] == "stop"


def test_run_image_bad_json_keeps_raw(tmp_path, monkeypatch):
    monkeypatch.delenv("DEEPSEEK_API_KEY", raising=False)
    img = tmp_path / "in.png"
    from PIL import Image as PILImage
    PILImage.new("RGB", (8, 8), "white").save(img)
    resp = {"created": 0, "choices": [{"finish_reason": "length",
                                       "message": {"content": "截断"}}],
            "usage": {"prompt_tokens": 1, "completion_tokens": 1}}
    with pytest.raises(ValueError):
        run_image(str(img), "u", str(tmp_path / "r"), transport=lambda pl: resp)
    assert (tmp_path / "r" / "raw" / "u.resp.json").exists()
    rows = [json.loads(l) for l in
            (tmp_path / "r" / "ledger.jsonl").read_text().splitlines()]
    assert len(rows) == 1 and rows[0]["ok"] is False      # 失败也记账
    assert rows[0]["finish_reason"] == "length"


def test_assemble_scopes_and_tags_units(tmp_path):
    runs = tmp_path / "runs" / "cand"
    runs.mkdir(parents=True)
    doc_a = normalize(_mk_doc(columns=[
        {"beat": 4.0, "duration": 0.5,
         "marks": [{"string": 1, "kind": "digit", "fret": 2}]},
        {"beat": 50, "duration": 1, "marks": []},          # 过筛弃
    ]))
    doc_b = normalize(_mk_doc(columns=[
        {"beat": 80.0, "duration": 1.0, "marks": [], "tech": "strumUp"},
    ]))
    for name, doc in (("a", doc_a), ("b", doc_b)):
        (runs / f"{name}.cand.json").write_text(
            json.dumps(to_jsonable(doc), ensure_ascii=False), encoding="utf-8")
    out = tmp_path / "cand-merged.json"
    assemble(str(tmp_path / "runs"), ["a", "b"], str(out))
    merged = json.loads(out.read_text(encoding="utf-8"))
    beats = [c["beat"] for c in merged["columns"]]
    assert beats == ["4", "80"]                       # 50 被过筛;拍序排列
    units = [c["unit"] for c in merged["columns"]]
    assert units == ["a", "b"]
    segs = {c["beat"]: c["segment"] for c in merged["columns"]}
    assert segs["4"] == "intro" and segs["80"] == "chorus"


# ── 制备(原生拼装/裁块用真 PDF,慢路只跑一次)───────────────

PDF = os.path.expanduser("~/ukeflow-sources/gs-aini.pdf")
LAYOUT = os.path.expanduser("~/ukeflow-sources/vlm-poc-57/layout/layout.json")
HAS_INPUTS = os.path.exists(PDF) and os.path.exists(LAYOUT)


@pytest.mark.skipif(not HAS_INPUTS, reason="缺 gs-aini PDF 或 layout 产物")
def test_prepare_pages_and_crops(tmp_path):
    import math

    with open(LAYOUT, encoding="utf-8") as fh:
        layout = json.load(fh)
    pages = vlm_poc_pages = vp.prepare_pages(PDF, layout, [0], str(tmp_path))
    assert len(pages) == 1
    from PIL import Image as PILImage
    with PILImage.open(pages[0]) as im:
        assert im.size == (1986, 1404)
    crops = vp.prepare_crops(str(tmp_path), layout, ["page0:0"], str(tmp_path))
    assert len(crops) == 1
    with PILImage.open(crops[0]) as im:
        assert im.width == 1986 and 300 < im.height < 600
    # 换算常量与官方页几何自洽
    assert math.isclose(vp.SCALE_RENDER_TO_NATIVE, 1986 / 2480.3336, rel_tol=1e-9)
