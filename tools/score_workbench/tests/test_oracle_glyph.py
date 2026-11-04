"""工单61 m0 oracle 注入缝:对齐 DP / 字形注入 / 骨架映射 / 编排装配。

对齐与注入以纯函数直测(Attack/Sym 构造,无图像);build_oracle_tab 走
monkeypatch 桩(不进 cv2/split);真值自评链(冻结评测集当候选 = 满分)
钉评分链与真值自洽。
"""

import json
from fractions import Fraction

import pytest

from score_workbench.eval_scorer import joint_report
from score_workbench.eval_truth import DEFAULT_PATH, payload_sha256
from score_workbench.oracle_glyph import (GS_AINI_BAR_MAP, POS_TOL,
                                          _repair_spans, align_columns,
                                          inject_bar)
from score_workbench.tab import Attack, Sym

LINE_YS = [100.0, 119.2, 138.4, 157.6]      # ①②③④(g=19.2)
GAP = 19.2


def _atk(cx, duration=None, digits=(), x_marks=(), events=()):
    a = Attack(cx - 6, cx + 6)
    a.duration = duration
    a.digits = list(digits)
    a.x_marks = list(x_marks)
    a.events = list(events)
    return a


def _col(beat, marks=None, duration=None, tech=None):
    c = {"beat": str(beat), "marks": marks or [], "duration": duration}
    if tech:
        c["tech"] = tech
    return c


def _span(index, x0=100.0, x1=200.0, meter=4.0):
    return {"index": index, "x0": x0, "x1": x1, "meter": meter,
            "start_beat": meter * index}


# ── 对齐 DP ───────────────────────────────────────────────────────────

class TestAlignColumns:
    def test_equal_counts_order_match(self):
        cols = [_col(4), _col(5), _col(6)]
        pairs, extra, missed = align_columns(
            [_atk(110), _atk(135), _atk(160)], cols, _span(1), 4.0)
        assert pairs == [(0, 0), (1, 1), (2, 2)]
        assert not extra and not missed

    def test_extra_attack_unmatched(self):
        # 配对数同为 3,平手取 Σ|Δnorm| 最小 → 贴近列的 attack 胜出
        cols = [_col(4), _col(5), _col(6)]
        pairs, extra, missed = align_columns(
            [_atk(110), _atk(122), _atk(135), _atk(160)], cols,
            _span(1), 4.0)
        assert sorted(pairs) == [(0, 0), (1, 1), (3, 2)]
        assert extra == [2] and not missed

    def test_missed_column(self):
        cols = [_col(4), _col(5), _col(6)]
        pairs, extra, missed = align_columns(
            [_atk(110), _atk(160)], cols, _span(1), 4.0)
        assert sorted(pairs) == [(0, 0), (1, 2)]
        assert not extra and missed == [1]

    def test_position_guard_rejects_far_match(self):
        pairs, extra, missed = align_columns(
            [_atk(198)], [_col(4)], _span(1), 4.0)
        assert not pairs and extra == [0] and missed == [0]

    def test_half_beat_column_pairs(self):
        pairs, _, _ = align_columns([_atk(112)], [_col("9/2")],
                                    _span(1), 4.0)
        assert pairs == [(0, 0)]

    def test_monotone_never_crosses(self):
        # 列序 4,6;attack 序 110(近4),160(近6)→ 不许交叉配
        cols = [_col(4), _col(6)]
        pairs, _, _ = align_columns([_atk(110), _atk(160)], cols,
                                    _span(1), 4.0)
        assert pairs == [(0, 0), (1, 1)]


# ── 注入 ──────────────────────────────────────────────────────────────

class TestInjectBar:
    def _run(self, attacks, cols, variant="marks"):
        stats = {"bars": [], "n_pairs": 0, "n_extra": 0, "n_missed": 0,
                 "n_injected": 0, "bad_marks": []}
        rep = inject_bar(attacks, cols, _span(1), GAP, LINE_YS, variant,
                         stats=stats)
        return rep, stats

    def test_marks_replaced_and_events_kept(self):
        a = _atk(110, digits=[Sym("digit", 104, 112.2, 12, 14,
                                 label="9", conf=0.9)],
                 events=[Sym("roll", 110, 100, 9, 60)])
        rep, stats = self._run(
            [a], [_col(4, [{"string": 2, "kind": "digit", "fret": 4},
                           {"string": 4, "kind": "x"}], duration="1")])
        assert rep["n_pairs"] == 1 and stats["n_injected"] == 2
        assert [(d.label, d.conf) for d in a.digits] == [("4", 1.0)]
        assert abs(a.digits[0].cy - LINE_YS[1]) < 1e-9      # ②弦线
        assert [(x.role, round(x.cy, 1)) for x in a.x_marks] == \
            [("x_mark", round(LINE_YS[3], 1))]              # ④弦线
        assert a.events and a.events[0].role == "roll"      # 技巧保留

    def test_extra_attack_stripped_when_no_columns(self):
        # 真值无列(空 cols)= 该域不该有 attack → 音位记号全清
        a = _atk(110, digits=[Sym("digit", 104, 112.2, 12, 14,
                                 label="5", conf=0.9)])
        self._run([a], [])
        assert not a.digits and not a.x_marks

    def test_extra_stripped_when_columns_exist(self):
        extra = _atk(160, digits=[Sym("digit", 154, 112.2, 12, 14,
                                      label="5", conf=0.9)])
        matched = _atk(110)
        self._run([matched, extra],
                  [_col(4, [{"string": 1, "kind": "x"}], duration="1")])
        assert not extra.digits and not extra.x_marks
        assert matched.x_marks and matched.x_marks[0].role == "x_mark"

    def test_duration_variant_injects_truth_duration(self):
        a = _atk(110, duration=None)
        self._run([a], [_col(4, duration="1/2")], variant="marks+durations")
        assert a.duration == 0.5
        a2 = _atk(110, duration=None)
        self._run([a2], [_col(4, duration="1/2")], variant="marks")
        assert a2.duration is None                  # marks 不动时值

    def test_muted_counted_not_injected(self):
        a = _atk(110)
        _, stats = self._run(
            [a], [_col(4, [{"string": 3, "kind": "muted"}], duration="1")])
        assert not a.x_marks and stats["n_injected"] == 0
        assert stats["n_muted_skipped"] == 1

    def test_bad_string_mark_recorded(self):
        a = _atk(110)
        _, stats = self._run(
            [a], [_col(4, [{"string": 9, "kind": "x"}], duration="1")])
        assert stats["bad_marks"] and stats["n_injected"] == 0


# ── 骨架映射 ──────────────────────────────────────────────────────────

class TestRepairSpans:
    @staticmethod
    def _systems(specs):
        return [{"measures": [{"index": i, "x0": 100.0 + i * 400,
                               "x1": 500.0 + i * 400}
                              for i in range(n)]} for n in specs]

    def test_merge_phantom_bar(self):
        systems = self._systems([5])
        out = _repair_spans(systems, 0, {0: [(0, 0), (1, 1), (2, 2),
                                             (3, 3), (4, 3)]})
        # span4 并入 bar3:x 域并合
        assert out[-1][:3] == (3, 100.0 + 3 * 400, 500.0 + 4 * 400)
        assert len(out) == 4

    def test_fallback_uses_global_accumulation(self):
        systems = self._systems([2, 3])
        out = _repair_spans(systems, 1, None)     # 系统1 无映射
        assert [bar for bar, *_ in out] == [2, 3, 4]

    def test_gsayini_map_shape(self):
        systems = self._systems([5, 4, 4, 4, 5, 3, 3])
        for si in range(7):
            out = _repair_spans(systems, si, GS_AINI_BAR_MAP)
            bars = [bar for bar, *_ in out]
            assert bars == sorted(bars)
            assert all(b2 > b1 for b1, b2 in zip(bars, bars[1:]))


# ── 编排装配(monkeypatch 桩,不进 cv2/split)────────────────────────

class TestBuildOracleTab:
    def _fake_run(self):
        from score_workbench.tab import assemble_measures  # noqa: F401
        s = {"index": 0,
             "staff": {"gap": GAP, "line_ys": LINE_YS, "top": 90.0,
                       "bottom": 160.0, "x0": 100.0, "x1": 500.0},
             "layers": {"tab": {"bbox": [100.0, 90.0, 400.0, 90.0],
                                "crop": "x.png"}},
             "measures": [{"index": 0, "x0": 100.0, "x1": 300.0,
                           "left": {"x": 100.0}, "right": {"x": 300.0}},
                          {"index": 1, "x0": 300.0, "x1": 500.0,
                           "left": {"x": 300.0}, "right": {"x": 500.0}}]}
        a0 = _atk(110, duration=1.0)
        a1 = _atk(390, duration=1.0,
                  digits=[Sym("digit", 384, 112.2, 12, 14,
                              label="9", conf=0.9)])
        return {"systems": [s], "attacks": [[a0, a1]], "evidence": [[]],
                "per_system": [{"index": 0}],
                "header": {"key": None, "meter": None, "tempo_bpm": None,
                           "meter_assumed": True, "evidence": None,
                           "warnings": []},
                "meter_beats": 4.0, "layout": {"score_pages": []}}

    def _evalset(self, cols, rests=()):
        payload = {"chords": [], "segments": [], "columns": cols,
                   "rests": list(rests), "ties": [], "slides": []}
        return {"schema": "ukeflow.eval.truth/1", "id": "t", "version": 1,
                "frozen_at": "2026-11-03", "payload": payload,
                "payload_sha256": payload_sha256(payload),
                "meta": {"tempo": 78, "beats_per_bar": 4,
                         "event_count": 0}}

    def test_injection_wiring(self, tmp_path, monkeypatch):
        import score_workbench.oracle_glyph as og

        run = self._fake_run()
        monkeypatch.setattr("score_workbench.tab.recognize_tab_attacks",
                            lambda *a, **k: run)
        pdf = tmp_path / "fake.pdf"
        pdf.write_bytes(b"x")
        cols = [_col(0, duration="1"),
                _col(5, [{"string": 2, "kind": "digit", "fret": 4}],
                     duration="1")]
        doc = og.build_oracle_tab(str(pdf), str(tmp_path),
                                  self._evalset(cols),
                                  bar_map={0: [(0, 0), (1, 1)]})
        assert doc["schema"] == "ukeflow.workbench.tab/1"
        assert doc["oracle"]["variant"] == "marks"
        assert doc["oracle"]["alignment"]["n_pairs"] == 2
        m0, m1 = doc["measures"]
        assert m0["notes"] == []                      # 列0 无记号
        # 列1 的数字被 oracle 换成 ②4(conf=1.0)
        assert [(n["fret"], n["string"], n["confidence"])
                for n in m1["notes"]] == [(4, 2, 1.0)]
        assert (tmp_path / "oracle-tab.json").is_file()

    def test_variant_guard(self, tmp_path):
        import score_workbench.oracle_glyph as og

        pdf = tmp_path / "fake.pdf"
        pdf.write_bytes(b"x")
        with pytest.raises(ValueError):
            og.build_oracle_tab(str(pdf), str(tmp_path),
                                self._evalset([]), variant="bogus")


# ── 真值自评链(冻结评测集当候选 = 满分,钉链路自洽)──────────────────

def test_truth_self_score_perfect():
    from score_workbench.eval_truth import load_evalset

    doc = load_evalset(str(_pkg_root() / DEFAULT_PATH))
    payload = doc["payload"]
    cols = [dict(c) for c in payload["columns"]
            if c.get("status") == "adjudicated"]
    cand = {"schema": "ukeflow.eval.candidate/1",
            "columns": cols,
            "rests": [{"beat": r["beat"], "beats": r["beats"]}
                      for r in payload["rests"]],
            "ties": [{"from_beat": t["from_beat"], "to_beat": t["to_beat"]}
                     for t in payload["ties"]],
            "slides": [], "warnings": []}
    rep = joint_report(doc, cand)
    assert rep["events"]["f1"] == 1.0
    assert rep["symbols"]["f1"] == 1.0


def _pkg_root():
    from pathlib import Path

    return Path(__file__).parent.parent
