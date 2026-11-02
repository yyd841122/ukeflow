"""dolce_poc 适配单测(工单58③):钉 123 方言语义 + POC 实测样例。

样例取自 docs/research/2026-10-27-dolce-jianpu-poc.md 的整页读出
(sys1 人声段)与失败模式 2(TAB 噪声行);音高映射钉 App 纯旋律版
「印张点数减一 + E→C 平移」约定(工单37 台账)。
"""

from fractions import Fraction

from score_workbench.dolce_poc import (
    Attack,
    collect_attacks,
    composite_beat,
    parse_123,
    suppress_garbage,
)


POC_SYS1 = """X:1
T:爱你不是两三天
K:1=E
M:4/4
Q:1/4=78
|: 5'_. (5'__ 5'_) 1''_ 6'_. (6'__ 6'_) 1''_ | 5'_ 5'_ 6'_ (3'_ 3') 0_ 3'__ 2'__ |
w:你的/信只留/下最后一封/淡淡笔迹/你熟悉的/温柔//请别
"""


def _attacks(text, dot_shift=-1):
    meta, lines = parse_123(text)
    suppress_garbage(lines, meter=Fraction(meta.get("meter", (4, 4))[0]))
    return meta, lines, collect_attacks(lines, dot_shift=dot_shift)


def test_flat_tie_matches_app_truth_convention():
    """照读不并(默认):连线组内 token 各成一击、拍位照排——
    App 真值把延音尾存独立音,(5'__ 5'_) → @0.75(1/4)+@1.0(1/2)。"""
    _, _, attacks = _attacks(POC_SYS1)
    bar1 = [a for a in attacks if a.printed_bar == 1]
    assert [(str(a.beat_in_bar), str(a.printed_duration)) for a in bar1] == [
        ("0", "3/4"), ("3/4", "1/4"), ("1", "1/2"), ("3/2", "1/2"),
        ("2", "3/4"), ("11/4", "1/4"), ("3", "1/2"), ("7/2", "1/2")]
    assert sum(a.printed_duration for a in bar1) == 4


def test_meta_and_music_line_split():
    meta, lines, _ = _attacks(POC_SYS1)
    assert meta["key"] == "1=E"
    assert meta["meter"] == (4, 4)
    assert meta["tempo"] == 78
    assert len(lines) == 1
    assert lines[0].lyrics == "你的/信只留/下最后一封/淡淡笔迹/你熟悉的/温柔//请别"
    # 行首 `|:` 界不造空小节
    assert len(lines[0].bars) == 2


def test_durations_and_tie_merge():
    """tie_merge 口径:`5'_.`=3/4;`(5'__ 5'_)` 同音连线对并一击 3/4。"""
    meta, lines = parse_123(POC_SYS1)
    suppress_garbage(lines, meter=Fraction(4))
    attacks = collect_attacks(lines, tie_merge=True)
    bar1 = [a for a in attacks if a.printed_bar == 1]
    durs = [a.printed_duration for a in bar1]
    assert durs == [Fraction(3, 4), Fraction(3, 4), Fraction(1, 2),
                    Fraction(3, 4), Fraction(3, 4), Fraction(1, 2)]
    assert bar1[1].slur_tied
    # 小节和闭合 = 4 拍
    assert sum(durs) == 4
    # 攻击音高序列(印张度数,App C 框架)
    midis = [a.midi for a in bar1]
    assert midis == [67, 67, 72, 69, 69, 72]  # 5' 5' 1'' 6' 6' 1''


def test_bar_numbering_across_lines():
    """多行顺序累加小节号:第二行小节从上一行末尾续。"""
    text = "K:1=E\nM:4/4\n| 1 1 1 1 |\n| 2 2 2 2 |\n"
    _, _, attacks = _attacks(text)
    assert {a.printed_bar for a in attacks} == {1, 2}


def test_composite_beat_anchor():
    """第 n 小节起拍 = (n−1)×4(57 拍位锚)。"""
    a = Attack(midi=60, printed_bar=6, beat_in_bar=Fraction(0),
               printed_duration=Fraction(1))
    assert composite_beat(a) == 20


def test_suppress_rhythm_dominant():
    """失败模式 2:X 主导行(TAB 噪声)判垃圾。"""
    text = "K:1=E\nM:4/4\nX X | X X |\n| 1 1 1 1 |\n"
    _, lines, attacks = _attacks(text)
    garbage = [l for l in lines if l.suppressed]
    assert len(garbage) == 1
    assert garbage[0].suppress_reason == "rhythm_dominant"
    # 垃圾行不落事件
    assert {a.printed_bar for a in attacks} == {1}


def test_suppress_unclosed_noise():
    """`((X- ((1-)) X_))` 形噪声:和数散架 + 无歌词 → 判垃圾。"""
    text = "K:1=E\nM:4/4\n| 1- 2 | 3 |\n| 1 1 1 1 |\n"
    _, lines, _ = _attacks(text)
    assert lines[0].suppressed
    assert lines[0].suppress_reason == "bars_unclosed"
    assert not lines[1].suppressed


def test_real_line_never_suppressed():
    """真简谱行(闭合+有词)存活;变拍行(和≠4但有词)不得误杀。"""
    text = ("K:1=E\nM:4/4\n"
            "| 5'_ 5'_ 6'_ (3'_ 3') 0_ 3'__ 2'__ |\n"
            "w:你的/信只留\n"
            "| 1. 6_ 5_ |\n"
            "w:变拍\n")  # 构造和=2.5 的变拍行,带词→不得误杀
    meta, lines, _ = _attacks(text)
    assert not lines[0].suppressed
    assert not lines[1].suppressed


def test_rest_and_rhythm_do_not_attack():
    """0 与 X 不落攻击,但占拍位(时值进小节和)。"""
    text = "K:1=E\nM:4/4\n| 0 1 X 2 |\n"
    _, _, attacks = _attacks(text, dot_shift=0)
    assert len(attacks) == 2
    assert [a.midi for a in attacks] == [60, 62]
    assert attacks[1].beat_in_bar == Fraction(3)


def test_low_octave_commas():
    """低音点 `,`:点数计入八度换算(印张点数减一再加低音点位移)。"""
    text = "K:1=C\nM:4/4\n| 6,, 1, 1 1 |\n"
    _, _, attacks = _attacks(text, dot_shift=0)
    # 口径:octave = dots_up − commas + dot_shift;shift=0 时 6,, → −2。
    # (gs 印张默认 shift=−1 会再低一个八度,现实印张低音点极少;此测只钉公式。)
    assert attacks[0].midi == 69 + 12 * (-2)
    assert attacks[1].midi == 60 + 12 * (-1)


def test_fullbar_rest_z():
    text = "K:1=C\nM:4/4\n| Z |\n| 1 1 1 1 |\n"
    _, lines, attacks = _attacks(text)
    assert {a.printed_bar for a in attacks} == {2}
    # Z 小节号照累加(第1小节整小节休止),Z 闭合 = 拍号
    assert lines[0].bars[0].duration_sum == 4


def test_melody_score_perfect_and_shifted():
    """56 配对机制 × 旋律层:全配 F1=1;起音差半拍判错(τ 内才配)。"""
    from score_workbench.dolce_poc import melody_score
    # 印张 bar6(=旋律格 beat 0,align 20)两音 1 5;真值同
    attacks = collect_attacks(parse_123(
        "K:1=E\nM:4/4\n" + "| Z | Z | Z | Z | Z |\n| 1 5 1 5 |\n")[1],
        dot_shift=0)
    truth = [
        {"beat": 0.0, "midi": 60}, {"beat": 1.0, "midi": 67},
        {"beat": 2.0, "midi": 60}, {"beat": 3.0, "midi": 67},
    ]
    rep = melody_score(truth, attacks, align_beats=20)
    assert rep["f1"] == 1.0
    # 候选起音全错半拍 → 全散
    from copy import deepcopy
    attacks2 = deepcopy(attacks)
    for a in attacks2:
        a.beat_in_bar += Fraction(1, 2)
    rep2 = melody_score(truth, attacks2, align_beats=20)
    assert rep2["f1"] == 0.0
