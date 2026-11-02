"""统一展开规则缝(工单56):× 指形展开 / 数字直读 / tech 整和弦 /
muted 不落音 / x 与扫弦同列不重复。

规则对真值与候选同一函数(语义分层,ADR-0010 决策 2),这里只测缝本身。
"""

from fractions import Fraction as F

from score_workbench.eval_expand import expand_events, rat

E = [4, 4, 4, 2]        # E
A = [2, 1, 0, 0]        # A
D7 = [-1, 2, -1, 3]     # D7(②④闷音)
CHORDS = [{"beat": "0", "label": "E", "frets": E},
          {"beat": "8", "label": "A", "frets": A},
          {"beat": "16", "label": "D7", "frets": D7}]


def col(beat, marks=(), tech=None, duration="1", **kw):
    c = {"beat": beat, "duration": duration, "marks": list(marks)}
    if tech:
        c["tech"] = tech
    c.update(kw)
    return c


def sf(evs):
    return sorted((e.string, e.fret) for e in evs)


def test_x_expands_via_chord_fingering_digit_reads_own_fret():
    cols = [col("0", [{"string": 4, "kind": "x"},
                      {"string": 1, "kind": "digit", "fret": 7}])]
    evs, warns = expand_events(cols, CHORDS)
    assert not warns
    assert sf(evs) == [(1, 7), (4, 4)]


def test_x_follows_chord_change_not_literal_fret():
    # 同一个 × 记号,A 和弦下展开为 ②1(E 和弦下是 ②4)
    evs, _ = expand_events([col("8", [{"string": 2, "kind": "x"}])], CHORDS)
    assert sf(evs) == [(2, 0)]


def test_strum_tech_expands_whole_chord_skipping_muted_strings():
    evs, _ = expand_events([col("16", tech="strumDown"),
                            col("8.5", tech="roll", duration="1/2")], CHORDS)
    assert sf(e for e in evs if e.onset == F(16)) == [(1, 3), (3, 2)]
    assert sf(e for e in evs if e.onset == F(17, 2)) == \
        [(1, 0), (2, 0), (3, 1), (4, 2)]


def test_digit_marks_survive_alongside_strum_tech():
    # 卷弦列可带旋律数字(印张 @12 = 波浪+×堆+数字2);数字直读不查和弦
    cols = [col("8", [{"string": 1, "kind": "digit", "fret": 2}],
                tech="roll")]
    evs, _ = expand_events(cols, CHORDS)
    assert sf(evs) == [(1, 0), (1, 2), (2, 0), (3, 1), (4, 2)]


def test_x_mark_same_column_as_strum_not_double_counted():
    cols = [col("8", [{"string": 3, "kind": "x"},
                      {"string": 1, "kind": "digit", "fret": 2}],
                tech="strumUp")]
    evs, _ = expand_events(cols, CHORDS)
    assert sf(evs) == [(1, 0), (1, 2), (2, 0), (3, 1), (4, 2)]


def test_muted_and_tie_columns_emit_nothing():
    cols = [col("0", [{"string": 3, "kind": "muted"}]),
            col("1", tie=True)]
    evs, warns = expand_events(cols, CHORDS)
    assert evs == [] and not warns


def test_warnings_x_without_chord_or_on_muted_string():
    evs, warns = expand_events(
        [col("-1", [{"string": 1, "kind": "x"}])], CHORDS)
    assert evs == [] and len(warns) == 1
    evs, warns = expand_events(
        [col("16", [{"string": 2, "kind": "x"}])], CHORDS)
    assert evs == [] and any("闷音弦" in w[1] for w in warns)


def test_rat_accepts_string_int_float_forms():
    assert rat("19/2") == F(19, 2) and rat(4) == F(4) and rat(13.25) == F(53, 4)


def test_tremolo_column_expands_from_x_marks():
    cols = [col("4", [{"string": s, "kind": "x"} for s in (4, 3, 2, 1)],
                tech="tremolo")]
    evs, _ = expand_events(cols, CHORDS)
    assert sf(evs) == [(1, 2), (2, 4), (3, 4), (4, 4)]
