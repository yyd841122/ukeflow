#!/usr/bin/env python3
"""pdf_census.py — 谱全了式位图 PDF 记号普查(工单41,实验性)。

gs-aini 真值验证结论(2026-10-25):自动拍位标定未达可用线
(音符 F1≈0.4,目标 0.85)——印张逐小节不等宽 + 字形锚位漂移 ±0.3 拍,
无人工锚的自动标定撞墙。工具保留价值:形状档案分类器、组件普查、
px 级定位表(--json);拍位列须人工按系统锚定后才有意义。
定位:转录辅助,不是 OMR 引擎。承诺「枚举全 + 不确定显式标出」,
不承诺「识别对」;最终数据准确度由互证测试 + 人工校验/听验保底。

用法:
  # 普查 + 报告
  python3 tools/pdf_census.py ~/ukeflow-sources/gs-aini.pdf --report 报告.md
  # 普查 + 对真值 diff(真值经 tools/dump_score_sheet_json.dart 导出)
  python3 tools/pdf_census.py ~/ukeflow-sources/gs-aini.pdf --gt /tmp/gs-aini-gt.json

依赖(dev-only,不进 app):python3 -m venv /tmp/pdfenv
  /tmp/pdfenv/bin/pip install pypdfium2 pillow numpy scipy

形状档案(2026-10-25 工单39 像素实测,render scale=3,弦距14px):
  ×=两笔交叉10×14笔画2.2 | 堆2/3/4=高26/40/54宽≤14 | 波浪=同尺寸蛇形(行剖面单笔)
  箭头=同尺寸+端部行宽≥8 | 八分休止=实心点10×6.5+尾(顶部行致密) | 多拍休止=宽≥28高≤18
  长音椭圆=14≤w≤28、16≤h≤30空心 | 震音椭圆=h≥40空心 | 数字=8×12均匀致密
"""

import argparse
import json
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
import pypdfium2 as pdfium

SCALE = 3.0          # 渲染倍率(弦距14px,与工单39实测档案同基准)
GAP = 14.0           # 弦距 px
STAFF_SPAN = 3 * GAP # ①→④ 弦线总高
LINE_RUN = 14        # ≥此横向 run 视为弦线删除
T_LINE = 235         # 弦线/小节线灰度阈(浅灰)
T_INK = 195          # 字形墨阈


# ── 页面级检测 ──────────────────────────────────────────────────────────

def find_systems(dark, width):
    """staff 四线组(≥75% 页宽的横线,每4条一组),返回各组首线 y。"""
    rows = dark.sum(axis=1)
    ys = [y for y in range(dark.shape[0]) if rows[y] > width * 0.75]
    groups = []
    for y in ys:
        if groups and y - groups[-1][-1] <= 6:
            groups[-1].append(y)
        else:
            groups.append([y])
    return [g[0] for g in groups][::4]


def find_barlines(dark, top):
    """贯穿 staff 高的竖线(含首尾),返回 x 列表。"""
    band = dark[top - 2:top + int(STAFF_SPAN) + 4, :]
    cols = np.where(band.sum(axis=0) >= STAFF_SPAN - 2)[0]
    groups = []
    for x in cols:
        if groups and x - groups[-1][-1] <= 2:
            groups[-1].append(x)
        else:
            groups.append([x])
    return [float(np.mean(g)) for g in groups]


def find_chord_labels(dark, top):
    """和弦名行文字块。名牌行高逐系统浮动(实测 top-52..top-17),
    带宽取 top-56..top-12,过滤 y 过低/过高与弦线残段。"""
    y_off = max(0, top - 56)
    band = dark[y_off:top - 12, :]
    lab, n = ndimage.label(band)
    out = []
    cands = []  # (x0, x1, mask_sliver)
    for i, sl in enumerate(ndimage.find_objects(lab)):
        w = sl[1].stop - sl[1].start
        h = sl[0].stop - sl[0].start
        size = int((lab[sl] == i + 1).sum())
        if w < 12 or size < 25:
            continue
        if 8 <= h <= 26:
            out.append((float(sl[1].start), float(sl[1].stop), float(w)))
        elif size >= 60:
            # 与和弦图框粘连的名牌:取底部 20px 切片重标(名坐框与谱表之间)
            sliver = (lab[sl] == i + 1)[-20:, :]
            lab2, _ = ndimage.label(sliver)
            for j, sl2 in enumerate(ndimage.find_objects(lab2)):
                w2 = sl2[1].stop - sl2[1].start
                h2 = sl2[0].stop - sl2[0].start
                size2 = int((lab2[sl2] == j + 1).sum())
                if size2 >= 25 and 12 <= w2 and 6 <= h2 <= 20:
                    out.append((float(sl[1].start + sl2[1].start),
                                float(sl[1].start + sl2[1].stop), float(w2)))
    # 去重:x0 相近(切片重标与整块重复检出)保留前者
    dedup = []
    for x0, x1, w in sorted(out):
        if dedup and x0 - dedup[-1][0] < 15:
            continue
        dedup.append((x0, x1, w))
    return dedup


# ── 字形组件与分类 ──────────────────────────────────────────────────────

def band_components(dark, top, remove_lines):
    """staff 带内字形组件。remove_lines=True 时只删 4 根弦线行上的长横 run
    (小件通道;整行扫删会切成波浪碎片,故高件通道不删线)。"""
    y0, y1 = top - 12, top + int(STAFF_SPAN) + 22
    seg = dark[y0:y1, :].copy()
    if remove_lines:
        line_rows = [top + k * GAP for k in range(4)]
        for lr in line_rows:
            for yy in range(int(lr) - y0 - 1, int(lr) - y0 + 2):
                if not (0 <= yy < seg.shape[0]):
                    continue
                row = seg[yy]
                xx = 0
                while xx < seg.shape[1]:
                    if row[xx]:
                        x2 = xx
                        while x2 < seg.shape[1] and row[x2]:
                            x2 += 1
                        if x2 - xx >= LINE_RUN:
                            seg[yy, xx:x2] = False
                        xx = x2
                    else:
                        xx += 1
    lab, n = ndimage.label(seg)
    comps = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        h, w = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        mask = lab[sl] == i + 1
        size = int(mask.sum())
        if size < 10:
            continue
        comps.append({
            'x': float(sl[1].start), 'y': float(sl[0].start + y0),
            'w': float(w), 'h': float(h), 'size': size,
            'fill': size / (w * h), 'mask': mask,
        })
    return comps


def _row_runs(mask):
    """每行的墨 run 数与最大 run 宽(抽样 7 行)。"""
    h = mask.shape[0]
    stats = []
    for yy in np.linspace(1, h - 2, 7).astype(int):
        xs = np.where(mask[yy])[0]
        if len(xs) == 0:
            stats.append((0, 0))
            continue
        runs = np.split(xs, np.where(np.diff(xs) > 2)[0] + 1)
        stats.append((len(runs), max(len(r) for r in runs)))
    return stats


def classify(c, top):
    """形状档案 → (类别, 置信)。判据冲突降置信,不硬猜。"""
    w, h, fill = c['w'], c['h'], c['fill']
    rel_y = c['y'] - top  # 组件顶相对 staff 首线

    if w > 160:
        return 'merged', 0.0  # 密集段整体粘连,不可分类,如实丢弃
    if w <= 5 and h >= 20:
        return 'stem', 0.9
    if h >= 40 and w <= 16:
        stats = _row_runs(c['mask'])
        med_runs = float(np.median([r for r, _ in stats]))
        wide_rows = [i for i, (_, mw) in enumerate(stats) if mw >= 8]
        top_third = sum(1 for i in wide_rows if i < 3)
        bot_third = sum(1 for i in wide_rows if i >= 4)
        if med_runs >= 1.5 or fill >= 0.42:
            return ('stack4', 0.8 if fill >= 0.42 else 0.5)
        if wide_rows and top_third > bot_third:
            return 'arrowUp', 0.7
        if wide_rows and bot_third > top_third:
            return 'arrowDown', 0.7
        if not wide_rows:
            return 'wave', 0.75
        return 'wave/arrow?', 0.4
    if h >= 40 and 16 < w <= 32:
        return ('ringTall', 0.8) if fill < 0.55 else ('blobTall?', 0.4)
    if 22 <= h < 40 and w <= 16:
        return f'stack{max(2, min(3, round(h / 13.5)))}', 0.7
    if w >= 28 and h <= 18 and -14 <= rel_y <= 14:
        return 'restMulti', 0.7
    if 14 <= w <= 30 and 16 <= h <= 30:
        return ('noteEllipse', 0.7) if fill < 0.6 else ('digitBig?', 0.4)
    if w <= 3 and h <= 16:
        return 'lineStub', 0.9
    if w <= 6 and h <= 6:
        return 'dot', 0.7
    if 7 <= w <= 13 and 9 <= h <= 20:
        mask = c['mask']
        top_h = max(3, int(h * 0.4))
        top_fill = mask[:top_h].mean()
        bot_max = max((mw for _, mw in _row_runs(mask)[3:]), default=0)
        if top_fill >= 0.6 and bot_max <= 5:
            return 'rest8', 0.7
        if fill >= 0.4:
            return 'digit', 0.6
        return 'mark?', 0.4
    return f'unk{int(w)}x{int(h)}', 0.3


# ── 拍位标定(验证态:真值和弦锚 × 和弦名行文字块,分块最小二乘)────────
# 印张 px/beat 逐系统不等宽、小节线检测混入音杆,故不用小节线串接。
# 每系统和弦名块数 = 连续真值和弦数(每个换和弦都有名牌),在指针附近
# 搜起点取残差最小的分块;拟合 px = a + b·beat(b 即 pxPerBeat)。

def find_bar_chain(cands):
    """从竖线候选里找最长等差链(小节线;间距容 ±12px)。"""
    if len(cands) < 2:
        return []
    from collections import Counter
    diffs = Counter()
    for i in range(len(cands)):
        for j in range(i + 1, len(cands)):
            d = cands[j] - cands[i]
            if 240 <= d <= 560:
                diffs[round(d / 16) * 16] += 1
    if not diffs:
        return []
    best_chain = []
    for S, _ in diffs.most_common(4):
        for x0 in cands:
            chain = [x0]
            while True:
                target = chain[-1] + S
                nxt = [c for c in cands if abs(c - target) <= 12]
                if not nxt:
                    break
                chain.append(min(nxt, key=lambda c: abs(c - target)))
            if len(chain) > len(best_chain):
                best_chain = chain
    return best_chain


def calibrate_from_gt(systems, gt_beats, gt_notes):
    """验证态标定:小节线等差链分段插值(印张逐小节不等宽,单一线性映射
    原理性不成立)。链首拍位二选一(首位小节线=floor(首个真值拍/4)*4 或
    再退一小节),用记号块-真值命中数投票。"""
    gt_sorted = sorted(set(gt_beats))
    lower_bound = 0.0
    for s_ in systems:
        marks = [c['x'] + c['w'] / 2 for c in s_['comps'] if c['w'] <= 30]
        chain = find_bar_chain([round(b) for b in s_['barlines']])
        if len(chain) < 3 or not marks:
            s_['grid'] = None
            continue
        best = None
        max_off = 4.0 * int((gt_sorted[-1] if gt_sorted else 108) / 4) + 4
        for off4 in range(int(lower_bound), int(max_off) + 1, 4):
            off = float(off4)
            def beat_at(x, off=off):
                if x <= chain[0]:
                    i = 0
                elif x >= chain[-1]:
                    i = len(chain) - 2
                else:
                    i = max(j for j in range(len(chain) - 1)
                            if chain[j] <= x)
                return off + 4.0 * (i + (x - chain[i]) /
                                    (chain[i + 1] - chain[i]))
            hits = 0
            for c in s_['comps']:
                if c['w'] > 30:
                    continue
                x = c['x'] + c['w'] / 2
                beat = beat_at(x)
                i = np.searchsorted(gt_sorted, beat)
                hit = False
                for j in (i - 1, i):
                    if (0 <= j < len(gt_sorted)
                            and abs(gt_sorted[j] - beat) <= 0.2):
                        hit = True
                        break
                if not hit:
                    continue
                # 弦线约束:组件 y 区间须罩住某同拍真值音的弦线
                lo_n = (c['y'] - s_['top'] + 3) / GAP
                hi_n = (c['y'] + c['h'] - s_['top'] - 3) / GAP
                lo_s, hi_s = max(1, int(np.floor(lo_n)) + 1), \
                    min(4, int(np.floor(hi_n)) + 1)
                for n in gt_notes:
                    if (abs(n['beat'] - beat) <= 0.2
                            and lo_s <= n['string'] <= hi_s):
                        hits += 1
                        break
            if best is None or hits > best[0]:
                best = (hits, off)
        if best is None or best[0] < 3:
            s_['grid'] = None
            continue
        hits, off = best
        s_['grid'] = {'chain': chain, 'off': off, 'resid': 0.0,
                      'startBeat': off, 'conf': 0.8, 'hits': hits}
        lower_bound = off + 4.0
    return systems


def beat_of(sys_, x):
    g = sys_.get('grid')
    if not g:
        return None
    chain, off = g['chain'], g['off']
    if x <= chain[0]:
        i = 0
    elif x >= chain[-1]:
        i = len(chain) - 2
    else:
        i = max(j for j in range(len(chain) - 1) if chain[j] <= x)
    return off + 4.0 * (i + (x - chain[i]) / (chain[i + 1] - chain[i]))


# ── 主流程 ──────────────────────────────────────────────────────────────

def census(pdf_path, gt_note_beats, gt_notes):
    doc = pdfium.PdfDocument(pdf_path)
    systems = []
    for pi in range(len(doc)):
        page = doc[pi]
        img = np.array(
            page.render(scale=SCALE).to_pil().convert('L'))
        dark = img < T_INK
        dark_line = img < T_LINE
        w = img.shape[1]
        for si, top in enumerate(find_systems(dark_line, w)):
            comps_tall = [c for c in band_components(dark, top, False)
                          if c['h'] >= 40]
            comps_small_all = band_components(dark, top, True)
            comps_small = [c for c in comps_small_all
                           if c['h'] < 40 and not any(
                               a['x'] - 3 <= c['x'] and
                               c['x'] + c['w'] <= a['x'] + a['w'] + 3 and
                               a['y'] - 3 <= c['y'] and
                               c['y'] + c['h'] <= a['y'] + a['h'] + 3
                               for a in comps_tall)]
            systems.append({
                'page': pi, 'index': si, 'top': float(top),
                'barlines': find_barlines(dark_line, top),
                'labels': find_chord_labels(dark_line, top),
                'comps': comps_tall + comps_small,
            })
    for s in systems:
        events = []
        for c in s['comps']:
            cls, conf = classify(c, s['top'])
            if cls in ('stem', 'lineStub'):
                continue  # 节奏杆/弦线残段不进事件表
            events.append({
                'cls': cls, 'conf': conf,
                'x': c['x'] + c['w'] / 2, 'y': c['y'],
                'w': c['w'], 'h': c['h'],
            })
        s['events'] = sorted(events, key=lambda e: e['x'])
    calibrate_from_gt(systems, gt_note_beats, gt_notes)
    for s in systems:
        for ev in s['events']:
            ev['beat'] = round(beat_of(s, ev['x']), 2) if s.get('grid') else None
        if s.get('grid'):
            s['startBeat'] = s['grid']['off']
    return systems


def line_span(ev):
    """事件覆盖的弦线区间(1..4),按 y 几何换算。"""
    top_line = ev['_staffTop']
    a = (ev['y'] - top_line + 3) / GAP
    b = (ev['y'] + ev['h'] - top_line - 3) / GAP
    lo, hi = max(1, int(np.floor(a)) + 1), min(4, int(np.floor(b)) + 1)
    return (lo, hi) if lo <= hi else (0, 0)


def diff(systems, gt):
    """普查 vs 真值:按类查准/查全。返回 (summary, matched_pairs)。"""
    # 真值事件(期望在印张可见的):
    strum_beats = {e['beat'] for e in gt['strums']}
    rest_ranges = [(e['beat'], e['beat'] + e['beats']) for e in gt['rests']]
    in_rest = lambda b: any(a <= b < z for a, z in rest_ranges)

    gt_notes = [n for n in gt['notes']
                if n['beat'] not in strum_beats and not in_rest(n['beat'])]
    max_gt_beat = max([n['beat'] for n in gt['notes']] +
                      [e['beat'] for e in gt['strums']] + [0.0])

    # 普查事件池(可代表发声位的类别)
    pool = []
    for s in systems:
        for ev in s['events']:
            ev['_staffTop'] = s['top']
            pool.append(ev)

    def near(ev, beat, tol=0.35):
        return ev['beat'] is not None and abs(ev['beat'] - beat) <= tol

    NOTE_CLS = {'mark?', 'digit', 'digitBig?', 'stack2', 'stack3', 'stack4',
                'noteEllipse'}
    used = set()
    # 音符查全
    hit_notes = 0
    misses = []
    cand = []
    matched_notes = []
    for n in gt_notes:
        for i, ev in enumerate(pool):
            if i in used or ev['cls'] not in NOTE_CLS or not near(ev, n['beat']):
                continue
            lo, hi = line_span(ev)
            if lo <= n['string'] <= hi:
                cand.append((abs(ev['beat'] - n['beat']), 'n', i, n))
    for d, _, i, n in sorted(cand, key=lambda t: t[0]):
        if i in used or n in misses and False:
            continue
        if any(m is n for m in matched_notes):
            continue
        used.add(i)
        matched_notes.append(n)
        hit_notes += 1
    misses = [n for n in gt_notes if not any(m is n for m in matched_notes)]
    # 音符查准(被认作音符位的普查事件有真值支撑)
    note_events = [(i, ev) for i, ev in enumerate(pool)
                   if ev['cls'] in NOTE_CLS and ev['beat'] is not None
                   and ev['beat'] <= max_gt_beat + 1]
    supported = sum(1 for i, ev in note_events
                    if any(abs(ev['beat'] - n['beat']) <= 0.35
                           and line_span(ev)[0] <= n['string'] <= line_span(ev)[1]
                           for n in gt_notes))
    # 扫弦/休止/震音
    def cls_match(gt_kind, ev):
        want = {'roll': ('wave',), 'strumDown': ('arrowDown', 'wave/arrow?'),
                'strumUp': ('arrowUp', 'wave/arrow?')}[gt_kind]
        return ev['cls'] in want

    scand = []
    for e in gt['strums']:
        for i, ev in enumerate(pool):
            if i in used or not cls_match(e['kind'], ev) or not near(ev, e['beat']):
                continue
            scand.append((abs(ev['beat'] - e['beat']), 's', i, e))
    matched_strums = []
    strum_hits = 0
    for d, _, i, e in sorted(scand, key=lambda t: t[0]):
        if i in used or any(m is e for m in matched_strums):
            continue
        used.add(i)
        matched_strums.append(e)
        strum_hits += 1
    rest_hits = sum(1 for e in gt['rests']
                    if any(ev['cls'] in ('rest8', 'restMulti', 'dot')
                           and ev['beat'] is not None
                           and abs(ev['beat'] - e['beat']) <= 0.4
                           for ev in pool))
    trem_hits = sum(1 for e in gt['tremolos']
                    if any(ev['cls'] == 'ringTall'
                           and ev['beat'] is not None
                           and abs(ev['beat'] - e['beat']) <= 0.6
                           for ev in pool))
    beyond = [ev for ev in pool if ev['beat'] is not None
              and ev['beat'] > max_gt_beat + 2
              and ev['cls'] not in ('stem', 'dot')]
    summary = {
        'gt_notes': len(gt_notes), 'note_recall': round(hit_notes / max(1, len(gt_notes)), 3),
        'note_events': len(note_events),
        'note_precision': round(supported / max(1, len(note_events)), 3),
        'gt_strums': len(gt['strums']), 'strum_recall': round(strum_hits / max(1, len(gt['strums'])), 3),
        'gt_rests': len(gt['rests']), 'rest_recall': round(rest_hits / max(1, len(gt['rests'])), 3),
        'gt_tremolos': len(gt['tremolos']), 'tremolo_recall': round(trem_hits / max(1, len(gt['tremolos'])), 3),
        'beyond_truth_events': len(beyond),
        'miss_examples': misses[:8],
    }
    return summary, beyond


def report_md(systems, gt, summary, beyond):
    max_gt = summary and max(
        [n['beat'] for n in gt['notes']] + [0.0])
    lines = ['# PDF 记号普查报告(gs-aini,工单41)', '',
             f'- 系统(谱表)总数:{len(systems)}',
             f'- 真值 diff:{json.dumps(summary, ensure_ascii=False)}', '']
    for s in systems:
        g = s.get('grid')
        head = (f"链首拍={g['off']:.0f},小节线链={len(g['chain'])}根,"
                f"记号命中={g['hits']}" if g else "未标定(无小节线链)")
        lines.append(f"## p{s['page']} 系统{s['index']}(top={int(s['top'])},{head})")
        lines.append('| 拍位 | 类别 | 弦线 | 尺寸 | 置信 |')
        lines.append('|---|---|---|---|---|')
        for ev in s['events']:
            ev['_staffTop'] = s['top']
            lo, hi = line_span(ev)
            beat = f"{ev['beat']:.2f}" if ev['beat'] is not None else '?'
            flag = ' ⚠超真值' if max_gt and ev['beat'] and ev['beat'] > max_gt + 2 else ''
            lines.append(f"| {beat} | {ev['cls']}{flag} | {lo}-{hi} "
                         f"| {ev['w']:.0f}x{ev['h']:.0f} | {ev['conf']} |")
        lines.append('')
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('pdf')
    ap.add_argument('--gt', help='真值 JSON(dump_score_sheet_json.dart 导出)')
    ap.add_argument('--report', help='markdown 报告输出路径')
    ap.add_argument('--json', help='普查事件 JSON 输出路径')
    args = ap.parse_args()

    gt = None
    if args.gt:
        with open(args.gt) as f:
            gt = json.load(f)
        systems = census(args.pdf,
                     sorted({n['beat'] for n in gt['notes']} |
                            {e['beat'] for e in gt['strums']}),
                     gt['notes'] if gt else [])
    slim = [{k: v for k, v in s.items() if k not in ('comps', 'grid', 'labels')} for s in systems]
    if args.json:
        with open(args.json, 'w') as f:
            json.dump(slim, f, ensure_ascii=False, indent=1)

    if gt:
        summary, beyond = diff(systems, gt)
        print(json.dumps(summary, ensure_ascii=False, indent=1))
    else:
        summary, beyond = None, []

    if args.report:
        with open(args.report, 'w') as f:
            f.write(report_md(systems, gt, summary, beyond))
    if not args.report and not args.json:
        for s in slim:
            print(f"p{s['page']} 系统{s['index']} 起拍{s['startBeat']:.0f} "
                  f"事件{len(s['events'])}")


if __name__ == '__main__':
    sys.exit(main())
