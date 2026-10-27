"""小节装配缝(工单49):时值符号 → 拍位累加 + 小节归属 + 闭合对账。

时值规则(简谱读法):基拍=四分;n 层时值线=÷2ⁿ;附点 ×1.5;延音杠各 +1 拍。
拍位=小节内依音序累加;x 只定小节归属(工单41 教训:不做 px→拍标定)。
小节读出长度 ≠ 拍号 → 闭合警告(拍位继续按读出累加,漂移可见不遮掩)。
"""

from score_workbench.melody import assemble_measures


def note(x, label, underlines=0, aug=False, dashes=0, conf=1.0):
    return {"x": x, "label": label, "underlines": underlines,
            "aug": aug, "dashes": dashes, "confidence": conf}


def measures4(width=400.0, n=3):
    return [{"index": i, "x0": i * width, "x1": (i + 1) * width}
            for i in range(n)]


def test_quarters_fill_measure_and_accumulate():
    notes = [note(100 + i * 90, str(i % 7 + 1)) for i in range(12)]
    out = assemble_measures(notes, measures4(), 4)
    assert len(out.measures) == 3
    m0 = out.measures[0]
    assert [n["beat"] for n in m0["notes"]] == [0.0, 1.0, 2.0, 3.0]
    assert m0["read_beats"] == 4.0 and m0["closure_ok"]
    assert out.measures[1]["notes"][0]["beat"] == 4.0


def test_dotted_eighth_and_sixteenth_pair():
    # 附点八(0.75)+十六(0.25)+四分(1)+四分+延音杠(2) = 4 拍(sys01 b6 型)
    notes = [
        note(60, "5", underlines=1, aug=True),
        note(130, "5", underlines=2),
        note(200, "1"),
        note(270, "6", dashes=1),
    ]
    out = assemble_measures(notes, measures4(), 4)
    beats = [n["beat"] for n in out.measures[0]["notes"]]
    durs = [n["duration"] for n in out.measures[0]["notes"]]
    assert beats == [0.0, 0.75, 1.0, 2.0]
    assert durs == [0.75, 0.25, 1.0, 2.0]
    assert out.measures[0]["read_beats"] == 4.0


def test_rest_takes_slot_and_lands_in_rests():
    notes = [note(60, "3", underlines=1), note(130, "0", underlines=1),
             note(200, "3", underlines=2), note(260, "2", underlines=2)]
    out = assemble_measures(notes, measures4(), 4)
    m = out.measures[0]
    assert [n["beat"] for n in m["notes"]] == [0.0, 1.0, 1.25]
    assert m["rests"] == [{"beat": 0.5, "beats": 0.5, "x": 130.0,
                           "evidence": None}]


def test_closure_mismatch_warns_and_drift_stays_visible():
    notes = [note(60, "1"), note(130, "2"), note(200, "3")]     # 少 1 拍
    out = assemble_measures(notes, measures4(), 4)
    m0 = out.measures[0]
    assert not m0["closure_ok"]
    assert any("闭合" in w for w in m0["warnings"])
    assert out.measures[1]["start_beat"] == 3.0     # 漂移不遮掩


def test_unknown_label_keeps_slot_with_warning():
    notes = [note(60, "9"), note(130, "5")]
    out = assemble_measures(notes, measures4(), 4)
    m = out.measures[0]
    assert m["notes"][0]["degree"] is None
    assert any("9" in w or "未知" in w for w in m["warnings"])
