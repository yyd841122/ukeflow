"""CLI:矢量谱页 → ScoreIR JSON + 人读报告。"""
from __future__ import annotations

import argparse
import json
import re
import sys

from .decode_tab import DecodedTab, split_voices
from .gate import run_gate
from .page import read_page
from .score_ir import build_score_ir


def _slug(title: str) -> str:
    s = re.sub(r'[^\w一-鿿]+', '-', title.strip()).strip('-').lower()
    return s or 'chart'


def build_report(dt: DecodedTab, extra: dict, errors: list[str],
                 warnings: list[str]) -> str:
    lines = ['# 矢量谱页解码报告', '']
    lines.append(f'- 曲目:{dt.title}({dt.artist})')
    lines.append(f'- 拍号 {dt.meter[0]}/{dt.meter[1]},♩={dt.bpm},调号 {dt.key}')
    lines.append(f'- 小节:共 {len(dt.bars)} 小节;弱起垫 {extra["pickupPad"]} 拍')
    if extra.get('sections'):
        lines.append(f'- 段落:' + '、'.join(f'{lb}@b{bn}' for lb, bn in extra['sections']))
    if extra.get('harmonicBars'):
        lines.append(f'- 泛音小节:<12> 按同品常音转录(音高同、音色不建模):'
                     + '、'.join(f'b{n}' for n in extra['harmonicBars']))
    if extra.get('warnings'):
        lines.append('- 解码警告:')
        lines.extend(f'  - {w}' for w in extra['warnings'])
    lines.append('')
    lines.append('## 小节对账')
    lines.append('')
    lines.append('| 小节 | 列数 | 内容拍数 | 和弦 | 卷弦 |')
    lines.append('|---|---|---|---|---|')
    for b in dt.bars:
        chords = ','.join(f'{c.label}{"".join(str(f) for f in c.frets)}'
                          for c in b.chords) or '—'
        rolls = sum(1 for c in b.columns if c.roll)
        dur = sum(c.duration or 0.0 for c in b.columns)
        lines.append(f'| b{b.number} | {len(b.columns)} | {dur:g} | {chords} | {rolls} |')
    lines.append('')
    lines.append('## 体检闸')
    lines.append('')
    if errors:
        lines.append(f'**阻塞 {len(errors)} 项(不得导出):**')
        lines.extend(f'- {e}' for e in errors)
    else:
        lines.append('**全绿:自动放行**(红旗见下,人工目验项)。')
    if warnings:
        lines.append('')
        lines.append(f'**红旗/目验 {len(warnings)} 项:**')
        lines.extend(f'- {w}' for w in warnings)
    return '\n'.join(lines) + '\n'


def cmd_decode(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog='vector-chart')
    sub = ap.add_subparsers(dest='cmd', required=True)
    d = sub.add_parser('decode', help='解码矢量谱页 → ScoreIR JSON + 报告')
    d.add_argument('input', help='渲染页 HTML(UTF-16LE/UTF-8)')
    d.add_argument('--out', required=True, help='ScoreIR JSON 输出路径')
    d.add_argument('--report', required=True, help='人读报告输出路径')
    d.add_argument('--id', default=None, help='曲目 id(缺省 slug(曲名)-vector)')
    d.add_argument('--no-faithful', action='store_true',
                   help='不内嵌原样渲染 HTML(缺省:字体在位即内嵌 sourceHtml)')
    args = ap.parse_args(argv)

    from .page import read_raw_text
    raw_text = read_raw_text(args.input)
    page = read_page(args.input)
    from .decode_tab import decode_tab as _decode
    dt = _decode(page)
    chart_id = args.id or f'{_slug(dt.title)}-vector'
    ir, extra = build_score_ir(dt, chart_id,
                               source=f'vector-page:{chart_id}')
    faithful_html = None
    if not args.no_faithful:
        from .faithful import DEFAULT_FONT, build_faithful_html
        if DEFAULT_FONT.exists():
            # 原样渲染 HTML 内嵌为可选键(旧 App fromJson 忽略未知键,向前兼容);
            # App 导入流落库时拆列:sourceJson 保持纯 IR,sourceHtml 单列存原文。
            faithful_html = build_faithful_html(raw_text, font_woff=DEFAULT_FONT)
            # 原样流水横带(票06):单行小节序拼接(连续谱线/去重复谱号拍号),
            # 跟练播放头用
            from .faithful_strip import build_strip_svg, embed_strip
            edges_by = {si: e for si, e in dt.system_bar_edges}
            staff_by = {si: y for si, y in dt.system_staff_ys}
            digit_by = dict(dt.system_first_digit_x)
            system_info = [
                (si, edges_by[si], staff_by[si], digit_by[si])
                for si, _ in dt.system_bar_edges
                if si in edges_by and si in staff_by and si in digit_by
            ]
            strip_svg, strip_meta = build_strip_svg(raw_text, system_info)
            faithful_html = embed_strip(faithful_html, strip_svg, strip_meta)
        else:
            print('字体缺席,跳过原样渲染内嵌(fonts/Bravura.woff)', file=sys.stderr)
    errors, warnings = run_gate(ir, extra)
    report = build_report(dt, extra, errors, warnings)
    with open(args.report, 'w', encoding='utf-8') as f:
        f.write(report)
    if errors:
        print(f'体检闸阻塞 {len(errors)} 项——JSON 不落盘(坏源不导出)。', file=sys.stderr)
        for e in errors[:20]:
            print(f'  - {e}', file=sys.stderr)
        return 1
    if faithful_html is not None:
        ir['sourceHtml'] = faithful_html
    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump(ir, f, ensure_ascii=False, indent=1)
    n_notes = len(ir['voices']['melody']['notes']) + len(
        ir['voices']['accompaniment']['notes'])
    print(f'✓ {chart_id}: {len(ir["measures"])} 小节 / {n_notes} 音 / '
          f'{len(ir["chordAnchors"])} 和弦锚 / {len(ir["strums"])} 卷弦;'
          f'体检闸全绿,红旗 {len(warnings)} 项(见报告)')
    return 0


def main() -> int:
    return cmd_decode()


if __name__ == '__main__':
    raise SystemExit(main())
