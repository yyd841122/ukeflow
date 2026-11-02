"""冻结评测集校验(工单56):哈希自洽 / 版本号 / 台账完整性 / 真值自评满分。

这份测试跑在真冻结文件(evalset/gs-aini-tab-v1.json)上——文件是票面
「评测集冻结(哈希+版本)」验收物本身;手改列数据=哈希闸红,增删裁决行
=台账闸红。
"""

import json
from pathlib import Path

import pytest

from score_workbench.eval_expand import expand_events
from score_workbench.eval_scorer import joint_report
from score_workbench.eval_truth import (ledger_stats, load_evalset,
                                        payload_sha256)

EVALSET = Path(__file__).parent.parent / "evalset" / "gs-aini-tab-v1.json"


@pytest.fixture(scope="module")
def doc():
    if not EVALSET.is_file():
        pytest.fail(f"冻结评测集缺失:{EVALSET}(build-evalset 生成后收口)")
    return load_evalset(str(EVALSET))


def test_version_and_freeze_stamp(doc):
    assert doc["version"] >= 1
    assert doc["frozen_at"]


def test_hash_is_self_consistent(doc):
    assert doc["payload_sha256"] == payload_sha256(doc["payload"])


def test_ledger_completeness(doc):
    """待裁定/排除必须有理由行;排除项公布(困难样本不得全排)。"""
    payload = doc["payload"]
    for col in payload["columns"]:
        if col.get("status") in ("pending", "excluded"):
            assert col.get("reason") or col.get("evidence"), \
                f"{col['beat']} 缺理由行"
    assert not any(c.get("status") == "excluded"
                   for c in payload["columns"]), "v1 不应有排除项"


def test_ledger_categories_published(doc):
    led = ledger_stats(doc)
    assert led["pending_beats"], "待裁定清单必须非空(公布数量)"
    assert led["pending_direction_slots"] > 0, "箭头方向未核槽数必须公布"
    assert led["uncovered"], "未覆盖拍段必须公布"


def test_event_count_anchor(doc):
    """meta.event_count = 展开事件数(冻结一致性锚;改列必被此闸抓住)。"""
    payload = doc["payload"]
    evs, warns = expand_events(payload["columns"], payload["chords"])
    assert not warns
    assert doc["meta"]["event_count"] == len(evs)


def test_truth_self_scores_perfect(doc):
    """真值自评 = 双层 F1 1.0(评分器×真值互相咬合的冒烟闸)。"""
    payload = doc["payload"]
    cand = {"schema": "ukeflow.eval.candidate/1",
            "columns": payload["columns"], "rests": payload["rests"],
            "ties": payload["ties"], "slides": payload["slides"]}
    rep = joint_report(doc, cand)
    assert rep["events"]["f1"] == 1.0
    assert rep["symbols"]["f1"] == 1.0
    assert rep["gate"]["pass"] is True


def test_segments_have_evidence_level(doc):
    for seg in doc["payload"]["segments"]:
        assert seg.get("evidence_level"), f"段 {seg['id']} 缺证据等级"


def test_bar1_is_whole_rest_not_empty(doc):
    """「0」列裁决:第1小节 TAB = 全小节休止(裁片更正),非纯空谱。"""
    payload = doc["payload"]
    rest0 = [r for r in payload["rests"] if r["beat"] == "0"]
    assert rest0 and rest0[0]["beats"] == "4"
    from score_workbench.eval_expand import rat
    assert not [c for c in payload["columns"] if rat(c["beat"]) < 4]


def test_adjudicated_intro_is_crop_level(doc):
    """今日终审的关键修正必须落在冻结集里(逐项钉)。"""
    cols = {c["beat"]: c for c in doc["payload"]["columns"]}
    assert cols["9"]["marks"] == [{"string": 1, "kind": "digit", "fret": 6}]
    assert cols["13"]["marks"] == [{"string": 2, "kind": "digit", "fret": 4}]
    assert cols["17"]["marks"] == [{"string": 1, "kind": "digit", "fret": 9}]
    assert cols["17"]["duration"] == "3"
    assert "10" not in cols and "35/2" not in cols and "18" not in cols
    assert cols["12"]["tech"] == "roll"
    assert cols["14"].get("tech") is None
    assert cols["80"]["tech"] == "strumUp"
    assert cols["84"]["tech"] == "strumUp"
    assert cols["343/4"]["tech"] == "strumDown"   # 拍 85.75 的规范分数串
    assert cols["12"]["marks"], "@12 波浪列保 ×堆+数字"
    ties = {(t["from_beat"], t["to_beat"]) for t in doc["payload"]["ties"]}
    assert ("19/2", "10") in ties and ("17", "35/2") in ties
    assert doc["payload"]["slides"] == []
