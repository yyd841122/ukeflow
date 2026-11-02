"""统一展开规则(工单56):印张符号列 × 和弦指形 → 播放事件。

语义分层(ADR-0010 决策 2)的「展开」半边:符号层(×/数字/符杠/休止/技巧)
与播放事件层分开计分,展开规则在此单源、对所有候选一致——真值与候选草稿
走同一函数,任何一路都不许私下推导。

列(column)= 一个 attack 拍位上的印张记号束:
  marks   ×/数字/闷音记号(× 的品位来自当拍和弦指形,数字自带品位)
  tech    roll/strumUp/strumDown(波浪/箭头;整和弦拨,timbre 不改事件)
  tie     连音×柱(不占拍无攻击,真值不落事件)
  duration 该 attack 的时值(拍,有理数)

拍位/时值全程 Fraction 精确(节奏有理数精确比,工单56)。
"""

from dataclasses import dataclass
from fractions import Fraction


@dataclass(frozen=True)
class Event:
    string: int
    fret: int
    onset: Fraction
    duration: Fraction
    segment: str | None = None
    ref: Fraction | None = None      # 来源列拍位(诊断定位用)


class ExpansionWarning(Exception):
    """单条展开告警:候选输入的病形(× 无和弦锚/× 落闷音弦等)。"""


def rat(value) -> Fraction:
    """拍位/时值入参 → Fraction。接受 int/float/str('19/2'|'13.25')。"""
    if isinstance(value, Fraction):
        return value
    if isinstance(value, bool):
        raise ValueError(f"非法拍值 {value!r}")
    if isinstance(value, int):
        return Fraction(value)
    if isinstance(value, float):
        return Fraction(str(value))
    if isinstance(value, str):
        return Fraction(value)
    raise ValueError(f"非法拍值 {value!r}")


def chord_frets_at(beat, chords) -> list[int] | None:
    """当拍生效的和弦指形(frets ④③②① 序,-1=闷音);首个锚之前 = None。"""
    cur = None
    for c in chords:
        if rat(c["beat"]) <= beat:
            cur = c
        else:
            break
    return list(cur["frets"]) if cur else None


TECH_EXPANDING = ("roll", "strumUp", "strumDown")


def expand_events(columns, chords):
    """符号列 → 播放事件。返回 (events, warnings)。

    规则(单源,真值与候选同走):
    - 有 marks 的列逐记号展开;无 marks 而 tech ∈ roll/strumUp/strumDown 的列
      按整和弦展开(箭头/波浪盖全弦,×列与箭头同列出现时以 × 列为准);
    - × = 当拍和弦指形该弦品位;数字 = 自带品位;闷音/连音列不落事件;
    - tremolo 列的 × 列照常展开(椭圆只罩记号,不改 attack 语义)。
    """
    events, warns = [], []
    for col in columns:
        beat = rat(col["beat"])
        dur = col.get("duration")
        dur_f = rat(dur) if dur is not None else None
        seg = col.get("segment")
        marks = col.get("marks") or []
        tech = col.get("tech")
        frets = chord_frets_at(beat, chords)
        if col.get("tie"):
            continue
        tech_emitted = False
        if tech in TECH_EXPANDING:
            if frets is None:
                warns.append((beat, "扫弦无和弦锚,无法展开,丢弃"))
            else:
                for si, fret in enumerate(frets):
                    if fret >= 0:
                        events.append(Event(4 - si, int(fret), beat, dur_f,
                                            seg, beat))
                tech_emitted = True
        for m in marks:
            kind = m.get("kind")
            s = m.get("string")
            if kind == "muted":
                continue
            if tech_emitted and kind == "x":
                continue        # × 列与箭头/波浪同列:同一批弦,事件不重复
            if s not in (1, 2, 3, 4):
                warns.append((beat, f"弦号非法 {s!r},记号丢弃"))
                continue
            if kind == "x":
                if frets is None:
                    warns.append((beat, "× 无和弦锚,无法展开品位,丢弃"))
                    continue
                fret = frets[4 - s]
                if fret < 0:
                    warns.append((beat, f"× 落在闷音弦 S{s}(品位 -1),丢弃"))
                    continue
            elif kind == "digit":
                fret = m.get("fret")
                if fret is None:
                    warns.append((beat, f"数字记号缺品位 S{s},丢弃"))
                    continue
            else:
                warns.append((beat, f"未知记号类别 {kind!r},丢弃"))
                continue
            events.append(Event(int(s), int(fret), beat, dur_f, seg, beat))
    events.sort(key=lambda e: (e.onset, e.string))
    return events, warns


def column_tie_rows(payload):
    """延音线行(tie):[(from, to)]。"""
    return [(rat(t["from_beat"]), rat(t["to_beat"]))
            for t in payload.get("ties", [])]
