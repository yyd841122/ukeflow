"""TAB 装配与真值 diff 单测(工单50):拍位累加、小节网格锚定、四维 diff。

装配纪律:小节起点锚在「bar 数 × 拍号」网格(barline 是真值,read_beats
被 None 时值毒化时漂移只许留在小节内);× 不落音落证据。diff 四维 =
数字正确率(拍位 ±TOL + 同弦优先配对)/ 时值(同弦连续对)/ 休止 P-R /
技巧 F1。
"""

from score_workbench.tab import Attack, Sym, assemble_measures, read_duration
from score_workbench.tab_diff import diff_tab

LYS = [21.0, 40.5, 59.5, 78.5]
SPANS = [{"index": 0, "x0": 0.0, "x1": 400.0},
         {"index": 1, "x0": 400.0, "x1": 800.0}]


def _digit(x, fret, conf=0.9):
    return Sym("digit", float(x), 20.0, 11.0, 15.0, str(fret), conf)


def _stem(x):
    return Sym("stem", float(x), 45.0, 3.0, 30.0)


def test_assembly_grid_anchor_and_closure():
    """小节起点 = bar×拍号;第一小节 read_beats 亏格不拖垮第二小节起点。"""
    a1 = Attack(50.0, 66.0)
    a1.digits = [_digit(55, 3)]
    a1.rhythm = [_stem(58)]
    a1.duration = read_duration(a1, 19.2, 4.0)
    a2 = Attack(450.0, 466.0)
    a2.digits = [_digit(455, 5)]
    a2.rhythm = [_stem(458)]
    a2.duration = read_duration(a2, 19.2, 4.0)
    ms, un = assemble_measures([a1, a2], [], SPANS, 4.0, LYS, 19.2)
    assert [m["start_beat"] for m in ms] == [0.0, 4.0]
    assert ms[0]["read_beats"] == 1.0 and not ms[0]["closure_ok"]
    assert ms[1]["notes"][0]["beat"] == 4.0
    assert ms[1]["notes"][0]["string"] == 1 and ms[1]["notes"][0]["fret"] == 5


def test_assembly_x_marks_evidence_not_notes():
    """× 落 x_marks(弦号证据),不进 notes(票面:照读谱法不落音)。"""
    x1 = Sym("x_mark", 60.0, 55.0, 13.0, 19.0)
    a = Attack(55.0, 75.0)
    a.x_marks = [x1]
    a.rhythm = [_stem(65)]
    ms, _ = assemble_measures([a], [], SPANS[:1], 4.0, LYS, 19.2)
    assert ms[0]["notes"] == []
    assert ms[0]["x_marks"][0]["strings"] == [3]
    assert ms[0]["x_marks"][0]["beat"] == 0.0


def test_read_duration_bracket_quarter():
    att = Attack(0.0, 16.0)
    att.bracket = True
    assert read_duration(att, 19.2, 4.0) == 1.0
    assert read_duration(att, 19.2, 3.0) == 1.0


def test_diff_digit_accuracy_and_duration():
    draft = {
        "measures": [
            {"index": 0, "notes": [
                {"string": 1, "fret": 8, "beat": 9.0, "duration": 0.5,
                 "x": 1105.0},
                {"string": 1, "fret": 7, "beat": 9.5, "duration": 0.5,
                 "x": 1158.0},
                {"string": 1, "fret": 4, "beat": 10.0, "duration": 0.5,
                 "x": 1210.0},
            ], "rests": [], "techniques": []},
        ],
    }
    truth = {
        "notes": [
            {"beat": 9.0, "string": 1, "fret": 8},
            {"beat": 9.5, "string": 1, "fret": 7},
            {"beat": 10.0, "string": 1, "fret": 4},
        ],
        "strums": [], "rests": [], "tremolos": [], "slides": [],
    }
    r = diff_tab(draft, truth)
    s = r["summary"]
    assert s["digit_matched"] == 3 and s["digit_ok"] == 3
    assert s["digit_accuracy"] == 1.0
    assert r["duration"]["ok"] == 2 and r["duration"]["compared"] == 2


def test_diff_digit_fret_mismatch_and_tolerance():
    draft = {
        "measures": [
            {"index": 0, "notes": [
                {"string": 1, "fret": 6, "beat": 9.05, "duration": 0.5,
                 "x": 1100.0},
            ], "rests": [], "techniques": []},
        ],
    }
    truth = {
        "notes": [{"beat": 9.0, "string": 1, "fret": 8}],
        "strums": [], "rests": [], "tremolos": [], "slides": [],
    }
    r = diff_tab(draft, truth)
    s = r["summary"]
    assert s["digit_matched"] == 1 and s["digit_ok"] == 0
    assert r["hotspots"][0]["field"] == "fret"
    assert r["hotspots"][0]["draft"] == 6 and r["hotspots"][0]["truth"] == 8


def test_diff_rest_pr_and_whole_rest_separate():
    draft = {
        "measures": [
            {"index": 0, "notes": [], "techniques": [],
             "rests": [
                 {"beat": 7.1, "beats": 0.5, "kind": "rest8", "x": 900.0},
                 {"beat": 2.0, "beats": 4.0, "kind": "rest_whole", "x": 400.0},
             ]},
        ],
    }
    truth = {"notes": [], "strums": [],
             "rests": [{"beat": 7.0, "beats": 0.5}],
             "tremolos": [], "slides": []}
    r = diff_tab(draft, truth)
    rs = r["rests"]
    assert rs["tp"] == 1 and rs["fp"] == 0 and rs["fn"] == 0
    assert rs["precision"] == 1.0 and rs["recall"] == 1.0
    assert rs["whole_bar_not_in_truth"] == 1   # 真值事件模型外,单列


def test_diff_slide_matched_against_truth_slides():
    """滑音对真值 slides 配对(fromBeat),不再是恒 FP。"""
    draft = {
        "measures": [
            {"index": 0, "notes": [],
             "techniques": [{"kind": "slide", "beat": 9.5, "x": 1016.0}],
             "rests": [], "x_marks": []},
        ],
    }
    truth = {"notes": [], "strums": [], "rests": [], "tremolos": [],
             "slides": [{"fromBeat": 9.5, "toBeat": 10.0}]}
    r = diff_tab(draft, truth)
    t = r["techniques"]
    assert t["tp"] == 1 and t["fp"] == 0 and t["fn"] == 0
    assert t["by_kind"]["slide"]["f1"] == 1.0


def test_diff_technique_f1_by_kind():
    draft = {
        "measures": [
            {"index": 0, "notes": [],
             "techniques": [
                 {"kind": "roll", "beat": 4.3, "x": 620.0},
                 {"kind": "strumUp", "beat": 85.0, "x": 100.0},
                 {"kind": "strumUp", "beat": 86.0, "x": 200.0},
             ], "rests": [], "x_marks": []},
        ],
    }
    truth = {
        "notes": [],
        "strums": [
            {"beat": 4.0, "kind": "roll"},
            {"beat": 85.0, "kind": "strumUp"},
            {"beat": 86.5, "kind": "strumDown"},
        ],
        "rests": [], "tremolos": [], "slides": [],
    }
    r = diff_tab(draft, truth)
    t = r["techniques"]
    assert t["tp"] == 2 and t["fp"] == 1 and t["fn"] == 1
    assert t["by_kind"]["roll"]["tp"] == 1
    assert t["by_kind"]["strumUp"]["tp"] == 1
    assert t["by_kind"]["strumDown"]["fn"] == 1


def test_assembly_empty_measure_with_evidence_no_crash():
    """有证据无 attack 的 span(如 slide 落在休止小节)不炸,beat 挂小节起点。"""
    slide = Sym("slide", 450.0, 20.0, 26.0, 7.0)
    ms, _ = assemble_measures([], [slide], SPANS, 4.0, LYS, 19.2)
    assert ms[1]["techniques"][0]["kind"] == "slide"
    assert ms[1]["techniques"][0]["beat"] == 4.0


def test_diff_window_beyond_truth_counted_not_compared():
    """草稿超出真值末拍 +4 的窗口外音只计不比(工单49 同纪律)。"""
    draft = {
        "measures": [
            {"index": 0, "notes": [
                {"string": 1, "fret": 2, "beat": 200.0, "duration": 1.0,
                 "x": 500.0},
            ], "rests": [], "techniques": []},
        ],
    }
    truth = {"notes": [{"beat": 9.0, "string": 1, "fret": 8}],
             "strums": [], "rests": [], "tremolos": [], "slides": []}
    r = diff_tab(draft, truth)
    assert r["summary"]["digit_matched"] == 0
    assert r["summary"]["draft_notes"] == 0     # 窗口外剔除
