"""原样渲染包装(票05,ADR-0011 矢量谱页双路线的「阅读」路线)。

把矢量谱页原文 div 包装成单文件自包含 HTML:官方 CSS 模板
(alphatab.net/docs/guides/nodejs §4,渲染面依赖 @font-face 加载 Bravura,
缺字体则 PUA 符号不显示)+ 字体 base64 内嵌 + 原 div 原文(不重排、
不重序列化)。产物浏览器直开 = 谱站像素级原样。配方来源与许可见
docs/research/2026-11-06-vector-page-faithful-render.md(Bravura,SIL OFL)。
"""
from __future__ import annotations

import base64
from pathlib import Path

# 官方 CSS 模板(§4)原样,仅 @font-face 的 src 换内嵌 woff、body 加留白。
_CSS_TEMPLATE = """
@font-face {
    font-family: 'alphaTab';
    src: url(data:font/woff;base64,__FONT_B64__) format('woff');
    font-weight: normal;
    font-style: normal;
}
.at-surface * {
    cursor: default;
    vertical-align: top;
    overflow: visible;
}
.at {
    font-family: 'alphaTab';
    speak: none;
    font-style: normal;
    font-weight: normal;
    font-variant: normal;
    text-transform: none;
    line-height: 1;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    font-size: 34px;
    overflow: visible !important;
}
body { margin: 0; padding: 12px; background: #fff; }
"""

# 字体默认位置:包内 fonts/Bravura.woff(SIL OFL,随仓库分发)
DEFAULT_FONT = Path(__file__).resolve().parent.parent / 'fonts' / 'Bravura.woff'


def build_faithful_html(raw_html: str, font_woff: str | Path | None = None) -> str:
    """矢量谱页原文 → 自包含原样 HTML(浏览器/WebView 直开)。

    [raw_html] 必须是**原文**(含 PUA 字形 g.at 节点);任何重序列化都可能
    破坏浏览器宽容解析下的原始布局。
    """
    font_path = Path(font_woff) if font_woff else DEFAULT_FONT
    woff_b64 = base64.b64encode(font_path.read_bytes()).decode()
    css = _CSS_TEMPLATE.replace('__FONT_B64__', woff_b64)
    return (
        '<!DOCTYPE html>\n<html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f'<style>{css}</style></head><body>\n{raw_html}\n</body></html>'
    )
