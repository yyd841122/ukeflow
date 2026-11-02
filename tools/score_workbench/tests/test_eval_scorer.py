"""联合事件 F1 评分器缝(工单56):三件套联合判定 / 容差闭开与半间隔上界 /
一对一配对 / 空间漂移另报 / 节奏错单列。

容差纪律:τ = min(1/32 拍, 真值最短相邻起音间隔之半);有理数精确比。
"""

from fractions import Fraction as F

from score_workbench.eval_expand import Event
from score_workbench.eval_scorer import _match, score_layer, tolerance


def ev(string, fret, onset, dur):
    return ((string, fret), F(onset), F(dur))


def beats(*vals):
    return [Event(1, 0, F(v), F(1)) for v in vals]


def test_tolerance_capped_by_1_32_and_half_min_gap():
    # 最短相邻起音间隔 1/4 → 半间隔 1/8 > 1/32,τ 取上限 1/32
    assert tolerance(beats("0", "1/4", "1/2")) == F(1, 32)


def test_tolerance_shrinks_below_half_min_gap():
    # 间隔 1/16 的密拍段:τ = min(1/32, 1/32);两枚 1/16 邻音不可能被
    # 同一候选同时配中(一对一)
    assert tolerance(beats("0", "1/16", "1/8")) == F(1, 32)


def test_joint_verdict_requires_all_three_components():
    truth = [ev(1, 2, "4", "1/2"), ev(2, 0, "5", "1")]
    # 同弦品同拍位但时值错 → 非 TP,计 fp+fn 且入 rhythm_miss
    cand = [ev(1, 2, "4", "1"), ev(2, 0, "5", "1")]
    rep = score_layer(truth, cand, F(1, 32))
    assert rep["tp"] == 1 and rep["fp"] == 1 and rep["fn"] == 1
    assert rep["rhythm_miss"]["count"] == 1
    assert rep["f1"] == 0.5


def test_onset_within_tol_is_tp_beyond_is_not():
    truth = [ev(1, 2, "1", "1")]
    assert score_layer(truth, [ev(1, 2, "1", "1")], F(1, 32))["tp"] == 1
    # 恰在 τ 上(=1/32)算中(闭);超半格(1/16)不算
    assert score_layer(truth, [ev(1, 2, "33/32", "1")], F(1, 32))["tp"] == 1
    assert score_layer(truth, [ev(1, 2, "17/16", "1")], F(1, 32))["tp"] == 0


def test_string_or_fret_mismatch_never_pairs():
    truth = [ev(1, 2, "4", "1")]
    assert score_layer(truth, [ev(2, 2, "4", "1")], F(1, 32))["tp"] == 0
    assert score_layer(truth, [ev(1, 3, "4", "1")], F(1, 32))["tp"] == 0


def test_one_to_one_pairing():
    truth = [ev(1, 2, "4", "1")]
    cand = [ev(1, 2, "4", "1"), ev(1, 2, "4", "1")]
    rep = score_layer(truth, cand, F(1, 32))
    assert rep["tp"] == 1 and rep["fp"] == 1 and rep["fn"] == 0


def test_match_pairs_nearest_within_bucket():
    truth = [ev(1, 2, "4", "1"), ev(1, 2, "5", "1")]
    cand = [ev(1, 2, "5", "1"), ev(1, 2, "4", "1")]
    pairs = _match(truth, cand, F(1, 32))
    assert sorted(pairs) == [(0, 1), (1, 0)]


def test_both_empty_is_perfect():
    assert score_layer([], [], F(1, 32))["f1"] == 1.0
    rep = score_layer([], [ev(1, 2, "0", "1")], F(1, 32))
    assert rep["f1"] == 0.0 and rep["fp"] == 1


def test_rational_exact_beats_float_drift():
    # 直化网格 vs 印张三连音:13.25 与 13⅓ 差 1/12 > τ=1/32,必须判错;
    # 精确有理数 40/3 才配中(本曲 b4 直化段的实案)
    truth = [ev(2, 4, "40/3", "1/3")]
    assert score_layer(truth, [ev(2, 4, "13.25", "0.25")], F(1, 32))["tp"] == 0
    assert score_layer(truth, [ev(2, 4, "40/3", "1/3")], F(1, 32))["tp"] == 1
    # 时值同理:1/3 对 0.25 判错
    rep = score_layer([ev(1, 2, "13", "1/3")], [ev(1, 2, "13", "0.25")],
                      F(1, 32))
    assert rep["tp"] == 0 and rep["rhythm_miss"]["count"] == 1
