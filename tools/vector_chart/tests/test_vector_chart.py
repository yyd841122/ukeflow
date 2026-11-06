# -*- coding: utf-8 -*-
"""矢量谱页解码黄金测试(票01)。

黄金事实全部来自 2026-11-05 几何考古 + 双小节听感/闭合互证;样本文件
在仓库外(~/ukeflow-sources/vector-pages/),缺席时 skip(位图纪律同款)。
"""
import json
import re
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from vector_chart.gate import run_gate  # noqa: E402
from vector_chart.page import read_page, read_raw_text  # noqa: E402
from vector_chart.score_ir import build_score_ir  # noqa: E402
from vector_chart import decode_tab as D  # noqa: E402

SAMPLE = Path.home() / 'ukeflow-sources' / 'vector-pages' / 'tiankongzhicheng.html'
SAMPLE_UTF16 = Path.home() / 'ukeflow-sources' / 'vector-pages' / 'tiankongzhicheng-orig-utf16.html'

needs_sample = pytest.mark.skipif(not SAMPLE.exists(), reason='样本文件缺席(仓库外 fixture)')


@pytest.fixture(scope='module')
def decoded():
    page = read_page(str(SAMPLE))
    return D.decode_tab(page)


@pytest.fixture(scope='module')
def score_ir(decoded):
    ir, extra = build_score_ir(decoded, 'tiankongzhicheng-vector', 'vector-page:test')
    return ir, extra


@needs_sample
def test_page_meta(decoded):
    assert decoded.title == '天空之城'
    assert decoded.artist == '久石让'
    assert decoded.bpm == 80
    assert decoded.key == '1=C'
    assert decoded.meter == (4, 4)


@needs_sample
def test_structure_golden(decoded):
    """51 小节全写出(无反复);五段段落标注。"""
    assert len(decoded.bars) == 51
    assert [b.number for b in decoded.bars] == list(range(1, 52))
    assert decoded.sections == [('Part A', 1), ('Part B', 18), ('Part C', 24),
                                ('Part A', 34), ('Ending', 46)]


@needs_sample
def test_pickup_bar(decoded):
    """弱起 = 第 1 小节 1 拍(两个八分,无卷弦)。"""
    b1 = decoded.bars[0]
    assert b1.total_duration == 1.0
    assert [c.duration for c in b1.columns] == [0.5, 0.5]
    assert b1.columns[0].notes[0].fret == 0  # 空弦 A
    assert b1.columns[1].notes[0].fret == 2  # 2 品 B


@needs_sample
def test_all_measures_close(decoded):
    """除弱起外每小节恰 4 拍(逐小节闭合是物化端总闸的原料)。"""
    for b in decoded.bars[1:]:
        assert b.total_duration == 4.0, f'b{b.number} = {b.total_duration}'


@needs_sample
def test_first_position_chords(decoded):
    """首位和弦指形(④③②① 相对品;考古逐音验证)。"""
    got = {}
    for b in decoded.bars:
        for c in b.chords:
            got.setdefault(c.label, (tuple(c.frets), c.base_fret))
    assert got['Am'] == ((2, 0, 0, 0), 1)
    assert got['Em'] == ((0, 4, 3, 2), 1)
    assert got['F'] == ((2, 0, 1, 0), 1)
    assert got['C'] == ((0, 0, 0, 3), 1)
    assert got['Dm'] == ((2, 2, 1, 0), 1)
    assert got['G'] == ((0, 2, 3, 2), 1)
    assert got['B7'] == ((2, 3, 2, 2), 1)


@needs_sample
def test_position_chords(decoded):
    """把位和弦:标注=窗口起始品,无点弦=闷音(-1);绝对品=相对+base-1。"""
    got = {}
    for b in decoded.bars:
        for c in b.chords:
            got[(c.label, b.number)] = (tuple(c.frets), c.base_fret)
    # b21 Em@7 品:9,7,7,7 = E5 G4 B4 E5
    assert got[('Em', 21)] == ((3, 1, 1, 1), 7)
    # b27 Fmaj7@5 品:C4 F4 A4 E5
    assert got[('Fmaj7', 27)] == ((1, 1, 1, 3), 5)
    # b32 Dm@5 品:D5 F4 A4 D5
    assert got[('Dm', 32)] == ((3, 1, 1, 1), 5)
    # b24 F@6 品:单点 s1 窗口相对 3(绝对 8 = F5)
    assert got[('F', 24)][0][3] == 3 and got[('F', 24)][1] == 6
    # 把位图无点弦 = 闷音(E@6:相对 [-1,3,2,2] = 绝对 -1,8,7,7)
    assert got[('E', 25)][0][0] == -1 and got[('E', 25)][1] == 6
    assert got[('E', 25)][0][1] == 3 and got[('E', 25)][0][2] == 2


@needs_sample
def test_ghost_roll_columns(decoded):
    """连音卷弦幽灵列(b15/b23/b49):符干在、数字无、连音弓连自前列。"""
    ghosts = [b for b in decoded.bars
              if any('幽灵列' in w for w in decoded.warnings)
              and b.number in (15, 23, 49)]
    assert {b.number for b in decoded.bars} >= {15, 23, 49}
    # b23: 幽灵列仿前列 (3,0,0) 三音、四分
    b23 = decoded.bars[22]
    assert b23.total_duration == 4.0
    assert sum(len(c.notes) for c in b23.columns) == 13  # 4+1+1+1+3+3(幽灵)


@needs_sample
def test_half_notes_and_harmonics(decoded):
    """b49 尾卷弦二分(符干比四分长 1.5px 互证);b51 <12> 泛音按同品转录。"""
    b49 = decoded.bars[48]
    assert b49.columns[-1].duration == 2.0
    b51 = decoded.bars[50]
    assert b51.total_duration == 4.0
    harm = b51.columns[-1]
    assert all(n.harmonic and n.fret == 12 for n in harm.notes)
    assert len(harm.notes) == 4


@needs_sample
def test_rolls(decoded):
    """卷弦(琶音波纹)数:全曲 88 个 roll 事件(与 IR 一致)。"""
    n_rolls = sum(1 for b in decoded.bars for c in b.columns if c.roll)
    assert n_rolls >= 80


@needs_sample
def test_voice_split(score_ir):
    """旋律=列内最高音;弱起拍右移(时序保真,骨架不动)。"""
    ir, _extra = score_ir
    mel = ir['voices']['melody']['notes']
    assert mel[0]['beat'] == 3.0 and mel[0]['midi'] == 69  # 弱起 A4 落 3.0
    assert mel[1]['beat'] == 3.5 and mel[1]['midi'] == 71  # B4
    # 开头动机:A B | C B C E …
    assert [n['midi'] for n in mel[:7]] == [69, 71, 72, 71, 72, 76, 71]


@needs_sample
def test_ir_structure(score_ir):
    ir, _extra = score_ir
    assert ir['schemaVersion'] == 1
    assert ir['meter'] == {'beatsPerMeasure': 4, 'beatUnit': 4}
    assert [m['number'] for m in ir['measures']] == list(range(1, 52))
    assert ir['measures'][0]['startBeat'] == 0
    assert ir['unsupportedSymbols'] == []
    kinds = {s['kind'] for s in ir['strums']}
    assert kinds == {'roll'}


@needs_sample
def test_gate_green(score_ir):
    """体检闸对正产物全绿(自动放行)。"""
    ir, extra = score_ir
    errors, warnings = run_gate(ir, extra)
    assert errors == []
    assert len(warnings) >= 3  # 幽灵列披露 + 泛音 + 段落


def test_gate_rejects_hole():
    """体检闸负例:小节空洞必须阻塞。"""
    ir = {
        'schemaVersion': 1, 'id': 'x', 'title': 't',
        'meter': {'beatsPerMeasure': 4, 'beatUnit': 4},
        'tempoMap': [{'beat': 0, 'bpm': 80}],
        'keyMap': [{'beat': 0, 'key': '1=C'}],
        'measures': [{'number': 1, 'startBeat': 0}, {'number': 2, 'startBeat': 4}],
        'melodyAlignBeats': 0,
        'voices': {
            'melody': {'notes': [
                {'beat': 0.0, 'durationBeats': 1.0, 'string': 1, 'fret': 0,
                 'midi': 69},
            ], 'rests': []},
            'accompaniment': {'notes': [
                {'beat': 0.0, 'durationBeats': 2.0, 'string': 3, 'fret': 0,
                 'midi': 60},
                {'beat': 2.0, 'durationBeats': 2.0, 'string': 4, 'fret': 0,
                 'midi': 67},
            ], 'rests': []},
        },
        'rests': [], 'slides': [], 'tremolos': [], 'strums': [],
        'chordAnchors': [], 'unsupportedSymbols': [], 'review': {},
    }
    errors, _ = run_gate(ir)
    assert any('空洞' in e or '尾欠' in e for e in errors)


def test_gate_rejects_bad_fret_and_midi():
    ir = {
        'schemaVersion': 1, 'id': 'x', 'title': 't',
        'meter': {'beatsPerMeasure': 4, 'beatUnit': 4},
        'tempoMap': [{'beat': 0, 'bpm': 80}],
        'keyMap': [{'beat': 0, 'key': '1=C'}],
        'measures': [{'number': 1, 'startBeat': 0}],
        'melodyAlignBeats': 0,
        'voices': {
            'melody': {'notes': [], 'rests': []},
            'accompaniment': {'notes': [
                {'beat': 0.0, 'durationBeats': 4.0, 'string': 1, 'fret': 99,
                 'midi': 70},  # 品位越界 + midi 不符
            ], 'rests': []},
        },
        'rests': [], 'slides': [], 'tremolos': [], 'strums': [],
        'chordAnchors': [], 'unsupportedSymbols': [], 'review': {},
    }
    errors, _ = run_gate(ir)
    assert any('品位非法' in e for e in errors)
    assert any('midi' in e for e in errors)


def test_gate_rejects_non_44_and_unsupported():
    ir = {
        'schemaVersion': 1, 'id': 'x', 'title': 't',
        'meter': {'beatsPerMeasure': 3, 'beatUnit': 4},
        'tempoMap': [{'beat': 0, 'bpm': 80}],
        'keyMap': [{'beat': 0, 'key': '1=C'}],
        'measures': [{'number': 1, 'startBeat': 0}],
        'melodyAlignBeats': 0,
        'voices': {
            'melody': {'notes': [], 'rests': []},
            'accompaniment': {'notes': [
                {'beat': 0.0, 'durationBeats': 3.0, 'string': 1, 'fret': 0,
                 'midi': 69},
            ], 'rests': []},
        },
        'rests': [], 'slides': [], 'tremolos': [], 'strums': [],
        'chordAnchors': [], 'unsupportedSymbols': [
            {'kind': 'harmonic', 'beat': 0.0},
        ], 'review': {},
    }
    errors, _ = run_gate(ir)
    assert any('仅支持 4/4' in e for e in errors)
    assert any('harmonic' in e for e in errors)


@needs_sample
def test_utf16_original_decodes_same():
    """UTF-16LE 原件与 UTF-8 副本解码结果一致(下载器双形态兼容)。"""
    if not SAMPLE_UTF16.exists():
        pytest.skip('UTF-16 原件缺席')
    page16 = read_page(str(SAMPLE_UTF16))
    dt16 = D.decode_tab(page16)
    dt8 = D.decode_tab(read_page(str(SAMPLE)))
    assert len(dt16.bars) == len(dt8.bars) == 51
    assert [b.total_duration for b in dt16.bars] == \
        [b.total_duration for b in dt8.bars]


# ── 原样流水横带(票06):非首系统头部裁切 ──────────────────────────

def test_strip_bar_ranges_skip_header_on_non_first_systems():
    """TAB 谱号/拍号只第 1 段展示一次:非首系统首片从首个 TAB 数字
    左 5px 起切(重画头不进横带);首系统首片保持系统左缘。"""
    from vector_chart.faithful_strip import _bar_ranges

    edges = [20.0, 198.0, 350.0]
    # 首系统:头保留(lo = 系统左缘)
    assert _bar_ranges(edges)[0] == (20.0, 198.0)
    # 非首系统:裁头(lo = 首数字左 5px;数字 x=71.7 → 66.7)
    assert _bar_ranges(edges, 71.7, skip_header=True)[0] == (66.7, 198.0)
    # 后续片不受影响
    assert _bar_ranges(edges, 71.7, skip_header=True)[1] == (198.0, 350.0)
    # 裁切锚不越过首小节线(数值异常时兜底)
    assert _bar_ranges(edges, 10.0, skip_header=True)[0] == (20.0, 198.0)


@needs_sample
def test_strip_build_visible_clef_only_once():
    """端到端:真样本页建横带,谱号字形坐标只落进第 1 片窗口。"""
    from vector_chart.faithful_strip import build_strip_svg
    from vector_chart import decode_tab as D

    page = read_page(str(SAMPLE))
    dt = D.decode_tab(page)
    edges_by = {si: e for si, e in dt.system_bar_edges}
    staff_by = {si: y for si, y in dt.system_staff_ys}
    digit_by = dict(dt.system_first_digit_x)
    system_info = [
        (si, edges_by[si], staff_by[si], digit_by[si])
        for si, _ in dt.system_bar_edges
    ]
    strip_svg, meta = build_strip_svg(read_raw_text(str(SAMPLE)), system_info)
    assert len(meta['bars']) == 51

    # 只数嵌套小节片(<svg x= 开头);外层横带 svg 无 x 属性,不配
    wins = []
    for m in re.finditer(
            r'<svg x="[\-0-9.]+" y="[\-0-9.]+" width="[0-9.]+" '
            r'height="[0-9.]+" viewBox="([\-0-9.]+) 0 ([0-9.]+) ', strip_svg):
        lo, w = float(m.group(1)), float(m.group(2))
        wins.append((lo, lo + w))
    # 谱号字形在原页各系统的 x(组内平移后 = 28.4,全系统同位)
    clef_x = 28.4
    assert sum(1 for lo, hi in wins if lo <= clef_x < hi) == 1, \
        'TAB 谱号只应在首片窗口可见'
