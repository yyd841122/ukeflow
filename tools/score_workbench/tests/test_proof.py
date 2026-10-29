"""校对台状态层(工单51):会话装/存、印张→IR 映射、preflight、×还原。

合成 out-dir 走真旋律管线(conftest.build_proof_out_dir,OCR 用桩),
TAB 草稿手写同构;映射约定按金标准核对(G4→②3 等,见 proof.py 模块注)。
"""

import json
from pathlib import Path

import pytest

from score_workbench.melodic_diff import diff_melody
from score_workbench.proof import (OPEN_MIDI, add_chord, add_note, add_rest,
                                   anchor_layer_to_grid, batch_technique,
                                   build_ir, chords_in_measure,
                                   confirm_all, current_melody_draft,
                                   degree_to_midi, delete_note, delete_x_mark,
                                   edit_chord, edit_note, edit_rest,
                                   edit_technique, expand_x_mark, load_session,
                                   measure_count, measure_view, midi_to_tab,
                                   preflight, save_session, set_confirm,
                                   set_meta)

from .conftest import build_proof_out_dir

# 跨语言总闸的漂移侧:fixture 在 App 端(Dart)吃,本文件保证它与
# 现导出逐位相等——陈了报「fixture 过期」而非 Dart 端莫名红
# (check.sh 真值漂移闸同款纪律;工单51 retro)。
GATE_FIXTURE = (Path(__file__).resolve().parents[3] / "test" / "fixtures"
                / "score_ir" / "workbench_export_sample.json")


def build_gate_ir(out_dir) -> dict:
    """把合成谱经校对台全流程校到 preflight 全绿,导出确定性 IR(无
    reviewedAt——时间戳会毁掉漂移闸)。覆盖:双声部音/推导声部休止/显示
    休止/滑音/震音/扫弦/和弦锚。"""
    session = load_session(str(out_dir))
    set_meta(session, {"tempo": 78, "id": "workbench-sample",
                       "title": "工作台导出样张"})
    anchor_layer_to_grid(session, "melody")
    edit_note(session, "melody", 1, 0, {"duration": 1.0})
    edit_note(session, "melody", 1, 1, {"duration": 3.0})
    edit_note(session, "melody", 2, 0, {"duration": 1.0})
    edit_note(session, "melody", 2, 1, {"duration": 3.0})
    add_chord(session, 0, {"beat": 0.0, "label": "C", "frets": [-1, 3, 2, 1]})
    # × 消解走真路径(还原为音):rest@14 在界内,时长收到 1.0
    out = expand_x_mark(session, 3, 0, {"label": "E", "frets": [-1, 4, 4, 2]})
    assert out["created"] == 1
    confirm_all(session)
    assert preflight(session) == []
    ir, skipped = build_ir(session)
    assert skipped == []
    return ir


@pytest.fixture
def out_dir(tmp_path):
    return build_proof_out_dir(tmp_path)


@pytest.fixture
def session(out_dir):
    return load_session(str(out_dir))


def _close_melody_holes(session):
    """合成旋律 m1/m2 只有 2 拍音(工厂每小节数字数不同),先重锚(欠拍
    小节让系统1整体漂了 2 拍)再补足 4 拍闭合。"""
    anchor_layer_to_grid(session, "melody")
    edit_note(session, "melody", 1, 0, {"duration": 1.0})
    edit_note(session, "melody", 1, 1, {"duration": 3.0})
    edit_note(session, "melody", 2, 0, {"duration": 1.0})
    edit_note(session, "melody", 2, 1, {"duration": 3.0})


# ── 会话装/存 ────────────────────────────────────────────────────────

def test_load_session_defaults(session):
    assert measure_count(session) == 4
    assert session["meta"]["id"] == "proof"
    assert session["meta"]["key"] == "1=C"        # 页眉没读出 → C 假定
    assert session["meta"]["tempo"] is None
    assert session["confirmed"] == [False] * 4
    view = measure_view(session, 0)
    assert view["melody"]["notes"][0]["degree"] == 5
    assert view["tab"]["notes"][0]["string"] == 2
    assert view["chords"] == [] and not view["confirmed"]


def test_meta_and_persistence_round_trip(session, out_dir):
    set_meta(session, {"tempo": 78, "key": "1=C", "title": "爱你不是两三天",
                       "melodyAlignBeats": 20.0})
    set_confirm(session, 0, True)
    add_chord(session, 0, {"beat": 0.0, "label": "C",
                           "frets": [-1, 3, 2, 1]})
    save_session(session)
    again = load_session(str(out_dir))
    assert again["meta"]["tempo"] == 78
    assert again["meta"]["melodyAlignBeats"] == 20.0
    assert again["confirmed"] == [True, False, False, False]
    assert chords_in_measure(again, 0)[0]["label"] == "C"


def test_measure_view_errors_exclude_globals(session):
    """全局错误(id/速度)归顶部问题抽屉,不折进每个小节面板。"""
    session["melody"]["measures"][0]["notes"][0]["duration"] = None
    errors = preflight(session)
    assert any(e["measure"] is None for e in errors)        # 全局有条目
    v = measure_view(session, 0, errors)
    assert all(e["measure"] == 1 for e in v["errors"])
    assert any("时值未知" in e["message"] for e in v["errors"])


def test_confirmed_resized_on_reload(session, out_dir):
    set_confirm(session, 3, True)
    save_session(session)
    payload = json.loads((out_dir / "proof.json").read_text())
    payload["confirmed"] = payload["confirmed"][:2]      # 草稿重认过后变短
    (out_dir / "proof.json").write_text(json.dumps(payload))
    again = load_session(str(out_dir))
    assert len(again["confirmed"]) == 4
    assert again["confirmed"][3] is False                # 裁补位归 False


# ── 印张 → midi → 弦品 ───────────────────────────────────────────────

def test_degree_to_midi_print_dot_convention():
    assert degree_to_midi("1=C", 5, 1, 0) == 67          # 5̇ = G4(工单39 实测)
    assert degree_to_midi("1=C", 1, 2, 0) == 72          # ḋ = C5
    assert degree_to_midi("1=C", 3, 0, 0) == 64          # 无点 = 中音域
    assert degree_to_midi("1=C", 5, 0, 1) == 67          # 下一点同中音域
    assert degree_to_midi("1=C", 5, 0, 2) == 55          # 下两点 = G3
    assert degree_to_midi("1=E", 1, 1, 0) == 64          # 1=E → 度1=E4
    with pytest.raises(ValueError):
        degree_to_midi("1=X", 1, 0, 0)


def test_midi_to_tab_matches_builtin_convention():
    assert midi_to_tab(67) == (2, 3)                     # 金标准 G4→②3
    assert midi_to_tab(72) == (1, 3)                     # C5→①3
    assert midi_to_tab(69) == (1, 0)
    assert midi_to_tab(64) == (2, 0)
    assert midi_to_tab(60) == (3, 0)
    assert midi_to_tab(55) is None                       # 低于四弦域


# ── 编辑操作 ─────────────────────────────────────────────────────────

def test_edit_note_reorders_by_beat(session):
    edit_note(session, "melody", 0, 0, {"beat": 3.5, "duration": 0.5})
    beats = [n["beat"] for n in session["melody"]["measures"][0]["notes"]]
    assert beats == [1.0, 2.0, 3.0, 3.5]
    with pytest.raises(ValueError):
        edit_note(session, "melody", 0, 9, {"duration": 1.0})


def test_add_and_delete_note_keeps_sort(session):
    add_note(session, "tab", 0, {"string": 4, "fret": 2, "beat": 0.5,
                                 "duration": 0.5})
    assert [n["beat"] for n in session["tab"]["measures"][0]["notes"]] == \
        [0.0, 0.5, 1.0, 2.0, 3.0]
    added = session["tab"]["measures"][0]["notes"][1]
    assert added["manual"] is True and added["evidence"] is None
    delete_note(session, "tab", 0, 1)
    assert len(session["tab"]["measures"][0]["notes"]) == 4


def test_edit_rest_kind_whitelisted(session):
    edit_rest(session, "tab", 3, 0, {"beats": 2.0, "kind": "rest_whole"})
    rest = session["tab"]["measures"][3]["rests"][0]
    assert rest["beats"] == 2.0 and rest["kind"] == "rest_whole"
    with pytest.raises(ValueError):
        edit_rest(session, "tab", 3, 0, {"kind": "rest16"})


def test_edit_technique_slide_to_beat(session):
    edit_technique(session, 1, 0, {"kind": "strumUp", "to_beat": None})
    tech = session["tab"]["measures"][1]["techniques"][0]
    assert tech["kind"] == "strumUp" and tech["to_beat"] is None
    with pytest.raises(ValueError):
        edit_technique(session, 1, 0, {"kind": "hammer-on"})


def test_batch_technique_writes_every_measure(session):
    n = batch_technique(session, {"kind": "strumDown", "beat": 0.0,
                                  "from_measure": 0, "to_measure": 3})
    assert n == 4
    for mi, m in enumerate(session["tab"]["measures"]):
        hit = [t for t in m["techniques"] if t.get("batch")]
        assert hit and hit[0]["beat"] == m["start_beat"]


# ── × 还原(GLOSSARY:查和弦指形,归校对台)──────────────────────────

def test_expand_x_mark_creates_notes_anchor_and_drops_mark(session):
    out = expand_x_mark(session, 3, 0, {"label": "E", "frets": [-1, 4, 4, 2],
                                        "fingers": [0, 2, 1, 0],
                                        "baseFret": 1})
    assert out["created"] == 1                    # ×弦号证据 [3] 只还原 ③ 弦
    m = session["tab"]["measures"][3]
    new = next(n for n in m["notes"] if n["beat"] == 13.0)
    assert (new["string"], new["fret"]) == (3, 4)
    assert new["duration"] == 1.0                 # 界含休止@14(评审#366):
                                                  # 时长收在下一事件,不叠上休止
    assert new["manual"].startswith("×还原")
    anchor = chords_in_measure(session, 3)[0]
    assert (anchor["label"], anchor["beat"]) == ("E", 1.0)
    assert anchor["fingering"]["frets"] == [-1, 4, 4, 2]
    assert m["x_marks"] == []                     # × 已消解
    with pytest.raises(ValueError):
        expand_x_mark(session, 3, 0, {"label": "", "frets": [0, 0, 0, 0]})


def test_expand_x_mark_without_strings_unrolls_all_sounding(session):
    session["tab"]["measures"][3]["x_marks"][0]["strings"] = None
    out = expand_x_mark(session, 3, 0, {"label": "E", "frets": [-1, 4, 4, 2]})
    assert out["created"] == 3                    # ③②① 三根发声弦


def test_delete_x_mark(session):
    delete_x_mark(session, 3, 0)
    assert session["tab"]["measures"][3]["x_marks"] == []


def test_anchor_layer_to_grid_rebases_drifted_measures(session):
    # 欠拍小节(m1 只 2 拍)让系统1(m2/m3)整体漂 2/4 拍
    assert (session["melody"]["measures"][2]["start_beat"],
            session["melody"]["measures"][3]["start_beat"]) == (6.0, 8.0)
    moved = anchor_layer_to_grid(session, "melody")
    assert moved == 2
    assert [m["start_beat"] for m in session["melody"]["measures"]] == \
        [0.0, 4.0, 8.0, 12.0]
    # m2 音 6,7 → 8,9;m3 音 8..12 → 12..16(小节内相对位不动)
    assert [n["beat"] for n in session["melody"]["measures"][2]["notes"]] == \
        [8.0, 9.0]
    assert [n["beat"] for n in session["melody"]["measures"][3]["notes"]] == \
        [12.0, 13.0, 14.0, 15.0]
    assert anchor_layer_to_grid(session, "melody") == 0     # 幂等
    assert anchor_layer_to_grid(session, "tab") == 0        # TAB 已网格锚定


# ── preflight(Dart 校验器镜像预演)────────────────────────────────

def test_preflight_raw_session_reports_holes_and_missing_meta(session):
    errors = preflight(session)
    fields = {e["field"] for e in errors}
    assert "tempo" in fields                      # 页眉没读出
    holes = [e for e in errors if e["field"] == "melody" and "末尾缺" in e["message"]]
    assert holes and {e["measure"] for e in holes} == {2, 3}   # m1/m2 只 2 拍
    assert not [e for e in errors if e["field"] == "tab"]      # 伴奏空洞自动补记


def test_preflight_gates_drifted_measure_starts(session):
    """评审51 定的闸:逐小节窗各自闭合抓不到跨小节重叠(m1/m2 补足时值后
    全绿但全局 [4,8)×[6,10) 重叠),Dart 端按均匀网格核对必炸——起点偏离
    网格在 preflight 就拦,逼先重锚。"""
    set_meta(session, {"tempo": 78})
    _close_melody_holes(session)
    # _close_melody_holes 先重锚过 → 干净;手动把 m2 拨漂再验闸
    session["melody"]["measures"][2]["start_beat"] = 6.0
    for n in session["melody"]["measures"][2]["notes"]:
        n["beat"] -= 2.0
    gates = [e for e in preflight(session) if e["field"] == "anchor"]
    assert gates and gates[0]["measure"] == 3 and "重锚" in gates[0]["message"]
    anchor_layer_to_grid(session, "melody")
    assert not [e for e in preflight(session) if e["field"] == "anchor"]


def test_preflight_catches_bad_rows(session):
    session["melody"]["measures"][0]["notes"][0]["degree"] = None
    session["tab"]["measures"][0]["notes"][1]["string"] = None
    session["tab"]["measures"][0]["notes"][2]["duration"] = None
    session["tab"]["measures"][0]["notes"][3]["fret"] = 20
    session["melody"]["measures"][1]["notes"][0]["dots_above"] = 1
    session["melody"]["measures"][1]["notes"][0]["dots_below"] = 1
    errors = preflight(session)
    text = " | ".join(e["message"] for e in errors)
    assert "度数未知" in text and "弦号未知" in text and "时值未知" in text
    assert "品位 20 越界" in text and "上下同时带八度点" in text


def test_preflight_catches_same_string_same_beat(session):
    session["tab"]["measures"][0]["notes"][1]["beat"] = 0.0
    session["tab"]["measures"][0]["notes"][1]["string"] = 2
    errors = [e for e in preflight(session) if "同弦同刻" in e["message"]]
    assert errors and errors[0]["measure"] == 1


def test_preflight_catches_measure_count_mismatch(session):
    session["tab"]["measures"].pop()
    assert any(e["field"] == "measures" for e in preflight(session))


def test_preflight_catches_slide_off_notes(session):
    session["tab"]["measures"][1]["techniques"][0]["to_beat"] = 5.5
    assert any("滑音止拍" in e["message"] for e in preflight(session))


def test_preflight_clean_after_proofing(session):
    set_meta(session, {"tempo": 78})
    _close_melody_holes(session)
    delete_x_mark(session, 3, 0)                  # × 未消解是阻塞项(评审#470)
    assert preflight(session) == []


def test_preflight_blocks_unresolved_x_marks(session):
    set_meta(session, {"tempo": 78})
    _close_melody_holes(session)
    errs = [e for e in preflight(session) if e["field"] == "x_marks"]
    assert errs and errs[0]["measure"] == 4 and "还原" in errs[0]["message"]


def test_preflight_gates_chord_stack_same_beat(session):
    """同拍堆(和弦)是一槽:多音同拍同长不算重叠(Dart addSlot 语义,
    评审#847 实锤的误报)。红验证:修前同断言报「事件重叠」。"""
    set_meta(session, {"tempo": 78})
    _close_melody_holes(session)
    delete_x_mark(session, 3, 0)
    add_note(session, "tab", 0, {"string": 1, "fret": 0, "beat": 0.0,
                                 "duration": 1.0})
    add_note(session, "tab", 0, {"string": 3, "fret": 0, "beat": 0.0,
                                 "duration": 1.0})
    assert not [e for e in preflight(session)
                if "重叠" in e["message"] and e["measure"] == 1]


def test_preflight_blocks_beatless_technique_and_open_slide(session):
    set_meta(session, {"tempo": 78})
    _close_melody_holes(session)
    delete_x_mark(session, 3, 0)
    session["tab"]["measures"][2]["techniques"][0]["beat"] = None
    session["tab"]["measures"][1]["techniques"][0]["to_beat"] = None
    errs = preflight(session)
    assert any("缺拍位" in e["message"] for e in errs)
    assert any("滑音缺止拍" in e["message"] for e in errs)


def test_edit_note_beat_cannot_be_null(session):
    """拍位是事件主键,编辑置空当场拒(评审#752:置空后排序/格式化炸)。"""
    with pytest.raises(ValueError, match="拍位不能为空"):
        edit_note(session, "melody", 0, 0, {"beat": None})
    # 半程失败不落半改(评审#202):degree 合法 + beat 非法 → 全不落
    with pytest.raises(ValueError):
        edit_note(session, "melody", 0, 0, {"degree": 3, "beat": ""})
    assert session["melody"]["measures"][0]["notes"][0]["degree"] == 5


def test_edit_chord_label_only_keeps_fingering(session):
    add_chord(session, 0, {"beat": 0.0, "label": "C", "frets": [-1, 3, 2, 1],
                           "fingers": [0, 3, 2, 1], "baseFret": 1})
    chords = session["chords"]
    edit_chord(session, 0, {"label": "C7"})     # label-only 编辑(评审#388)
    fg = chords[0]["fingering"]
    assert chords[0]["label"] == "C7"
    assert fg["frets"] == [-1, 3, 2, 1] and fg["fingers"] == [0, 3, 2, 1]


def test_load_session_discards_proof_from_other_source(session, out_dir):
    """指纹闸(评审#77):proof.json 绑源 sha,同目录换谱不叠陈旧编辑。"""
    import json as _json
    set_meta(session, {"tempo": 99})
    save_session(session)
    payload = _json.loads((out_dir / "proof.json").read_text())
    payload["source_sha256"] = "deadbeef"
    (out_dir / "proof.json").write_text(_json.dumps(payload))
    again = load_session(str(out_dir))
    assert again["meta"]["tempo"] != 99          # 陈旧包被弃


# ── ScoreIR 导出(工单 42 schema)───────────────────────────────────

def _proofed_session(session):
    set_meta(session, {"tempo": 78, "title": "爱你不是两三天"})
    _close_melody_holes(session)
    delete_x_mark(session, 3, 0)
    return session


def test_build_ir_schema_and_event_tables(session):
    _proofed_session(session)
    add_chord(session, 1, {"beat": 0.0, "label": "Em", "frets": [-1, 4, 4, 2]})
    ir, skipped = build_ir(session, reviewed_at="2026-10-28T12:00:00+08:00")
    assert skipped == []
    assert ir["schemaVersion"] == 1
    assert ir["meter"] == {"beatsPerMeasure": 4, "beatUnit": 4}
    assert ir["tempoMap"] == [{"beat": 0.0, "bpm": 78}]
    assert ir["keyMap"] == [{"beat": 0.0, "key": "1=C"}]
    assert [m["number"] for m in ir["measures"]] == [1, 2, 3, 4]
    assert ir["measures"][2]["startBeat"] == 8.0
    assert ir["review"] == {"reviewedAt": "2026-10-28T12:00:00+08:00"}
    # 旋律:度5+印张1点 → ②3 midi 67,证据 bbox+页码
    n0 = ir["voices"]["melody"]["notes"][0]
    assert (n0["beat"], n0["durationBeats"]) == (0.0, 1.0)
    assert (n0["string"], n0["fret"], n0["midi"]) == (2, 3, 67)
    assert n0["evidence"]["bbox"] and n0["evidence"]["page"] == 0
    # 伴奏:midi=空弦+品;卷弦/扫弦/滑音/震音分表;和弦锚主轴拍
    a0 = ir["voices"]["accompaniment"]["notes"][0]
    assert (a0["string"], a0["fret"], a0["midi"]) == (2, 4, 68)  # ②4=E4+4
    assert [s["kind"] for s in ir["strums"]] == ["strumDown"]
    assert ir["tremolos"][0]["beat"] == 8.0
    assert ir["slides"][0] == {"fromBeat": 4.0, "toBeat": 6.0, "evidence": None}
    assert ir["chordAnchors"][0]["beat"] == 4.0   # m1 起点 + 小节内 0
    assert ir["chordAnchors"][0]["fingering"]["frets"] == [-1, 4, 4, 2]
    # 印张 TAB 休止 → 顶层显示休止;简谱 0 → 旋律声部休止
    assert ir["rests"] == [{"beat": 14.0, "beats": 1.0, "evidence": None}]


def test_build_ir_derives_accompaniment_gap_rests(session):
    _proofed_session(session)
    ir, skipped = build_ir(session)
    rests = ir["voices"]["accompaniment"]["rests"]
    # m2 整小节静默 → 全小节休止;m3 只一音 @12,后方空洞 [13,16) 补记
    assert rests == [{"beat": 8.0, "beats": 4.0}, {"beat": 13.0, "beats": 3.0}]
    # 旋律声部休止照录印张 0 号(合成草稿无),空洞在 preflight 已清
    assert ir["voices"]["melody"]["rests"] == []


def test_build_ir_skips_unmappable_without_silent_loss(session):
    _proofed_session(session)
    session["melody"]["measures"][0]["notes"][0]["degree"] = None
    session["tab"]["measures"][1]["techniques"][0]["to_beat"] = None
    ir, skipped = build_ir(session)
    assert {s["what"] for s in skipped} == {"旋律音", "滑音"}


def test_build_ir_lists_unresolved_x_marks(session):
    set_meta(session, {"tempo": 78, "title": "爱你不是两三天"})
    _close_melody_holes(session)                # × 故意留着
    ir, skipped = build_ir(session)
    assert any(s["what"] == "×拨痕" and "未消解" in s["why"] for s in skipped)
    assert any(e["field"] == "x_marks" for e in preflight(session))


def test_build_ir_melody_lyric_carried(session):
    _proofed_session(session)
    session["melody"]["measures"][0]["notes"][0]["lyric"] = "你"
    ir, _ = build_ir(session)
    assert ir["voices"]["melody"]["notes"][0]["lyric"] == "你"


def test_current_draft_views_sorted_for_diff(session):
    edit_note(session, "melody", 0, 0, {"beat": 3.5, "duration": 0.5})
    add_note(session, "melody", 0, {"degree": 5, "beat": 0.25,
                                    "duration": 0.25})
    draft = current_melody_draft(session)
    assert [n["beat"] for n in draft["measures"][0]["notes"]] == \
        [0.25, 1.0, 2.0, 3.0, 3.5]
    truth = json.load(open("tests/fixtures/gs-aini-melody-gt.json"))
    report = diff_melody(draft, truth, start_measure=0, chunk_beats=4.0)
    assert report["schema"] == "ukeflow.workbench.melody_diff/1"
    assert "summary" in report


def test_export_fixture_matches_dart_gate(tmp_path):
    """漂移闸:fixture ← 现导出。Dart 侧闸在 test/core/import/
    workbench_export_gate_test.dart 吃同一份文件。"""
    ir = build_gate_ir(build_proof_out_dir(tmp_path, "gate.pdf"))
    assert GATE_FIXTURE.is_file(), "fixture 丢了,重跑生成本文件的 gen 脚本"
    fx = json.loads(GATE_FIXTURE.read_text())
    assert ir == fx, "工作台导出形状漂移:重生成 test/fixtures/score_ir/workbench_export_sample.json 并看 Dart 侧闸是否仍绿"


def test_open_midi_matches_uke_string_table():
    assert OPEN_MIDI == {1: 69, 2: 64, 3: 60, 4: 67}   # UkeString 高音 G
