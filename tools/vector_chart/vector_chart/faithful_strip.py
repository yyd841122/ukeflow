"""原样流水横带(票06):整页多行 → 单行按小节序拼接。

方案 = 嵌套 SVG 裁切(内容零改写,浏览器原生坐标变换):
- 每小节一片:`<svg x y w h viewBox="lo 0 w h">` 裁自该系统原文,
  浏览器自动裁切/平移,字形/字体/渲染保真度 = 站方原样;
- **y 对齐**:每片的 y 属性 = 首系统谱线 y − 本系统谱线 y,消除
  跨系统谱线高低错位;
- **连续谱线底层**:在所有嵌套 svg 之下画 4 条整宽灰线(alphaTab
  原渲染的谱线分段在数字处断开;底层灰线补齐断处,不影响原渲染);
- **首系统头保留**(谱号/拍号/小节号),非首系统起始的重画谱号/
  拍号通过 viewBox 裁切自然排除(其 x 范围在首小节之外);
- 弱起:首小节印张内容右对齐,横带按印张切,时序保真。
"""
from __future__ import annotations

import json
import re

LINE_THICK = 1.28
LINE_COLOR = '#A5A5A5'


def _bar_ranges(edges: list[float], first_dx: float | None = None,
                skip_header: bool = False) -> list[tuple[float, float]]:
    """小节切片。首系统首片含系统头(x 从系统左缘起);非首系统首片
    从首个 TAB 数字左 5px 起切——每系统行首重画的谱号/拍号不进横带
    (TAB 标识只第 1 段展示一次)。"""
    lo0 = edges[0]
    if skip_header and first_dx is not None:
        lo0 = max(lo0, first_dx - 5)
    return [(lo0 if i == 0 else edges[i], edges[i + 1])
            for i in range(len(edges) - 1)]


def build_strip_svg(raw_html: str, system_info: list,
                    strip_gap: float = 0.0) -> tuple[str, dict]:
    """[system_info] = [(系统 svg 序号, edges, staff_ys, 首数字 x)]。

    返回 (横带 SVG, 元信息 dict)。
    """
    # 解析各系统 SVG body(按出现序 = 系统序)
    systems: dict[int, tuple[float, str]] = {}
    for m in re.finditer(
        r'<svg[^>]*width="([0-9.]+)px" height="([0-9.]+)px"[^>]*>(.*?)</svg>',
        raw_html, re.S):
        systems[len(systems)] = (float(m.group(2)), m.group(3))

    ref_y0 = system_info[0][2][0] if system_info else 69.4
    ref_staff = system_info[0][2] if system_info else []

    slices: list[str] = []
    meta_bars: list[dict] = []
    strip_x = 0.0
    max_h = 0.0
    bar_no = 0

    for si_idx, (sidx, edges, staff_ys, first_dx) in enumerate(system_info):
        sys_h, body = systems.get(sidx, (0, None))
        if body is None:
            continue
        dy = ref_y0 - staff_ys[0]  # y 对齐(正值 = 下移)
        max_h = max(max_h, sys_h)
        for lo, hi in _bar_ranges(edges, first_dx, skip_header=si_idx > 0):
            w = hi - lo
            # 嵌套 SVG 裁切:内容原样,viewBox 裁本小节
            slices.append(
                f'<svg x="{strip_x:.1f}" y="{dy:.1f}" width="{w:.1f}" '
                f'height="{sys_h:.1f}" viewBox="{lo:.1f} 0 {w:.1f} {sys_h:.1f}" '
                f'overflow="hidden">{body}</svg>')
            meta_bars.append({'bar': bar_no + 1, 'x': round(strip_x, 1),
                              'w': round(w, 1)})
            strip_x += w + strip_gap
            bar_no += 1

    total_w = strip_x - strip_gap if slices else 0

    # 连续谱线底层(整宽 4 条灰线,在所有嵌套 svg 之下)
    staff_bg = ''.join(
        f'<rect x="0" y="{ry:.2f}" width="{total_w:.0f}" '
        f'height="{LINE_THICK}" fill="{LINE_COLOR}"/>' for ry in ref_staff)

    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{total_w:.0f}" '
           f'height="{max_h:.0f}" viewBox="0 0 {total_w:.0f} {max_h:.0f}" '
           f'style="display:block">'
           f'<rect x="0" y="0" width="{total_w:.0f}" height="{max_h:.0f}" fill="white"/>'
           + staff_bg + ''.join(slices) + '</svg>')
    meta = {'width': round(total_w), 'height': round(max_h), 'bars': meta_bars}
    return svg, meta


def embed_strip(page_html: str, strip_svg: str, strip_meta: dict) -> str:
    """把横带与元信息以隐藏节点植入原样页(固定标记,Dart 侧字符串提取)。"""
    if 'id="ukeflow-strip"' in page_html:
        return page_html  # 已植入
    meta_json = json.dumps(strip_meta, ensure_ascii=False)
    return (page_html
            + '<div id="ukeflow-strip" style="display:none">'
            + strip_svg + '</div>'
            + '<script type="application/json" id="ukeflow-strip-meta">'
            + meta_json + '</script>')


def extract_strip(page_html: str) -> tuple[str | None, dict | None]:
    """从原样页提取横带 SVG 与元信息(无标记返回 (None, None))。"""
    m = re.search(
        r'<div id="ukeflow-strip" style="display:none">(.*?)</div>'
        r'<script type="application/json" id="ukeflow-strip-meta">(.*?)</script>',
        page_html, re.S)
    if not m:
        return None, None
    try:
        meta = json.loads(m.group(2))
    except ValueError:
        return m.group(1), None
    return m.group(1), meta
