"""四线 TAB 型矢量谱页 → 解码模型(票01 规则集)。

规则全部由 2026-11-05 几何考古钉死(证据见票面「已钉事实」),要点:
- 四线 TAB:弦线 = 分段细矩形(h≈1.3),数字(text)落位在弦线 y 上;
- 小节线 = 细竖矩形(w≈0.9,h≈28.6 跨四线);反复记号本曲无(51 小节全写出);
- 列 = 同 x 数字组;时值在谱下节奏带:符干(L1 竖 path,底=基线,bbox 口径)、
  符杠对(L3 矩形轮廓 path,y=基线-0.8,连相邻符干 = 一对八分;两行杠 =
  十六分,本曲未出现)、符旗(C1 曲段,无杠八分)、
  附点弧点(A2 小弧,符干右侧)→ ×1.5;余为四分;
- 弱起:第 1 小节内容右对齐(休止垫 0 拍侧),播放时序与印张一致;
- 连音卷弦幽灵列:符干有、数字无,Q 弓形连音线连自前列 → 仿前列声部
  (sys4 b23 / sys9 b49 实证);
- 卷弦(琶音波纹)= 折线+曲段组合在列左侧 → strums[roll];
- 和弦指法图:18.1px 网格,纵线左→右 = 弦④③②①(音高逐音验证),
  按位弧点 bb≈5.2,品位 = 数上方钢丝数 +1;
- `<n>` 数字 = n 品自然泛音(音高=同品常音,音色不计入运行时模型,报告披露);
- tie/滑音:本曲零(曲线路径普查仅波纹段+符旗+连音弓)。
"""
from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass, field

from .page import PathEl, System, TextEl, VectorPage

STRING_MIDI = {1: 69, 2: 64, 3: 60, 4: 67}  # GCEA 高 G(域事实,uke_string.dart)

# 版面常量(像素),来自样本考古
STAFF_LINE_H = (0.9, 1.8)       # 弦线矩形高
BARLINE_W = (0.6, 2.4)          # 小节线宽
BARLINE_H = (27.0, 30.5)        # 小节线高(跨四线)
DIGIT_FONT = (10.0, 12.0)       # TAB 数字字号
BARNUM_FONT = (8.5, 10.0)       # 小节号字号
CHORD_FONT_MIN = 9.0            # 和弦名(斜体)字号下限


@dataclass
class Note:
    string: int
    fret: int
    harmonic: bool = False


@dataclass
class Column:
    x: float
    notes: list[Note]
    duration: float | None = None
    beat: float | None = None
    roll: bool = False
    melody: list = field(default_factory=list)
    accompaniment: list = field(default_factory=list)

    @property
    def top_note(self):
        """列内最高音(midi 大者;同 midi 取 1 弦)。"""
        if not self.notes:
            return None
        return max(self.notes,
                   key=lambda n: (STRING_MIDI[n.string] + n.fret,
                                  -n.string))


@dataclass
class ChordShape:
    label: str
    x: float
    frets: list  # 图纵线左→右 = ④③②①(IR 同序,不翻转)
    base_fret: int = 1  # 图窗起始品(把位标注;1 = 琴枕)


@dataclass
class Bar:
    number: int
    columns: list = field(default_factory=list)
    chords: list = field(default_factory=list)
    warnings: list = field(default_factory=list)

    @property
    def total_duration(self) -> float:
        return sum(c.duration or 0.0 for c in self.columns)


@dataclass
class DecodedTab:
    meter: tuple
    bpm: int
    key: str
    bars: list
    sections: list  # (label, bar number)
    title: str
    artist: str
    warnings: list = field(default_factory=list)
    system_bar_edges: list = field(default_factory=list)  # [(系统号, [小节线 x…])] 按曲序
    system_staff_ys: list = field(default_factory=list)  # [(系统号, [四线 y…])]
    system_first_digit_x: list = field(default_factory=list)  # [(系统号, 首个数字 x)]


def _cluster(values, tol: float):
    """聚类一维值(排序后相邻差 ≤ tol 归同簇),返回 (代表值, 数量)。"""
    out = []
    for v in sorted(values):
        if out and v - out[-1][0] <= tol:
            prev, n = out[-1]
            out[-1] = ((prev * n + v) / (n + 1), n + 1)
        else:
            out.append((v, 1))
    return out


def _staff_rows(sysm: System):
    """四条弦线的 y(宽分段矩形聚类;取等距 8.5-10.5 的四连簇)。"""
    rows = [r.y for r in sysm.rects
            if STAFF_LINE_H[0] <= r.h <= STAFF_LINE_H[1] and r.w >= 35]
    clusters = _cluster(rows, 1.2)
    ys = [round(v, 1) for v, n in clusters if n >= 2]
    for i in range(len(ys) - 3):
        quad = ys[i:i + 4]
        gaps = [b - a for a, b in zip(quad, quad[1:])]
        if all(8.5 <= g <= 10.5 for g in gaps):
            return quad
    return None


def _barline_xs(sysm: System):
    xs = [r.x for r in sysm.rects
          if BARLINE_W[0] <= r.w <= BARLINE_W[1]
          and BARLINE_H[0] <= r.h <= BARLINE_H[1]]
    return [round(v, 1) for v, _ in _cluster(xs, 2.5)]


def decode_tab(page: VectorPage) -> DecodedTab:
    meter = (4, 4)
    m = re.search(r'key\s*=\s*(\S+)\s+(\d+)/(\d+)', page.key_line)
    key = f'1={m.group(1)}' if m else '1=C'
    if m:
        meter = (int(m.group(2)), int(m.group(3)))
    bpm = 80
    mt = re.search(r'=\s*(\d+)', page.tempo_line)
    if mt:
        bpm = int(mt.group(1))

    bars = []
    sections = []
    warnings = []
    system_edges = []  # [(系统 svg 序号, edges)]
    system_staff_ys = []  # [(系统 svg 序号, [四线 y…])]
    system_first_digit_x = []  # [(系统 svg 序号, 首个 TAB 数字 x)]

    for sysm in page.systems:
        if sysm.height <= 1 or not sysm.texts:
            continue  # 空尾系统
        staff = _staff_rows(sysm)
        if staff is None:
            continue  # 标题带系统
        s1, s2, s3, s4 = staff
        bl = _barline_xs(sysm)
        left = min(r.x for r in sysm.rects
                   if STAFF_LINE_H[0] <= r.h <= STAFF_LINE_H[1] and r.w >= 35)
        edges = [left] + sorted(bl)
        system_edges.append((sysm.index, edges))
        system_staff_ys.append((sysm.index, staff))
        sys_digits = [t.x for t in sysm.texts
                      if t.content.isdigit()
                      and DIGIT_FONT[0] <= t.font_px <= DIGIT_FONT[1]
                      and s1 - 2 <= t.y <= s4 + 2]
        system_first_digit_x.append((sysm.index, min(sys_digits) if sys_digits else left + 40))
        barnums = sorted((t.x, int(t.content)) for t in sysm.texts
                         if t.content.isdigit()
                         and BARNUM_FONT[0] <= t.font_px <= BARNUM_FONT[1]
                         and t.y < s1 - 4)
        sys_bars = []
        for i in range(len(edges) - 1):
            lo, hi = edges[i], edges[i + 1]
            num = None
            for bx, bn in barnums:
                if lo - 10 <= bx <= lo + 16:
                    num = bn
                    break
            bar = Bar(number=num if num is not None else
                      ((sys_bars[-1].number + 1) if sys_bars else
                       (bars[-1].number + 1 if bars else 1)))
            digits = [t for t in sysm.texts
                      if (t.content.isdigit() or re.fullmatch(r'<\d+>', t.content))
                      and DIGIT_FONT[0] <= t.font_px <= DIGIT_FONT[1]
                      and s1 - 2 <= t.y <= s4 + 2 and lo <= t.x < hi]
            by_x = []  # [(代表 x, [TextEl])]
            for t in digits:
                matched = None
                for entry in by_x:
                    if abs(entry[0] - t.x) <= 4:
                        matched = entry
                        break
                if matched is None:
                    by_x.append([t.x, [t]])
                else:
                    matched[1].append(t)
            for cx, ts in sorted(by_x, key=lambda e: e[0]):
                notes = []
                for t in ts:
                    hm = re.fullmatch(r'<(\d+)>', t.content)
                    if hm:
                        notes.append(Note(string=0, fret=int(hm.group(1)),
                                          harmonic=True))
                        continue
                    row = min(range(4), key=lambda k: abs(staff[k] - t.y))
                    notes.append(Note(string=row + 1, fret=int(t.content)))
                if any(n.harmonic for n in notes):
                    f = notes[0].fret
                    notes = [Note(string=s, fret=f, harmonic=True)
                             for s in (1, 2, 3, 4)]
                bar.columns.append(Column(x=cx, notes=notes))
            sys_bars.append(bar)
        # 时值:全系统统一做(符干/符杠跨列)
        _assign_durations(sysm, staff, sys_bars)
        # 未印数字的连音卷弦列(仿前列声部;弓形 Q 曲线 + 独立符干为证)
        _resolve_ghosts(sysm, staff, edges, sys_bars, warnings)
        # 卷弦
        _mark_rolls(sysm, staff, sys_bars)
        # 和弦指法图
        _decode_chords(sysm, sys_bars)
        # 段落标注(粗体非数字文本)
        for t in sysm.texts:
            if t.bold and t.y < s1 - 4 and not t.content.isdigit():
                if sys_bars:
                    sections.append((t.content, sys_bars[0].number))
        bars.extend(sys_bars)

    dt = DecodedTab(meter=meter, bpm=bpm, key=key, bars=bars,
                    sections=sections, title=page.title, artist=page.artist,
                    warnings=warnings)
    dt.system_bar_edges = system_edges
    dt.system_staff_ys = system_staff_ys
    dt.system_first_digit_x = system_first_digit_x
    assign_beats(dt)
    _number_bars(dt)
    return dt


def assign_beats(dt: DecodedTab) -> None:
    """列拍位 = 小节内时值累加(列序即 x 序)。弱起小节按内容局部拍位。"""
    for b in dt.bars:
        t = 0.0
        for c in b.columns:
            c.beat = round(t, 4)
            t += c.duration or 0.0
        if any(c.duration is None for c in b.columns):
            b.warnings.append('存在无符干列(时值未知),拍长闭合将由体检闸拦')


def _number_bars(dt: DecodedTab) -> None:
    """补漏小节号:检测断档(印张编号缺漏=红旗)。"""
    prev = 0
    for b in dt.bars:
        if b.number != prev + 1:
            dt.warnings.append(
                f'小节号断档:期望 {prev + 1},实际 {b.number}(印张编号缺漏或判别错)')
        prev = b.number


def _stems(sysm: System):
    """符干路径 + 基线 y(底 = bbox 上缘 + 高;M 点可能在任意端)。"""
    cands = [p for p in sysm.paths
             if p.n_arcs == 0 and p.n_curves == 0 and p.n_lines >= 1
             and p.bbox[2] < 1.5 and 10 <= p.bbox[3] <= 60]
    if not cands:
        return [], 0.0
    bottoms = Counter(round(p.bbox[1] + p.bbox[3], 1) for p in cands)
    baseline = bottoms.most_common(1)[0][0]
    stems = [p for p in cands if abs(p.bbox[1] + p.bbox[3] - baseline) <= 1.5]
    return stems, baseline


def _beams(sysm: System, baseline: float):
    return [p for p in sysm.paths
            if p.n_lines == 3 and p.n_arcs == 0 and p.n_curves == 0
            and 0.4 <= p.bbox[3] <= 1.4 and p.bbox[2] >= 10
            and abs(p.bbox[1] + p.bbox[3] - baseline) <= 2.0]


def _flags(sysm: System):
    return [p for p in sysm.paths
            if p.n_curves == 1 and 4 <= p.bbox[2] <= 9
            and 9 <= p.bbox[3] <= 16]


def _aug_dots(sysm: System, baseline: float):
    return [p for p in sysm.paths
            if p.n_arcs >= 2 and p.n_curves == 0
            and p.bbox[2] <= 4 and p.bbox[3] <= 4
            and baseline - 8 <= p.y0 <= baseline]


def _assign_durations(sysm: System, staff, bars: list) -> None:
    stems, baseline = _stems(sysm)
    beams = _beams(sysm, baseline)
    flags = _flags(sysm)
    dots = _aug_dots(sysm, baseline)
    cols = [c for b in bars for c in b.columns]
    if not cols:
        return
    # 符干 → 列(泛音列文本宽,窗放到 +12;近者认领,一干不二主)
    stem_of = {}
    taken = set()
    for c in cols:
        near = [(s, abs(s.x0 - c.x - 4)) for s in stems
                if c.x + 1.0 <= s.x0 <= c.x + 12.0 and id(s) not in taken]
        if near:
            best = min(near, key=lambda t: t[1])[0]
            stem_of[id(c)] = best
            taken.add(id(best))

    def stem_at(x):
        near = [sx for sx in stem_xs if abs(sx - x) <= 1.2]
        return near[0] if near else None

    stem_xs = sorted(s.x0 for s in stems)  # 全量符干(含未认领的幽灵成员)
    links = set()
    for bm in beams:
        a = stem_at(bm.x0)
        b = stem_at(bm.x0 + bm.bbox[2])
        if a is not None and b is not None and a != b:
            links.add((min(a, b), max(a, b)))
    adj = {}
    for a, b in links:
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)
    groups = []
    seen = set()
    for sx in stem_xs:
        if sx in seen or sx not in adj:
            continue
        stack, grp = [sx], set()
        seen.add(sx)
        while stack:
            u = stack.pop()
            grp.add(u)
            for v in adj.get(u, ()):
                if v not in seen:
                    seen.add(v)
                    stack.append(v)
        groups.append(grp)
    unit_by_stem = {}
    for grp in groups:
        layer_ys = sorted({round(bm.bbox[1], 1) for bm in beams
                           if stem_at(bm.x0) in grp
                           and stem_at(bm.x0 + bm.bbox[2]) in grp})
        lines = max(1, len(_cluster(layer_ys, 1.2)))
        unit = 0.5 ** lines
        for sx in grp:
            unit_by_stem[sx] = unit
    for c in cols:
        st = stem_of.get(id(c))
        if st is None:
            c.duration = None
            continue
        low_row = max((n.string for n in c.notes),
                      default=None)  # 行最靠下的弦 = 弦号最大
        st.metadata_low_row = (staff[low_row - 1] if low_row else None)
        st.metadata_warn = None
        c.duration = _stem_duration(st, stems, baseline, beams, flags, dots,
                                    staff, unit_by_stem)
        if st.metadata_warn:
            c.warnings = getattr(c, 'warnings', []) or []



def _stem_duration(st, stems, baseline, beams, flags, dots, staff,
                   unit_by_stem):
    """符干 → 时值(拍)。

    杠组单元 > 符旗(八分) > 无杠:四分或二分——二分 = 无杠无旗无点且
    符干比「列内最低音弦位 + 6.5」推导的四分长度短 ≥1px(sys9 b49 /
    sys10 b51 双实例互证,两处小节闭合恰 +1 拍)。
    """
    dur = unit_by_stem.get(st.x0, 1.0)
    if st.x0 in unit_by_stem:
        pass  # 杠组成员:单元即八分/十六分
    else:
        if any(abs(f.x0 - (st.x0 + 1.2)) <= 2.5 for f in flags):
            dur = 0.5  # 符旗 = 无杠八分
        else:
            dur = 1.0
            low_row_y = getattr(st, 'metadata_low_row', None)
            if low_row_y is not None:
                expected_h = baseline - (low_row_y + 6.5)
                if st.bbox[3] >= expected_h + 1.0:
                    dur = 2.0  # 二分:杆比同弦位四分长 ≥1px(b49/b51 互证)
                elif st.bbox[3] <= expected_h - 1.0:
                    warnings = getattr(st, 'metadata_warn', None)
                    st.metadata_warn = (
                        f'符干长 {st.bbox[3]:.1f} 与期望 {expected_h:.1f} 不符')
    if any(st.x0 - 1.0 <= d.x0 + d.bbox[2] / 2 <= st.x0 + 5.5
           and abs(d.y0 - baseline) <= 6.5 for d in dots):
        dur *= 1.5
    return dur


def _resolve_ghosts(sysm: System, staff, edges, bars: list,
                    warnings: list) -> None:
    """连音卷弦幽灵列:符干有、数字无,弓形连音线连自前列。

    判据(考古钉死,sys4 b23 / sys9 b49):独立符干未被任何数字列认领 +
    Q 弓形曲线末端落在符干 ±4px + 前列存在 → 新列仿前列全部音符、
    时值取自身符干。无弓形归因则红旗待查(禁止静默丢)。
    """
    stems, baseline = _stems(sysm)
    beams = _beams(sysm, baseline)
    flags = _flags(sysm)
    dots = _aug_dots(sysm, baseline)
    # 杠组单元(与 _assign_durations 同法)
    unit_by_stem = {}
    stem_xs = sorted(s.x0 for s in stems)

    def stem_at(x):
        near = [sx for sx in stem_xs if abs(sx - x) <= 1.2]
        return near[0] if near else None

    links = set()
    for bm in beams:
        a, b = stem_at(bm.x0), stem_at(bm.x0 + bm.bbox[2])
        if a is not None and b is not None and a != b:
            links.add((min(a, b), max(a, b)))
    adj = {}
    for a, b in links:
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)
    seen = set()
    for sx in stem_xs:
        if sx in seen or sx not in adj:
            continue
        stack, grp = [sx], set()
        seen.add(sx)
        while stack:
            u = stack.pop()
            grp.add(u)
            for v in adj.get(u, ()):
                if v not in seen:
                    seen.add(v)
                    stack.append(v)
        layer_ys = sorted({round(bm.bbox[1], 1) for bm in beams
                           if stem_at(bm.x0) in grp
                           and stem_at(bm.x0 + bm.bbox[2]) in grp})
        unit = 0.5 ** max(1, len(_cluster(layer_ys, 1.2)))
        for gx in grp:
            unit_by_stem[gx] = unit
    taken = set()
    for b in bars:
        for c in b.columns:
            for st in stems:
                if c.x + 1.0 <= st.x0 <= c.x + 12.0:
                    taken.add(id(st))
    unmatched = sorted((s for s in stems if id(s) not in taken),
                       key=lambda s: s.x0)
    if not unmatched:
        return
    arches = [p for p in sysm.paths if p.n_q >= 1 and p.bbox[2] >= 8]

    def _stem_dur(st):
        return _stem_duration(st, stems, baseline, beams, flags, dots,
                              staff, unit_by_stem)

    last_col, last_bar = None, None
    for b in bars:
        for c in b.columns:
            if c.notes:
                last_col, last_bar = c, b
    for st in unmatched:
        hit = None
        for a in arches:
            ax2 = a.bbox[0] + a.bbox[2]
            if ax2 - 4 <= st.x0 <= ax2 + 4:
                hit = ax2
                break
        if hit is None or last_col is None or last_bar is None:
            warnings.append(
                f'有符干无对应数字列 @x={st.x0:.0f}(无连音弓可归因),红旗待查')
            continue
        ghost = Column(x=st.x0 - 2.0,
                       notes=[Note(string=n.string, fret=n.fret,
                                   harmonic=n.harmonic) for n in last_col.notes],
                       roll=last_col.roll)
        low_row = max((n.string for n in ghost.notes),
                      default=None)  # 行最靠下的弦 = 弦号最大
        st.metadata_low_row = (staff[low_row - 1] if low_row else None)
        ghost.duration = _stem_dur(st)
        # 插回符干 x 所在小节(小节区间由 edges 定)
        target = None
        for i in range(len(edges) - 1):
            if edges[i] - 6 <= st.x0 < edges[i + 1]:
                target = bars[i] if i < len(bars) else None
                break
        if target is None:
            warnings.append(
                f'连音卷弦幽灵列 @x={st.x0:.0f} 落在小节区间外,红旗待查')
            continue
        target.columns.append(ghost)
        warnings.append(
            f'连音卷弦幽灵列 @x={st.x0:.0f}:仿前列声部({len(ghost.notes)} 音)'
            f' 时值 {ghost.duration}')
        last_col, last_bar = ghost, target


def _mark_rolls(sysm: System, staff, bars: list) -> None:
    cols = [c for b in bars for c in b.columns]
    squig_x = []
    for p in sysm.paths:
        is_sq = ((p.n_lines == 1 and p.n_curves == 1 and p.bbox[2] < 3)
                 or (p.n_lines == 2 and p.n_curves == 0 and 3 <= p.bbox[2] <= 6)
                 or (p.n_curves == 1 and p.n_lines == 0
                     and p.bbox[2] < 3 and p.bbox[3] < 6))
        if is_sq and staff[0] - 12 <= p.bbox[1] <= staff[3] + 8:
            squig_x.append(p.x0)
    groups = [v for v, n in _cluster(sorted(squig_x), 6.0) if n >= 2]
    for c in cols:
        if any(c.x - 8 <= gx <= c.x + 1 for gx in groups):
            c.roll = True


def _decode_chords(sysm: System, bars: list) -> None:
    texts = [t for t in sysm.texts if t.italic and t.font_px >= CHORD_FONT_MIN]
    nuts = [r for r in sysm.rects if 17 <= r.w <= 19.5 and 0.8 <= r.h <= 1.15]
    dot_paths = [p for p in sysm.paths
                 if p.n_arcs >= 2 and p.n_curves == 0 and 4 <= p.bbox[2] <= 6.5]
    # 把位标注:7.56px 数字文本,贴图左侧(nut.y ± 12 行高内)
    pos_labels = [(t.x, t.y, int(t.content)) for t in sysm.texts
                  if t.content.isdigit() and 7.0 <= t.font_px <= 8.0]
    for nut in nuts:
        name = None
        for t in texts:
            if abs(t.x - nut.x) <= 14 and t.y < nut.y:
                name = t.content
                break
        if name is None:
            continue
        base = 1
        for lx, ly, lv in pos_labels:
            if nut.x - 20 <= lx <= nut.x - 4 and nut.y - 4 <= ly <= nut.y + 12:
                base = lv
                break
        verts = sorted(r.x + r.w / 2 for r in sysm.rects
                       if r.w <= 1.2 and abs(r.h - 30.2) < 1.5
                       and nut.x - 2 <= r.x <= nut.x + nut.w + 2)
        wires = sorted(r.y for r in sysm.rects
                       if abs(r.x - nut.x) < 1.5 and abs(r.w - nut.w) < 2
                       and r.h <= 0.9 and nut.y < r.y < nut.y + 34)
        frets = [0 if base == 1 else -1 for _ in range(4)]  # 首位图无点=空弦;把位图无点=闷音
        wire_cs = [wy + 0.25 for wy in wires]  # 钢丝中心(细矩形 h=0.5)
        nut_bottom = nut.y + nut.h
        for p in dot_paths:
            cx = p.x0 + p.bbox[2] / 2
            cy = p.y0  # 圆弧两端点都在圆心 y 上(端点解析)
            if not (nut.x - 6 <= cx <= nut.x + nut.w + 6):
                continue
            if not (nut_bottom <= cy <= (wire_cs[-1] + 4 if wire_cs
                                         else nut.y + 34)):
                continue
            si = min(range(4), key=lambda i: abs(verts[i] - cx))
            grid_row = 1 + sum(1 for wc in wire_cs if wc < cy)
            frets[si] = min(grid_row, 15)  # 窗口相对品(绝对 = 相对 + base - 1)
        shape = ChordShape(label=name, x=nut.x, frets=frets, base_fret=base)
        # 归属小节:图 x 落在哪个小节内容区间
        for b in bars:
            cols = b.columns
            if not cols:
                continue
            lo = min(c.x for c in cols) - 14
            hi = max(c.x for c in cols) + 14
            if lo <= nut.x <= hi:
                b.chords.append(shape)
                break


NATURAL_PCS = {0, 2, 4, 5, 7, 9, 11}  # 1=C 自然音级(运行时简谱推导的域)


def split_voices(dt: DecodedTab) -> None:
    """列内声部分配(就地)。

    伴奏 = 列内**全部音符**(金标准惯例:主轴 TAB 承载完整编配,四线谱
    跟练不丢音);旋律 = 列内最高音的参考简谱行(与伴奏跨声部重复,校验
    器明文允许;双轨混播即此设计)。变化音顶级(Am 调内的 F#/D# 等)进
    不了运行时简谱推导(_degreeOfPitchClass 明文拒绝)→ 不入旋律层、
    由声部休止占位,计数披露——完整音仍在伴奏 TAB。
    单音列:1 弦或 2 弦高音 → 旋律候选;否则只进伴奏。
    """
    skipped = 0
    for b in dt.bars:
        for c in b.columns:
            c.melody = []
            c.accompaniment = list(c.notes)
            if not c.notes:
                continue
            top = c.top_note
            if len(c.notes) == 1:
                n = c.notes[0]
                midi = STRING_MIDI[n.string] + n.fret
                top_ok = n.string == 1 or (n.string == 2 and midi >= 66)
            else:
                top_ok = True
            if top_ok and top is not None:
                midi = STRING_MIDI[top.string] + top.fret
                if midi % 12 in NATURAL_PCS:
                    c.melody = [top]
                else:
                    skipped += 1
    if skipped:
        dt.warnings.append(
            f'旋律参考行省略 {skipped} 个变化音顶级(运行时简谱行只支持自然'
            f'音级;完整音仍在伴奏 TAB 层,对应拍位落声部休止)')
