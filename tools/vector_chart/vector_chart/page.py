"""矢量谱页元素模型:alphaTab 渲染 HTML → 可解码几何。

文件形态(已钉事实,票01):一个 `<div class="at-surface">` 内若干
`<svg class="at-surface-svg">`,每 svg = 一个谱表系统;语义全在
`<text>`(内容)、`<rect>`(线/符干/小节线)、`<path>`(弧点/折线/曲段/符旗)。
无脚本、无嵌入 JSON。编码 UTF-16LE 与 UTF-8 都收。
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

_SVG = re.compile(r'<svg[^>]*width="([0-9.]+)px" height="([0-9.]+)px"[^>]*>(.*?)</svg>', re.S)
_TEXT = re.compile(r'<text x="([0-9.-]+)" y="([0-9.-]+)" style="([^"]*)"[^>]*>([^<]*)</text>')
_GLYPH = re.compile(
    r'<g transform="translate\(([0-9.-]+) ([0-9.-]+)\)" class="at">\s*'
    r'<text style="font-size: ([0-9]+)%;[^"]*">([^<]*)</text>')
_RECT = re.compile(r'<rect x="([0-9.-]+)" y="([0-9.-]+)" width="([0-9.-]+)" height="([0-9.-]+)"')
_PATH = re.compile(r'<path d="([^"]*)"')
_NUM = re.compile(r'[0-9.]+')
_CMD = re.compile(r'[MmLlCcQqAaZz]')


@dataclass
class TextEl:
    x: float
    y: float
    content: str
    bold: bool = False
    italic: bool = False
    font_px: float = 0.0


@dataclass
class GlyphEl:
    """音乐字体 PUA 字形(谱号/拍号数字)。"""

    x: float
    y: float
    code: int
    size_pct: int


@dataclass
class RectEl:
    x: float
    y: float
    w: float
    h: float


@dataclass
class PathEl:
    d: str
    x0: float
    y0: float
    bbox: tuple[float, float, float, float]  # x, y, w, h
    n_arcs: int
    n_lines: int
    n_curves: int
    n_q: int = 0  # Q 二次曲线(连音弓)


@dataclass
class System:
    index: int
    width: float
    height: float
    texts: list[TextEl] = field(default_factory=list)
    glyphs: list[GlyphEl] = field(default_factory=list)
    rects: list[RectEl] = field(default_factory=list)
    paths: list[PathEl] = field(default_factory=list)


@dataclass
class VectorPage:
    title: str = ''
    artist: str = ''
    credit: str = ''
    key_line: str = ''
    tempo_line: str = ''
    systems: list[System] = field(default_factory=list)


def _unescape(s: str) -> str:
    return (s.replace('&lt;', '<').replace('&gt;', '>')
             .replace('&amp;', '&').replace('&quot;', '"'))


def _path_points(d: str) -> list[tuple[float, float]]:
    """路径坐标点:M/L 取端点对;C 连控制点一起取(旗形极限在控制点);
    A 只取端点(半径/标志位不是坐标)。"""
    out: list[tuple[float, float]] = []
    tokens = _CMD.split(d)
    cmds = _CMD.findall(d)
    for cmd, seg in zip(cmds, tokens[1:]):
        nums = [float(n) for n in _NUM.findall(seg)]
        if cmd in ('Z', 'z') or len(nums) < 2:
            continue
        if cmd in ('C', 'c', 'Q', 'q'):
            for i in range(0, len(nums) - 1, 2):
                out.append((nums[i], nums[i + 1]))
        else:
            out.append((nums[-2], nums[-1]))
    return out


def _nums(d: str) -> list[float]:
    return [float(n) for n in _NUM.findall(d)]


def parse_page(raw: str) -> VectorPage:
    """解析整页渲染 HTML。raw 为解码后的 unicode 文本。"""
    page = VectorPage()
    matches = _SVG.findall(raw)
    for si, (w, h, body) in enumerate(matches):
        sysm = System(index=si, width=float(w), height=float(h))
        for m in _TEXT.finditer(body):
            x, y, style, content = m.groups()
            fs = re.search(r'font:(?:bold |italic )?([0-9.]+)px', style)
            sysm.texts.append(TextEl(
                x=float(x), y=float(y), content=_unescape(content),
                bold='bold' in style, italic='italic' in style,
                font_px=float(fs.group(1)) if fs else 0.0))
        for m in _GLYPH.finditer(body):
            x, y, pct, ch = m.groups()
            sysm.glyphs.append(GlyphEl(float(x), float(y), ord(ch), int(pct)))
        for m in _RECT.finditer(body):
            sysm.rects.append(RectEl(*(float(m.group(i)) for i in range(1, 5))))
        for m in _PATH.finditer(body):
            d = m.group(1)
            pts = _path_points(d)
            if not pts:
                continue
            xs = [x for x, _ in pts]
            ys = [y for _, y in pts]
            bx, by = min(xs), min(ys)
            sysm.paths.append(PathEl(
                d=d, x0=pts[0][0], y0=pts[0][1],
                bbox=(round(bx, 2), round(by, 2),
                      round(max(xs) - bx, 2), round(max(ys) - by, 2)),
                n_arcs=d.count('A'), n_lines=len(re.findall(r'[Ll]', d)),
                n_curves=d.count('C'), n_q=d.count('Q')))
        page.systems.append(sysm)
    # 标题带(系统0):歌名(最大字)/作者/署名/key/tempo
    if page.systems:
        band = page.systems[0].texts
        if band:
            biggest = max(band, key=lambda t: t.font_px)
            page.title = biggest.content
        for t in band:
            if t.content.startswith('key'):
                page.key_line = t.content
            elif t.content.startswith('♩') or t.content.startswith('♩'):
                page.tempo_line = t.content
        non_meta = [t.content for t in band
                    if t.content not in (page.title, page.key_line, page.tempo_line)
                    and not t.content.startswith('key') and '♩' not in t.content
                    and '♩' not in t.content]
        if len(non_meta) >= 1:
            page.artist = non_meta[0]
        if len(non_meta) >= 2:
            page.credit = non_meta[1]
    return page


def read_raw_text(path: str) -> str:
    """文件 → unicode 文本(UTF-16LE 原件与 UTF-8 副本同口径)。"""
    data = open(path, 'rb').read()
    if data[:2] in (b'\xff\xfe', b'\xfe\xff'):
        return data.decode('utf-16')
    return data.decode('utf-8-sig', errors='replace')


def read_page(path: str) -> VectorPage:
    """读文件为页面模型。"""
    return parse_page(read_raw_text(path))
