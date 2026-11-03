"""draft_candidate 适配单测(工单59a):49/50 草稿 → 评分器输入。

钉四件事:TAB 聚列+时值持续窗(与真值同规:休止截断/曲尾封顶)/不读的
记号留空记账不伪造/弦号未知照落;旋律 midi 折算(melodic_diff 净点数式)
+ 小节网格锚定(read_beats 漂移不进拍位)。
"""

import json

from fractions import Fraction

from score_workbench.dolce_poc import Attack, composite_beat, melody_score
from score_workbench.draft_candidate import (
    melody_draft_attacks,
    melody_window_scores,
    scope_and_store,
    tab_to_candidate,
)


def _tab_doc(measures):
    return {"header": {}, "measures": measures, "systems": []}


def _bar(index, notes=(), rests=(), x_marks=(), techniques=()):
    return {"index": index, "system": 0, "x0": 0.0, "x1": 0.0,
            "start_beat": 4.0 * index, "read_beats": 4.0, "closure_ok": True,
            "notes": list(notes), "rests": list(rests),
            "x_marks": list(x_marks), "techniques": list(techniques),
            "warnings": []}


def test_tab_groups_same_attack_and_recomputes_sustained_window():
    """同 attack 数字+×+技巧同列;时值=至下一 attack/休止,末列封顶主轴。"""
    doc = _tab_doc([
        _bar(0, notes=[
            {"string": 1, "fret": 3, "beat": 0.0, "duration": 0.5},
            {"string": 3, "fret": 0, "beat": 0.5, "duration": 0.5},
        ], x_marks=[
            {"kind": "x_stack", "strings": [4, 3], "beat": 0.0},
        ], techniques=[{"kind": "roll", "beat": 0.0}]),
        # 主轴外的一小节,制造 cut 与末列封顶
        _bar(30, notes=[
            {"string": 2, "fret": 5, "beat": 120.0, "duration": 4.0},
        ]),
    ])
    cand, notes = tab_to_candidate(doc)
    assert notes["skip"] == {"barline": 0, "slide": 0, "ellipse": 0}
    cols = {c["beat"]: c for c in cand["columns"]}
    assert Fraction(0) in cols and Fraction("1/2") in cols
    c0 = cols[Fraction(0)]
    assert [m["kind"] for m in c0["marks"]] == ["digit", "x", "x"]
    assert c0["tech"] == "roll"
    assert c0["duration"] == Fraction(1, 2)      # 下 attack @0.5 截断
    c5 = cols[Fraction(1, 2)]
    # 主轴内无后继(cut @120 越过主轴),按真值同规封顶 end=108
    assert c5["duration"] == Fraction(215, 2)


def test_tab_rest_cuts_duration_and_whole_rest_kept():
    doc = _tab_doc([
        _bar(0, notes=[
            {"string": 1, "fret": 0, "beat": 0.0, "duration": 2.0},
        ], rests=[
            {"beat": 2.0, "beats": 2.0, "kind": "rest_whole"},
        ]),
    ])
    cand, _ = tab_to_candidate(doc)
    assert cand["rests"] == [{"beat": Fraction(2), "beats": Fraction(2)}]
    cols = {c["beat"]: c for c in cand["columns"]}
    assert cols[Fraction(0)]["duration"] == Fraction(2)   # 显式休止截断


def test_tab_unread_symbols_recorded_not_fabricated():
    """barline/slide/ellipse 计数跳过;ties/slides 留空;弦号未知保占位。"""
    doc = _tab_doc([
        _bar(0, notes=[
            {"string": None, "fret": 7, "beat": 0.0, "duration": 1.0},
        ], x_marks=[
            {"kind": "barline", "strings": [], "beat": None},
            {"kind": "x_mark", "strings": [], "beat": 2.0},
        ], techniques=[
            {"kind": "slide", "beat": 0.0},
            {"kind": "ellipse", "beat": 0.0},
            {"kind": "strumDown", "beat": 2.0},
        ]),
    ])
    cand, notes = tab_to_candidate(doc)
    assert cand["ties"] == [] and cand["slides"] == []
    assert notes["skip"] == {"barline": 1, "slide": 1, "ellipse": 1}
    by_beat = {c["beat"]: c for c in cand["columns"]}
    assert by_beat[Fraction(0)]["marks"] == [
        {"string": None, "kind": "digit", "fret": 7}]
    assert by_beat[Fraction(2)]["marks"] == [{"string": None, "kind": "x"}]
    assert by_beat[Fraction(2)]["tech"] == "strumDown"


def test_tab_tech_conflict_keeps_priority_records_loser():
    """同拍 roll+strumUp+震音:优先级保 roll(具体字形>泛化定向>近邻
    挂靠),败者入 warnings 不静默。"""
    doc = _tab_doc([
        _bar(0, techniques=[
            {"kind": "strumUp", "beat": 0.0},
            {"kind": "roll", "beat": 0.0},
            {"kind": "tremolo", "beat": 0.0},
        ]),
    ])
    cand, notes = tab_to_candidate(doc)
    assert cand["columns"][0]["tech"] == "roll"
    # warnings[0] = 跳过汇总行(恒在),其后是逐条冲突记账
    assert len(cand["warnings"]) == 3
    assert all("tech 冲突" in w for w in cand["warnings"][1:])
    kept = {c["kept"] for c in notes["tech_conflicts"]}
    assert kept == {"roll"} and {c["dropped"] for c in
                                 notes["tech_conflicts"]} == {"strumUp",
                                                              "tremolo"}


def test_tab_scope_and_store_roundtrip(tmp_path):
    """过筛已裁定拍段 + 标段,落盘 rat 串(eval-joint CLI 直吃)。"""
    doc = _tab_doc([
        _bar(0, notes=[
            {"string": 4, "fret": 0, "beat": 0.0, "duration": 1.0},
        ]),
        _bar(9, notes=[          # 拍 36:落在范围外的首个小节
            {"string": 1, "fret": 1, "beat": 36.0, "duration": 1.0},
        ]),
    ])
    cand, _ = tab_to_candidate(doc)
    out = tmp_path / "cand.json"
    merged = scope_and_store(cand, str(out))
    assert [c["beat"] for c in merged["columns"]] == [Fraction(0)]
    assert merged["columns"][0]["segment"] == "b1"
    doc2 = json.load(open(out, encoding="utf-8"))
    assert doc2["schema"] == "ukeflow.eval.candidate/1"
    assert doc2["columns"][0]["beat"] == "0"


def test_melody_grid_anchor_ignores_read_beat_drift():
    """拍位=4×小节序+小节内拍;start_beat 漂移被减掉;midi=度数+净点数。"""
    doc = {"header": {}, "measures": [
        {"index": 5, "system": 1, "start_beat": 18.0, "read_beats": 4.0,
         "notes": [
             # 印张 5'(above=1)= 应用净 0 点 = G4=67;小节内拍 0(18.0 起)
             {"degree": 5, "octave_dots_above": 1, "octave_dots_below": 0,
              "beat": 18.0, "duration": 0.5, "evidence": None},
             # 印张 1''(above=2)= 净 1 点 = C5=72;read 漂移:beat 19.25
             {"degree": 1, "octave_dots_above": 2, "octave_dots_below": 0,
              "beat": 19.25, "duration": 0.5, "evidence": None},
             # 印张 7_(below=1, above=0):净 = 0−0 = 0 → B4=71
             {"degree": 7, "octave_dots_above": 0, "octave_dots_below": 1,
              "beat": 19.5, "duration": 0.5, "evidence": None},
         ], "rests": [], "warnings": [], "closure_ok": True,
         "x0": 0.0, "x1": 0.0},
    ]}
    attacks, n_unknown = melody_draft_attacks(doc)
    assert n_unknown == 0
    bars = [composite_beat(a) for a in attacks]
    assert bars == [Fraction(20), Fraction("85/4"), Fraction("43/2")]
    assert [a.midi for a in attacks] == [67, 72, 71]


def test_melody_unknown_degree_counted_not_dropped_silently():
    doc = {"header": {}, "measures": [
        {"index": 0, "system": 0, "start_beat": 0.0, "read_beats": 4.0,
         "notes": [
             {"degree": None, "octave_dots_above": 0, "octave_dots_below": 0,
              "beat": 0.0, "duration": 1.0, "evidence": None},
         ], "rests": [], "warnings": [], "closure_ok": True,
         "x0": 0.0, "x1": 0.0},
    ]}
    attacks, n_unknown = melody_draft_attacks(doc)
    assert attacks == [] and n_unknown == 1


def test_melody_window_scores_slices_truth_and_candidate():
    """窗按印张小节号:真值 beat+align 落窗,候选按 printed_bar 落窗。"""
    truth = {"melodyAlignBeats": 20.0, "notes": [
        {"beat": 0.0, "midi": 67},          # 印张拍 20 = b6 → verse-a 窗
        {"beat": 60.0, "midi": 72},         # 印张拍 80 = b21 → chorus 窗
    ]}
    attacks = [Attack(midi=67, printed_bar=6, beat_in_bar=Fraction(0),
                      printed_duration=Fraction(1)),
               Attack(midi=72, printed_bar=21, beat_in_bar=Fraction(0),
                      printed_duration=Fraction(1)),
               Attack(midi=99, printed_bar=15, beat_in_bar=Fraction(0),
                      printed_duration=Fraction(1))]   # 窗外(未覆盖段)
    reps = melody_window_scores(attacks, truth, windows=[
        ("verse-a(b6-9)", 6, 9), ("chorus(b21-27)", 21, 27)])
    assert reps["verse-a(b6-9)"]["n_truth"] == 1
    assert reps["verse-a(b6-9)"]["n_cand"] == 1
    assert reps["verse-a(b6-9)"]["tp"] == 1
    assert reps["chorus(b21-27)"]["tp"] == 1
    assert reps["verse-a(b6-9)"]["tau"] == "1/32"


def test_melody_score_baseline_rejects_wrong_pitch_and_drift():
    """错品/拍位漂超 τ 都不配对——基线尺子的判错行为钉一遍。"""
    truth = {"melodyAlignBeats": 20.0,
             "notes": [{"beat": 0.0, "midi": 67}]}
    attacks = [
        Attack(midi=68, printed_bar=6, beat_in_bar=Fraction(0),
               printed_duration=Fraction(1)),                    # 错品
        Attack(midi=67, printed_bar=6, beat_in_bar=Fraction(1, 32),
               printed_duration=Fraction(1)),                    # 恰在 τ 上→错
    ]
    reps = melody_window_scores(attacks, truth, windows=[("w", 6, 9)])
    assert reps["w"]["tp"] == 0 and reps["w"]["fn"] == 1
    assert reps["w"]["fp"] == 2
