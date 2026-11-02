"""评测集构建缝(工单56):底稿×修正→冻结集的推导纪律。

修正词汇、闷音/虚按推导、时值区间规则(显式休止截断/连音列不拦/曲尾封顶)、
段过滤、tech_x_marks 保 × 列。
"""

from fractions import Fraction as F

from score_workbench.eval_build import build_evalset
from score_workbench.eval_expand import expand_events
from score_workbench.eval_truth import payload_sha256, validate_evalset

GT = {
    "tempo": 78,
    "notes": [
        {"beat": 4.0, "string": 4, "fret": 4},
        {"beat": 4.0, "string": 3, "fret": 4},
        {"beat": 4.0, "string": 2, "fret": 4},
        {"beat": 4.0, "string": 1, "fret": 2},     # E 堆
        {"beat": 4.5, "string": 3, "fret": 4},     # 补音 ×
        {"beat": 6.0, "string": 4, "fret": 2},     # A 堆
        {"beat": 6.0, "string": 3, "fret": 1},
        {"beat": 6.0, "string": 2, "fret": 0},
        {"beat": 6.0, "string": 1, "fret": 0},
        {"beat": 8.0, "string": 4, "fret": 4},     # B 堆④②①
        {"beat": 8.0, "string": 2, "fret": 4},
        {"beat": 8.0, "string": 1, "fret": 2},
        {"beat": 8.5, "string": 3, "fret": 4},     # 补音
        {"beat": 9.0, "string": 2, "fret": 4},     # 轻拍②①
        {"beat": 9.0, "string": 1, "fret": 2},
        {"beat": 9.5, "string": 3, "fret": 4},     # 补音
    ],
    "strums": [
        {"beat": 4.0, "kind": "roll"},
        {"beat": 6.0, "kind": "roll"},
        {"beat": 50.0, "kind": "strumUp"},         # 段外(36-80 未覆盖),过滤
    ],
    "rests": [{"beat": 5.0, "beats": 0.5}],        # 显式休止截断 @4.5 时值
    "tremolos": [],
    "slides": [],
}

CHORDS = {
    "id": "x", "title": "测试曲", "key": "1=E",
    "chords": [
        {"beat": 4.0, "label": "E", "frets": [4, 4, 4, 2]},
        {"beat": 6.0, "label": "A", "frets": [2, 1, 0, 0]},
        {"beat": 8.0, "label": "B", "frets": [4, 3, 2, 2]},
    ],
}

CORR = {
    "date": "2026-11-02",
    "note_columns": {"9.5": [{"string": 1, "kind": "digit", "fret": 6}]},
    "main_axis_beats": 10,
    "ties_add": [{"from_beat": "19/2", "to_beat": "10",
                  "evidence": "测试延音线"}],
    "tech_x_marks": ["4"],
}


def by_beat(doc):
    return {c["beat"]: c for c in doc["payload"]["columns"]}


def test_marks_derive_from_chord_context_with_corrections():
    doc = build_evalset(GT, CHORDS, CORR, 1, "2026-11-02")
    cols = by_beat(doc)
    # E 堆 = 全 ×(品位=指形);修正列 9.5 的 ①6 → digit 6
    assert all(m["kind"] == "x" for m in cols["4"]["marks"])
    assert cols["19/2"]["marks"] == \
        [{"string": 1, "kind": "digit", "fret": 6}]


def test_muted_rules_chord_minus1_and_finger_bar():
    GT_D7 = dict(GT, notes=[
        {"beat": 16.0, "string": 3, "fret": 2},
        {"beat": 16.0, "string": 1, "fret": 3},     # D7 闷音柱
    ])
    CH = dict(CHORDS, chords=CHORDS["chords"] +
              [{"beat": 16.0, "label": "D7", "frets": [-1, 2, -1, 3]}])
    doc = build_evalset(GT_D7, CH, CORR, 1, "2026-11-02")
    assert {m["string"] for m in by_beat(doc)["16"]["muted"]} == {2, 4}


def test_duration_interval_rule_with_rest_and_end_cap():
    doc = build_evalset(GT, CHORDS, CORR, 1, "2026-11-02")
    cols = by_beat(doc)
    assert cols["4"]["duration"] == "1/2"        # 至 4.5
    assert cols["9/2"]["duration"] == "1/2"      # 4.5 被休止@5 截断
    assert cols["6"]["duration"] == "2"          # 6→8(无中间 attack)
    last = doc["payload"]["columns"][-1]
    assert last["beat"] == "19/2" and last["duration"] == "1/2"  # 曲尾封顶 10


def test_tie_column_and_out_of_segment_filtered():
    doc = build_evalset(GT, CHORDS, dict(CORR, tie_columns=[
        {"beat": "102", "status": "pending", "reason": "未核验"}]),
        1, "2026-11-02")
    beats = {c["beat"] for c in doc["payload"]["columns"]}
    assert "50" not in beats                     # 段外 strum 过滤
    tie = [c for c in doc["payload"]["columns"] if c.get("tie")]
    assert tie and tie[0]["status"] == "pending"


def test_tech_x_marks_keep_marks_at_roll_columns():
    doc = build_evalset(GT, CHORDS, CORR, 1, "2026-11-02")
    cols = by_beat(doc)
    assert cols["4"]["marks"], "tech_x_marks 列保 × 列"
    assert cols["6"]["marks"] == []
    # × 与 tech 同列:事件不重复(4 弦堆=4 事件)
    evs, _ = expand_events([cols["4"]], doc["payload"]["chords"])
    assert len(evs) == 4


def test_frozen_doc_validates_and_hash_covers_payload():
    doc = build_evalset(GT, CHORDS, CORR, 3, "2026-11-02")
    validate_evalset(doc)                        # 不抛即过
    assert doc["version"] == 3
    assert doc["payload_sha256"] == payload_sha256(doc["payload"])


def test_tamper_breaks_hash():
    import copy
    doc = build_evalset(GT, CHORDS, CORR, 1, "2026-11-02")
    bad = copy.deepcopy(doc)
    bad["payload"]["columns"][0]["beat"] = "999"
    try:
        validate_evalset(bad)
        assert False, "手改 payload 必须被哈希闸拦下"
    except ValueError as exc:
        assert "payload_sha256" in str(exc)
