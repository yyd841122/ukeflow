"""dolce(悦谱)123 输出适配——工单 58③ 读取候选限时筛选。

10-27 POC(docs/research/2026-10-27-dolce-jianpu-poc.md)的后续验证:
整页喂入(裁条塌已知)+ 非简谱区抑制 + 事件回映射。回映射走**音序对齐**
(按行序对到版面切分的简谱带),不伪造 bbox——dolce 输出无坐标,证据链
契约不满足是 49 判定其不可作识别引擎的根因,本模块不假装解决它。

123 方言语义(src/abcfamily/dialect123.ts,唯一偏离 ABC 之处):
`-` 增时线(加一拍)、`_` 减时线(减半,可叠)、`.` 附点、`'`/`,` 高/低
八度点、`()` 圆滑/连线组、`~` 弧连下一音、`0` 休止、`Z[n]` 整小节休止、
大写 `X` 节奏音符(读不出的槽位,非乐音)、`[13]` 和音、`&` 小节内第二
声部、变音记号前置(`#4`)。休止/未知不落攻击事件。

音高映射:App 纯旋律版约定 = 印张八度点减一 + E→C 平移(工单 37 台账:
「度数不变,直接落 C 指位」),即度数 d、印张点数 k → C 大调基音 +12×(k−1)。
印张调号(K:1=E)不进映射——度数是相对量,App 侧已按 C 落指。

复评口径(工单 58 实测结论):工单 56 冻结评测集为 TAB 层(324 事件中
digit 记号仅 7 个),简谱引擎与该真值无交叠——「56 评分器复评」对 dolce
的可行形式 = 同一配对机制(score_layer/τ=1/32)× App 纯旋律真值(参照级,
真值无时值字段,两侧 dur=None,即攻击事件 F1:音高+起音)。
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from fractions import Fraction

# C 大调度数基音(d=1..7),App 纯旋律版落指框架(E→C 平移后)。
# 59a 基线适配(melody 草稿折 midi)同用此表。
C_MAJOR_BASE = {1: 60, 2: 62, 3: 64, 4: 65, 5: 67, 6: 69, 7: 71}


@dataclass
class Token:
    """一个音符/休止/节奏槽位(和音组拆平,拍位共用)。"""

    kind: str                    # 'note' | 'rest' | 'rhythm'(X) | 'bar_rest'(Z)
    degree: int | None = None    # 印张度数(note 1-7)
    dots_up: int = 0             # 印张高音点数(' 的个数)
    commas: int = 0              # 低音点数(, 的个数)
    beams: int = 0               # 减时线数(_)
    dots: int = 0                # 附点数(.)
    sustains: int = 0            # 增时线数(-)
    accidental: str | None = None  # '#'|'b'|'##'|'bb'|'n'(前置)
    slur_group: int | None = None  # 所处 () 连线组号(None=组外)
    tie_arc: bool = False        # 后置 ~(弧连下一音,显式 tie)
    z_bars: int = 0              # bar_rest:整小节休止小节数(Z4=4)
    onset: Fraction | None = None   # 小节内拍位(累加后回填)
    duration: Fraction | None = None  # 印张时值(拍;扫描端即定)

    def midi(self, dot_shift: int = -1) -> int | None:
        """App 落指框架音高(C 大调 + dot_shift 八度位移,gs 印张 = −1
        即「印张点数减一」);非乐音 None。"""
        if self.kind != "note":
            return None
        octave = self.dots_up - self.commas + dot_shift
        return C_MAJOR_BASE.get(self.degree, 60) + 12 * octave

    @property
    def is_attack(self) -> bool:
        return self.kind == "note"


@dataclass
class Bar:
    tokens: list[Token] = field(default_factory=list)
    declared_bars: int = 1       # Z / Z4 的整小节休止数
    index: int | None = None     # 印张小节号(顺序累加,1 起)

    @property
    def duration_sum(self) -> Fraction:
        return sum((_token_duration(t) for t in self.tokens), Fraction(0))


@dataclass
class MusicLine:
    bars: list[Bar] = field(default_factory=list)
    lyrics: str | None = None    # 紧随的 w: 行
    suppressed: bool = False     # 垃圾行判定(TAB 噪声)
    suppress_reason: str | None = None


# ── 解析 ──────────────────────────────────────────────────────────────

# 无 ^ 锚:match(s, pos) 下 ^ 只认字符串真起点,pos 锚定由 match 本身保证
_NOTE_RE = re.compile(r"(##|bb|#|b|n)?([0-7])('+)?" + r"(,+)?")
_META_KEY_RE = re.compile(r"^K:\s*(\S+)")
_META_TEMPO_RE = re.compile(r"^Q:\s*(\d+)\s*/\s*(\d+)\s*=\s*(\d+)")
_META_METER_RE = re.compile(r"^M:\s*(\d+)\s*/\s*(\d+)")


def _scan_token(line: str, i: int, slur_group: int | None) -> tuple[Token, int] | None:
    """行内单个 token。返回 None = 不认识(调用方按原样跳一格)。"""
    ch = line[i]
    if ch == " " or ch == "\t":
        return None
    # 和音组 [13] / [#46'] —— 音符共用后续时值
    if ch == "[":
        j = i + 1
        notes: list[Token] = []
        while j < len(line) and line[j] != "]":
            m = _NOTE_RE.match(line, j)
            if not m:
                return None
            t = Token("note", int(m.group(2)), dots_up=len(m.group(3) or ""),
                      commas=len(m.group(4) or ""), accidental=m.group(1),
                      slur_group=slur_group)
            notes.append(t)
            j = m.end()
            if j < len(line) and line[j] == "~":
                notes[-1].tie_arc = True
                j += 1
        if j >= len(line) or len(notes) < 2:
            return None
        j += 1  # ']'
        dur = _scan_duration(line, j)
        j = dur[1]
        for t in notes:
            t.beams, t.dots = dur[0].beams, dur[0].dots
            t.duration = _token_duration(t)
        first, rest = notes[0], notes[1:]
        rest_tokens = (t for t in rest)
        return _Multi(first, list(rest_tokens), j)
    # 休止 0 / 整小节休止 Z
    if ch == "0":
        t = Token("rest", 0, slur_group=slur_group)
        d = _scan_duration(line, i + 1)
        t.beams, t.dots, t.duration = d[0].beams, d[0].dots, d[0].duration
        return _finish_sustain(t, line, d[1])
    m = re.match(r"^Z(\d*)", line[i:])
    if m:
        t = Token("bar_rest", z_bars=int(m.group(1)) if m.group(1) else 1)
        return _Multi(t, [], i + m.end())
    # 节奏音符 X(读不出的槽位)
    if ch == "X":
        t = Token("rhythm")
        d = _scan_duration(line, i + 1)
        t.beams, t.dots, t.duration = d[0].beams, d[0].dots, d[0].duration
        return _finish_sustain(t, line, d[1])
    # 音符
    m = _NOTE_RE.match(line, i)
    if m:
        t = Token("note", int(m.group(2)), dots_up=len(m.group(3) or ""),
                  commas=len(m.group(4) or ""), accidental=m.group(1),
                  slur_group=slur_group)
        j = m.end()
        if j < len(line) and line[j] == "~":
            t.tie_arc = True
            j += 1
        d = _scan_duration(line, j)
        t.beams, t.dots, t.duration = d[0].beams, d[0].dots, d[0].duration
        return _finish_sustain(t, line, d[1])
    return None


class _Multi:
    """scan_token 的多 token 返回(和音组)。"""

    def __init__(self, first: Token, rest: list[Token], next_i: int):
        self.first = first
        self.rest = rest
        self.next_i = next_i


def _finish_sustain(t: Token, line: str, j: int) -> _Multi:
    n = 0
    while j < len(line) and line[j] == "-":
        n += 1
        j += 1
    t.sustains = n
    t.duration = _token_duration(t)
    return _Multi(t, [], j)


def _scan_duration(line: str, i: int) -> tuple[Token, int]:
    beams = dots = 0
    j = i
    while j < len(line):
        if line[j] == "_":
            beams += 1
            j += 1
        elif line[j] == ".":
            dots += 1
            j += 1
        else:
            break
    return Token("note", beams=beams, dots=dots), j


def _token_duration(t: Token, meter: Fraction = Fraction(4)) -> Fraction:
    """印张时值(拍):基拍按减时线折半、附点伸长、增时线各加一基拍。"""
    if t.kind == "bar_rest":
        return meter * t.z_bars
    base = Fraction(1, 2 ** t.beams)
    dur = base * (2 - Fraction(1, 2 ** t.dots))
    return dur + t.sustains * base


def parse_music_line(line: str) -> MusicLine | None:
    """一行音乐体 → MusicLine(bars 顺序)。

    连续小节界字符(`|:`、`:|`、`||`)算**一次**界;行首/行尾界产生的
    空小节丢弃(不移位小节号)。"""
    ml = MusicLine()
    cur = Bar()
    slurred = 0
    group_id = 0
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if ch in "|:":
            # 界字符连跑只收一次小节
            while i < n and line[i] in "|:":
                i += 1
            ml.bars.append(cur)
            cur = Bar()
            continue
        if ch == "(":
            slurred += 1
            group_id += 1
            i += 1
            continue
        if ch == ")":
            slurred = max(0, slurred - 1)
            i += 1
            continue
        if ch in " \t":
            i += 1
            continue
        res = _scan_token(line, i, group_id if slurred > 0 else None)
        if res is None:
            i += 1
            continue
        tokens = [res.first] + res.rest
        cur.tokens.extend(tokens)
        i = res.next_i
    ml.bars.append(cur)
    # 行首尾空小节(界字符产物)丢弃
    while ml.bars and not ml.bars[0].tokens and ml.bars[0].declared_bars == 1:
        ml.bars.pop(0)
    while ml.bars and not ml.bars[-1].tokens and ml.bars[-1].declared_bars == 1:
        ml.bars.pop()
    return ml


def parse_123(text: str):
    """整份 123 输出 → (meta, music_lines)。

    music_lines 只含音乐体行;`w:` 歌词行挂到前一音乐行(POC 输出形态)。
    """
    meta: dict = {}
    out: list[MusicLine] = []
    pending: MusicLine | None = None
    for raw in text.splitlines():
        line = raw.rstrip("\n")
        if not line.strip():
            continue
        if line.startswith("w:"):
            if pending is not None:
                pending.lyrics = line[2:].strip()
            continue
        if _META_KEY_RE.match(line):
            meta["key"] = _META_KEY_RE.match(line).group(1)
            continue
        if _META_METER_RE.match(line):
            m = _META_METER_RE.match(line)
            meta["meter"] = (int(m.group(1)), int(m.group(2)))
            continue
        if _META_TEMPO_RE.match(line):
            m = _META_TEMPO_RE.match(line)
            meta["tempo"] = int(m.group(3))
            meta["tempo_unit"] = f"{m.group(1)}/{m.group(2)}"
            continue
        if line.startswith(("X:", "T:", "C:", "%", "!")):
            continue  # 头部杂项
        ml = parse_music_line(line)
        # 无 token 且无界的行不是音乐体(如残片)
        if not any(b.tokens or b.declared_bars > 1 for b in ml.bars) \
                and not any(t for b in ml.bars for t in b.tokens):
            continue
        out.append(ml)
        pending = ml
    return meta, out


# ── 抑制(非简谱区=TAB/和弦垃圾行) ─────────────────────────────────

def suppress_garbage(lines: list[MusicLine], meter: Fraction = Fraction(4)) -> None:
    """就地标记垃圾行(POC 失败模式 2:TAB 行被硬读成噪声)。

    判据(启发式,全部计数入报告,不做静默丢弃):
    a) 节奏音符 X 占比 ≥ 50%(乐音+休止之外的主导槽位);
    b) 闭合小节(和=拍号)占比 < 50% 且无歌词行——真简谱行逐小节闭合,
       TAB 噪声行(`X X |`、`((X- ((1-)) X_))`)和数散架。
    """
    for ml in lines:
        tokens = [t for b in ml.bars for t in b.tokens]
        if not tokens:
            ml.suppressed = True
            ml.suppress_reason = "empty"
            continue
        rhythm = sum(1 for t in tokens if t.kind == "rhythm")
        notes = sum(1 for t in tokens if t.kind == "note")
        closed = sum(1 for b in ml.bars
                     if b.tokens and b.duration_sum == meter)
        if notes + rhythm and rhythm / (notes + rhythm) >= Fraction(1, 2):
            ml.suppressed = True
            ml.suppress_reason = "rhythm_dominant"
        elif closed * 2 < len(ml.bars) and ml.lyrics is None:
            ml.suppressed = True
            ml.suppress_reason = "bars_unclosed"


# ── 攻击事件与回映射 ──────────────────────────────────────────────

@dataclass
class Attack:
    midi: int
    printed_bar: int          # 印张小节号(1 起,全文档顺序累加)
    beat_in_bar: Fraction
    printed_duration: Fraction
    slur_tied: bool = False   # 由同音连线合并而来(印张 tie,非新攻击)
    line_index: int = 0       # 输出行序(回映射锚:音序对齐用)
    lyric: str | None = None


def collect_attacks(lines: list[MusicLine], meter: Fraction = Fraction(4),
                    dot_shift: int = -1, tie_merge: bool = False,
                    keep_suppressed: bool = False) -> list[Attack]:
    """存活行 → 攻击事件;小节号全文档顺序累加(逐行委托
    collect_line_attacks,回映射路走该函数带印张起始小节)。

    连线口径(tie_merge):False(默认)= 照读不并,连线组内每个 token
    自成一击(拍位照排)——与 App 真值约定一致(TabNote 把同音连线延音
    尾也存成独立音);True = 同 () 组内相邻同音并为一击(音乐攻击口径),
    显式 `~` 弧同并。组外相邻同音两种口径都不并(不同音节各是一击)。"""
    attacks: list[Attack] = []
    bar_no = 0
    for li, ml in enumerate(lines):
        if ml.suppressed and not keep_suppressed:
            continue
        attacks.extend(collect_line_attacks(ml, bar_no + 1, li, meter=meter,
                                            dot_shift=dot_shift,
                                            tie_merge=tie_merge))
        bar_no += len(ml.bars)
    return attacks


def collect_line_attacks(ml: MusicLine, bar_no_start: int, line_index: int,
                         meter: Fraction = Fraction(4), dot_shift: int = -1,
                         tie_merge: bool = False) -> list[Attack]:
    """单行攻击事件;小节号自 bar_no_start 起(回映射给定的印张起始)。"""
    attacks: list[Attack] = []
    bar_no = bar_no_start - 1
    for b in ml.bars:
        bar_no += 1
        pos = Fraction(0)
        last_token: Token | None = None
        group_attack: dict[int, Attack] = {}
        for t in b.tokens:
            dur = _token_duration(t)
            t.onset = pos
            t.duration = dur
            pos += dur
            if t.is_attack:
                target: Attack | None = None
                if tie_merge:
                    if t.slur_group is not None:
                        g = group_attack.get(t.slur_group)
                        if (g is not None and g.midi == t.midi(dot_shift)
                                and g.printed_bar == bar_no):
                            target = g
                    if target is None and last_token is not None \
                            and last_token.tie_arc:
                        p = attacks[-1] if attacks else None
                        if (p is not None and p.midi == t.midi(dot_shift)
                                and p.printed_bar == bar_no):
                            target = p
                if target is not None:
                    target.printed_duration += dur
                    target.slur_tied = True
                else:
                    a = Attack(
                        midi=t.midi(dot_shift), printed_bar=bar_no,
                        beat_in_bar=t.onset, printed_duration=dur,
                        line_index=line_index, lyric=ml.lyrics)
                    attacks.append(a)
                    if t.slur_group is not None:
                        group_attack[t.slur_group] = a
            last_token = t
    return attacks


def composite_beat(a: Attack) -> Fraction:
    """印张拍格:第 n 小节起拍 = (n−1)×4(57 冻结锚)。"""
    return Fraction(a.printed_bar - 1) * 4 + a.beat_in_bar


def melody_score(truth_notes, attacks, align_beats) -> dict:
    """56 配对机制 × 旋律层(攻击事件 F1:音高+起音;τ 规则同源)。

    truth_notes = dump_melody_truth 的 notes(beat/midi,旋律格);
    align_beats = score_sheet_defs.melodyAlignBeats(旋律格→印张格偏移)。
    真值无时值字段(TabNote 模型本无),两侧 dur=None → 节奏不扣分。
    口径注记:56 冻结评测集是 TAB 层(digit 仅 7 记号),此函数是
    「56 评分器复评」对简谱引擎的可行形式;真值为参照级,非冻结闸。
    """
    from .eval_scorer import CAP, score_layer
    from .eval_scorer import ScoredItem

    t_items = [ScoredItem(("p", n["midi"]),
                          Fraction(str(n["beat"])) + Fraction(str(align_beats)),
                          None, None, Fraction(str(n["beat"])))
               for n in truth_notes]
    c_items = [ScoredItem(("p", a.midi), composite_beat(a), None, None,
                          composite_beat(a))
               for a in attacks]
    beats = sorted({i.beat for i in t_items})
    gaps = [b - a for a, b in zip(beats, beats[1:])]
    tol = min([CAP] + [g / 2 for g in gaps if g > 0])
    rep = score_layer(t_items, c_items, tol)
    rep["tau"] = str(tol)
    rep["n_truth"] = len(t_items)
    rep["n_cand"] = len(c_items)
    return rep


# ── 回映射:存活行 → 版面系统(工单48 layout)对齐 ────────────────────

def candidate_assignments(survivors, systems):
    """存活行 → 版面系统的**全部**保序解(行 bar 数 == 系统 measure 数)。

    系统可空 = 该系统简谱行未被读出/全灭。解可能多于一个(小节段等长
    时结构本身不可分辨)——调用方按内容择优并披露,不许静默取第一个。
    无解(跨行续刀等)→ 空列表,按已知障碍报告。
    """
    from itertools import combinations

    out = []
    for picks in combinations(range(len(systems)), len(survivors)):
        pairs = []
        for line, si in zip(survivors, picks):
            nb = sum(1 for b in line.bars)
            ns = len(systems[si].get("measures", []))
            if nb != ns:
                pairs = None
                break
            pairs.append((line, systems[si], systems[si]["_start_bar"]))
        if pairs:
            out.append(pairs)
    return out


def run_eval(doc_text: str, layout_doc: dict, score_page: int,
             truth_notes: list, align_beats: float, window_from: int,
             window_to: int, meter: Fraction = Fraction(4), dot_shift: int = -1,
             start_bars: list[int] | None = None) -> dict:
    """工单58③ 跑分:整页 123 → 抑制 → 存活行对齐版面系统 → 窗口评分。

    score_page = layout.score_pages 下标(57 拼装的整谱页 png 一张对应
    一个 score_page;变拍区起布局累计号≠印张号,分歧页不给 start_bars
    就无解照实报)。start_bars = 显式印张起始小节(按行序逐一给,来自
    印张灰字锚,如 p1 的 14,18,22)——给定时跳过结构枚举,顺序落位。
    窗口 = 印张小节号区间(小节 n = 拍 (n−1)×4)。
    """
    meta, lines = parse_123(doc_text)
    suppress_garbage(lines, meter=meter)
    # 布局:目标 score_page 的系统序列,带全局累计起始小节号(工单48 布局号)
    cum = 0
    systems = []
    for pi, pg in enumerate(layout_doc["score_pages"]):
        for sy in pg["systems"]:
            sy = dict(sy)
            sy["_start_bar"] = cum + 1
            if pi == score_page:
                systems.append(sy)
            cum += len(sy["measures"])
    survivors = [l for l in lines if not l.suppressed]
    if start_bars is not None:
        if len(start_bars) != len(survivors):
            raise ValueError(
                f"start_bars({len(start_bars)}) 与存活行({len(survivors)})数不等")
        assignments = [[(ml, {"index": i, "measures": []}, sb)
                        for i, (ml, sb) in enumerate(zip(survivors,
                                                         start_bars))]]
    else:
        assignments = candidate_assignments(survivors, systems)
    line_rows = []
    for li, ml in enumerate(lines):
        row = {"line": li, "bars": len(ml.bars),
               "tokens": sum(len(b.tokens) for b in ml.bars),
               "lyric": bool(ml.lyrics)}
        row["disposition"] = (f"suppressed:{ml.suppress_reason}"
                              if ml.suppressed else "kept")
        line_rows.append(row)

    # 全部保序解逐一评分,按 F1 择优并披露解集(等长小节段结构歧义,
    # 择优=内容解歧,如实入报告;无解=已知障碍照实报)
    scored = []
    w_lo = Fraction(window_from - 1) * 4
    w_hi = Fraction(window_to) * 4
    truth_win = [n for n in truth_notes
                 if w_lo <= Fraction(str(n["beat"])) + Fraction(str(align_beats))
                 < w_hi]
    for pairs in assignments:
        attacks = []
        slots = []
        for (ml, sy, start_bar) in pairs:
            attacks.extend(collect_line_attacks(
                ml, start_bar, 0, meter=meter, dot_shift=dot_shift))
            slots.append({"system": sy.get("index"),
                          "printed_bars": f"{start_bar}..{start_bar + len(ml.bars) - 1}"})
        in_win = [a for a in attacks
                  if window_from <= a.printed_bar <= window_to]
        rep = melody_score(truth_win, in_win, align_beats)
        scored.append({"slots": slots, "attacks_in_window": len(in_win),
                       "score": rep, "attacks": attacks, "pairs": pairs})
    scored.sort(key=lambda e: e["score"]["f1"], reverse=True)
    best = scored[0] if scored else None
    if best is not None:
        attacks = best["attacks"]
        for (ml, sy, start_bar) in best["pairs"]:
            for row in line_rows:
                if lines[row["line"]] is ml:
                    row["assigned_system"] = sy.get("index")
                    row["printed_bars"] = (
                        f"{start_bar}..{start_bar + len(ml.bars) - 1}")
    return {
        "meta": meta,
        "lines": line_rows,
        "n_lines": len(lines), "n_survivors": len(survivors),
        "n_systems": len(systems),
        "n_assignments": len(scored),
        "assignment_ambiguous": len(scored) > 1,
        "assignment_slots": [e["slots"] for e in scored],
        "attacks_total": len(attacks) if best else 0,
        "attacks_in_window": best["attacks_in_window"] if best else 0,
        "truth_in_window": len(truth_win),
        "window": {"bars": [window_from, window_to]},
        "score": best["score"] if best else None,
    }
