"""TAB 伴奏层识别(工单50):字形几何 → OCR 品位数字 → 节奏/记号解释 → 草稿。

输入=工单48 split 产物(tab 层裁图 + 谱表几何 + 小节骨架);证据链逐符号
携带(ADR-0009),拍位=小节内按「逐 attack 时值累加」得出——x 只定小节
归属与音序,不做 px→拍标定(工单41 撞墙点照守)。× 印记照读谱法不落音,
落证据(票面);和弦堆品位须查和弦指形,那是校对台(51)的活。

字形档案(300dpi,g≈19.2,gs-aini 像素考古实测;单表见
docs/research/2026-10-28-gs-aini-300dpi-geometry.md,scale3 档案见 census):
- 品位数字 ~13×14,圆心**落在自己的弦线上**(cy≈line_y±0.35g;简谱数字
  在行下空间,TAB 数字压线,两套坐标不同)。谱号区 T-A-B 竖排字母与拍号
  「4/4」在行间空间,被「压线」判据天然排除。线行会把压线字形切开,组件
  前先竖向闭运算桥接(核 1×7,线行切缝 ≤5 行)。
- × 印记 ~14×19,两笔交叉,同样压线;和弦堆 = 同 x 多弦 × 纵连(行距 1g,
  桥接后成整块,round(h/g) 折合弦数)。× 的 OCR 读 V/C/y 等废字,数字
  白名单先分流,不冲突。
- 符杆 = 细竖线(2-4px)自音位下行出谱底;符尾 = 杆末左下垂楔(16×59);
  符杠 = 谱下横杠(厚 ≤0.4g)按「盖过杆 x」逐杆计数;附点 = 数字右侧小点。
- 休止:八分 = 实心点 15×8 + 左下拖尾钩(桥接后 15×25 整块,上段致密);
  全小节 = 20×6 扁杠挂在②线下。
- 记号:卷弦波浪 = 8-9px 宽竖向蛇形贯穿 ≥2.1g(粗于符杆 4px);扫弦箭头
  = 4px 细杆贯穿 + 端部箭头(方向一期不读,杆作 attack 记号);小节线与
  箭头同形,靠「x 距小节界 ≤0.15g 且近旁无音位」排除;滑音 = 两品位数字
  间 26×7 斜杠(弦线高度);震音 = 瘦椭圆 h≥2.3g 罩弦;长音椭圆 h
  1.0-2.3g(证据);延音括线 = ④线下空心矩形(证据不改 attack,真值模型
  本就不记持续)。
- 逐小节不等宽、×/波浪印张右移 ~25px(census ±0.3 拍锚位漂移)——拍位
  累加不吃 x 距离,漂移只影响密段 x 序,闭合警告显形。
"""

import datetime
import json
from dataclasses import dataclass, field
from pathlib import Path

from . import __version__
from .split import INK_GRAY_MAX

# ── 字形几何(单位=g,即弦距;实测档案见模块 docstring)─────────────────

DIGIT_W = (0.45, 1.1)       # 品位数字宽(实测 11-18px)
DIGIT_H = (0.55, 0.95)      # 数字高(实测 14-15px)
LINE_HUG = 0.35             # 数字/× 圆心距弦线上限(压线;行间=拍号区)
X_W = (0.55, 0.95)          # × 印记宽(13-15px)
X_H = (0.75, 1.25)          # × 印记高(17-21px;与 rest8 下沿相接,致密度分流)
X_STACK_H = (1.3, 4.2)      # 桥接后的 × 堆高(每弦 1g)
ROLL_W = (0.3, 0.52)        # 卷弦波浪宽(8-9px;上限避开数字+杆合体柱)
ROLL_H_MIN = 2.1            # 波浪贯穿高下限(实测 55-70px)
SHAFT_W_MAX = 0.28          # 箭头/小节线杆宽上限(4px)
SHAFT_H_MIN = 2.4           # 贯穿杆最短高(①到④ 3g,线行删除后实测余 52px)
REST8_H = (1.1, 1.7)        # 八分休止桥接块高(点 15×8+尾 7×12 → 15×25)
REST8_W = (0.55, 1.0)
REST8_TOP_FILL = 0.55       # 上三分之一致密度(点实心;× 上段两细笔稀)
REST_WHOLE_W = (0.7, 1.7)   # 全小节休止 20×6
REST_WHOLE_H = (0.1, 0.45)
REST_WHOLE_ZONE = (0.05, 0.7)   # 挂点:②线下方此比例带内
SLIDE_W = (0.9, 1.8)        # 滑音斜杠 26×7
SLIDE_H = (0.15, 0.55)
SLIDE_HUG = 0.45            # 斜杠圆心压线容差
TREMOLO_H_MIN = 2.3         # 震音瘦椭圆高(实测 59px 罩四弦)
ELLIPSE_H = (1.0, 2.3)      # 长音椭圆高
ELLIPSE_W = (0.9, 2.1)   # 下限避开 × 堆(0.7-0.85g 宽)
HOLLOW_FILL = 0.55          # 空心判据:area/(w·h) 低于此
BRACKET_W_MIN = 1.5         # 延音括线:④线下空心矩形(实测 53×59)
BRACKET_H = (2.0, 4.2)
BRACKET_TOP_ZONE = 0.35     # 括线顶距④线上方此比例内
STEM_W_MAX = 0.26           # 符杆宽(2-4px)
STEM_H_MIN = 0.9
FLAG_W = (0.35, 1.3)        # 符尾楔 16×59(下限挡 2px 杆尾)
FLAG_H = (1.3, 3.4)
BEAM_H_MAX = 0.4            # 符杠厚(实测 2-4px)
BEAM_W_MIN = 0.8
BEAM_ZONE = (0.1, 3.6)      # 符杠带:④线下此比例域
AUG_DOT = 0.4               # 附点尺寸上限
AUG_GAP = (0.1, 0.95)       # 附点心距数字右缘(比例 g)
AUG_CY = 0.45               # 附点与数字 cy 容差
ATTACK_MERGE = 0.45         # 同一 attack 的音位/事件符号 x 簇间距上限
STEM_REACH = 0.55           # 符杆归属 attack 的 x 距离上限
STAFF_TOP_PAD = 1.7         # 识别域上界:①线上此比例
STAFF_BOT_PAD = 3.7         # 识别域下界:④线下此比例
COMP_MIN_AREA = 12          # 组件最小面积(与 split/melody 同源)
BRIDGE_KERNEL = (5, 7)     # 闭运算核(宽,高):线行切缝 ≤5 行 + 字形斜笔
                            # 错位 ≤4px(数字斜杠/断杆);波浪错位 4px 由
                            # rollseg 链接管,不靠闭运算
COLUMN_NARROW_FRAC = 0.3    # 竖柱行段「窄行」宽上限(杆 2-4px;实测档案)
COLUMN_HEAD_MIN = 0.5       # 数字柱首段 W 行高下限(箭头头 ~0.26g 在其下)
COLUMN_HEAD_MAX = 1.3       # 数字柱首段 W 行高上限(超 = × 堆/连体)
COLUMN_GLYPH_MIN_W = 0.55   # 字形段最宽行下限(卷弦斜坡峰值 9px 过不了)
BARLINE_NEAR = 0.15         # 杆距小节界此比例内 → barline
BARLINE_COMPANY = 0.8       # 「近旁有音位」的距离(印张 ×/波浪右移 25px)
MAX_SUBS = 2                # 十六分以下不考(落警告)
DEFAULT_REST8 = 0.5         # 八分休止时值(模板即八分)
DEFAULT_METER = 4.0         # 页眉读不出时的假定拍号(meter_assumed=True)
CROP_PAD = 2                # split 裁图外扩 px(_save_crop 口径)
SCHEMA = "ukeflow.workbench.tab/1"


@dataclass(frozen=True)
class Sym:
    """一个组件的分类结果(页坐标 px,bbox 证据)。"""

    role: str               # digit|x_mark|x_stack|roll|shaft|barline|rest8|
                            # rest_whole|slide|tremolo|ellipse|bracket|stem|
                            # flag|beam|dot|other
    x: float
    y: float
    w: float
    h: float
    label: str | None = None    # digit 的 OCR 读数;× 读数留证
    conf: float = 0.0

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2

    @property
    def x1(self) -> float:
        return self.x + self.w

    @property
    def y1(self) -> float:
        return self.y + self.h

    def moved(self, **kw) -> "Sym":
        d = {"role": self.role, "x": self.x, "y": self.y, "w": self.w,
             "h": self.h, "label": self.label, "conf": self.conf}
        d.update(kw)
        return Sym(**d)


def staff_components(gray, line_ys, top, bottom, gap, x0, x1):
    """谱带组件=(内部带, 谱下带)两段。

    内部带 [top−1.7g, ④+0.55g]:删全部四条线行(300dpi 实测线芯 <195,墨阈
    分不开线与字形)后 3×7 闭运算桥接切缝与 ≤2px 斜笔错位,取连通域。
    谱下带 [④+0.55g, ④+3.7g]:无线行,原始连通域(符尾/符杠/延音括线;
    与谱内符号在 ④+0.55g 处切开,括线顶边贴④线被删、不粘连符杆)。
    返回 (interior, below),各为 [(x, y, w, h, area)](crop px)。"""
    import cv2
    import numpy as np

    fourth = line_ys[3]
    y0 = max(0, int(top - STAFF_TOP_PAD * gap))
    ymid = min(gray.shape[0], int(fourth + 0.55 * gap))
    y1 = min(gray.shape[0], int(bottom + STAFF_BOT_PAD * gap))
    xa = max(0, int(x0 - gap))
    xb = min(gray.shape[1], int(x1 + gap))
    ink = (np.asarray(gray) < INK_GRAY_MAX).astype(np.uint8)
    for ly in line_ys:
        ink[max(0, int(ly) - 2):int(ly) + 3, :] = 0
    zone = np.zeros_like(ink)
    zone[y0:ymid, xa:xb] = ink[y0:ymid, xa:xb]
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, BRIDGE_KERNEL)
    dilated = cv2.dilate(zone, kernel)
    n, labels, _, _ = cv2.connectedComponentsWithStats(dilated)
    interior = []
    for i in range(1, n):
        mask = (labels[y0:ymid, xa:xb] == i) & (zone[y0:ymid, xa:xb] > 0)
        ys, xs = np.nonzero(mask)
        if len(ys) < COMP_MIN_AREA:
            continue
        interior.append((int(xs.min() + xa), int(ys.min() + y0),
                         int(xs.max() - xs.min() + 1),
                         int(ys.max() - ys.min() + 1), len(ys)))
    zone2 = np.zeros_like(ink)
    zone2[ymid:y1, xa:xb] = ink[ymid:y1, xa:xb]
    n, _, stats, _ = cv2.connectedComponentsWithStats(zone2)
    below = [tuple(int(v) for v in stats[i]) for i in range(1, n)
             if stats[i][4] >= COMP_MIN_AREA]
    return interior, below


def classify_symbols(interior, below, gap, line_ys, x_start, gray, ocr):
    """两段组件 → 角色。内部带:尺寸/位置分箱,压线小件交 OCR 白名单分流
    digit / x_mark;波浪蛇形因折线横向错位被线行切碎 → rollseg 链回合体。
    谱下带:符尾/符杠/延音括线 + 细杆续段(stem)。系统头的谱号区(T-A-B
    字母/拍号 4/4,行间空间、x < x_start+3.2g)整体归 other 证据。"""
    syms = []
    second = line_ys[1]
    fourth = line_ys[3]
    pending = []
    for x, y, w, h, area in interior:
        cx, cy = x + w / 2, y + h / 2
        y1c = y + h
        rel = h / gap
        near_line = min(abs(cy - ly) for ly in line_ys) <= LINE_HUG * gap
        digit_size = (DIGIT_W[0] * gap <= w <= DIGIT_W[1] * gap
                      and DIGIT_H[0] * gap <= h <= DIGIT_H[1] * gap)
        x_size = (X_W[0] * gap <= w <= X_W[1] * gap
                  and X_H[0] * gap <= h <= X_H[1] * gap)
        stack_size = (X_STACK_H[0] * gap <= h <= X_STACK_H[1] * gap
                      and X_W[0] * gap <= w <= X_W[1] * gap * 1.4)
        header_zone = cx < x_start + 3.2 * gap
        # 休止是紧凑定形件,先于竖柱分解判(否则点+尾钩被拆成 glyph+杆)
        sym = None
        if (REST_WHOLE_W[0] * gap <= w <= REST_WHOLE_W[1] * gap
                and REST_WHOLE_H[0] * gap <= h <= REST_WHOLE_H[1] * gap
                and area >= 0.75 * w * h
                and second + REST_WHOLE_ZONE[0] * gap <= cy
                <= second + REST_WHOLE_ZONE[1] * gap):
            sym = Sym("rest_whole", float(x), float(y), float(w), float(h))
        elif (REST8_H[0] * gap <= h <= REST8_H[1] * gap
                and REST8_W[0] * gap <= w <= REST8_W[1] * gap):
            top_fill = _top_third_fill(gray, x, y, w, h)
            sym = Sym("rest8" if top_fill >= REST8_TOP_FILL else "other",
                      float(x), float(y), float(w), float(h))
        if sym is not None:
            syms.append(sym)
            continue
        # 竖柱组件(TAB 同拍列:数字+杆+低弦 × 物理粘连,或箭头+头)先行
        # 分辨:箭头(长窄杆+谱外端部加宽)→ strumUp/Down;数字柱(头部
        # 致密)→ 分段拆 glyph(pending)/杆;其余(波浪/×堆)走原分类
        if rel >= 1.5 and w <= 1.4 * gap:
            verdict = _tall_column(gray, x, y, w, h, gap, line_ys)
            if verdict is not None:
                kind, payload = verdict
                if kind == "strum":
                    syms.append(Sym(payload, float(x), float(y),
                                    float(w), float(h)))
                    continue
                if kind == "roll":
                    syms.append(Sym("roll", float(x), float(y),
                                    float(w), float(h)))
                    continue
                for (bx, by, bw, bh, part) in payload:
                    if part == "stem":
                        syms.append(Sym("stem", float(bx), float(by),
                                        float(bw), float(bh)))
                        continue
                    if part == "other":
                        syms.append(Sym("other", float(bx), float(by),
                                        float(bw), float(bh)))
                        continue
                    bcy = by + bh / 2
                    blob_line = min(abs(bcy - ly) for ly in line_ys) \
                        <= LINE_HUG * gap
                    g_size = (DIGIT_W[0] * gap <= bw <= DIGIT_W[1] * gap
                              and DIGIT_H[0] * gap <= bh <= DIGIT_H[1] * gap)
                    x_sz = (X_W[0] * gap <= bw <= X_W[1] * gap
                            and X_H[0] * gap <= bh <= X_H[1] * gap)
                    if (g_size or x_sz) and blob_line \
                            and not (bx < x_start + 3.2 * gap):
                        syms.append(Sym("pending", float(bx), float(by),
                                        float(bw), float(bh)))
                        pending.append(len(syms) - 1)
                    else:
                        syms.append(Sym("other", float(bx), float(by),
                                        float(bw), float(bh)))
                continue
        sym = None
        if (digit_size or x_size) and near_line:
            fill = area / (w * h)
            slim = (w <= 0.55 * gap and h >= DIGIT_H[0] * gap
                    and area >= 0.5 * w * h)      # '1' 细杆
            if digit_size and (fill >= 0.42 or slim):
                sym = Sym("pending", float(x), float(y), float(w), float(h))
                pending.append(len(syms))
            elif x_size and not (fill >= 0.42 or slim):
                sym = Sym("pending", float(x), float(y), float(w), float(h))
                pending.append(len(syms))
            else:
                sym = Sym("other", float(x), float(y), float(w), float(h))
        elif (ROLL_W[0] * gap <= w <= ROLL_W[1] * gap
                and 0.8 * gap <= h < ROLL_H_MIN * gap):
            sym = Sym("rollseg", float(x), float(y), float(w), float(h))
        elif rel >= ROLL_H_MIN and ROLL_W[0] * gap <= w <= ROLL_W[1] * gap:
            sym = Sym("roll", float(x), float(y), float(w), float(h))
        elif stack_size:
            sym = Sym("x_stack" if not header_zone else "other",
                      float(x), float(y), float(w), float(h))
        elif w <= STEM_W_MAX * gap and h >= STEM_H_MIN * gap:
            sym = Sym("stem", float(x), float(y), float(w), float(h))
        elif (STEM_W_MAX * gap < w <= 1.3 * gap and h >= 1.3 * gap
                and y1c >= fourth + 0.2 * gap):
            # 符杆+符尾合体(楔挂杆末,物理相连;闭运算不切):记 flagstem,
            # 时值层按「杆+1 尾」计
            sym = Sym("flagstem", float(x), float(y), float(w), float(h))
        elif rel >= SHAFT_H_MIN and w <= SHAFT_W_MAX * gap:
            sym = Sym("shaft", float(x), float(y), float(w), float(h))
        elif (SLIDE_W[0] * gap <= w <= SLIDE_W[1] * gap
                and SLIDE_H[0] * gap <= h <= SLIDE_H[1] * gap
                and min(abs(cy - ly) for ly in line_ys) <= SLIDE_HUG * gap):
            sym = Sym("slide", float(x), float(y), float(w), float(h))
        elif (area < HOLLOW_FILL * w * h and ELLIPSE_W[0] * gap <= w
                <= ELLIPSE_W[1] * gap):
            if rel >= TREMOLO_H_MIN:
                sym = Sym("tremolo", float(x), float(y), float(w), float(h))
            elif ELLIPSE_H[0] * gap <= h <= ELLIPSE_H[1] * gap:
                sym = Sym("ellipse", float(x), float(y), float(w), float(h))
        if sym is None:
            if w <= AUG_DOT * gap and h <= AUG_DOT * gap:
                sym = Sym("dot", float(x), float(y), float(w), float(h))
            else:
                sym = Sym("other", float(x), float(y), float(w), float(h))
        syms.append(sym)
    # OCR 白名单分流(先于 rollseg 链:链会重排列表,pending 下标会失效)
    ocr_img = _inpainted(gray, line_ys) if pending else gray
    labels = _ocr_labels(ocr, ocr_img, pending, syms)
    for i, (label, conf) in zip(pending, labels):
        s = syms[i]
        is_digit = label is not None and len(label) == 1 \
            and label in "0123456789"
        if is_digit and _two_stroke_top(ocr_img, s.x, s.y, s.w, s.h):
            # 顶部三行多两笔分叉 = × 印记被穿线读成数字(0/7/8 实测),归 ×
            syms[i] = s.moved(role="x_mark", label=label, conf=conf)
        elif is_digit:
            syms[i] = s.moved(role="digit", label=label, conf=conf)
        else:
            syms[i] = s.moved(role="x_mark", label=label, conf=conf)
    syms = _chain_rollsegs(syms, gap)
    # 谱下带:符尾/符杠/延音括线/细杆续段
    for x, y, w, h, area in below:
        rel = h / gap
        if w >= BRACKET_W_MIN * gap and BRACKET_H[0] * gap <= h \
                <= BRACKET_H[1] * gap and area < HOLLOW_FILL * w * h:
            sym = Sym("bracket", float(x), float(y), float(w), float(h))
        elif h <= BEAM_H_MAX * gap and w >= BEAM_W_MIN * gap:
            sym = Sym("beam", float(x), float(y), float(w), float(h))
        elif (FLAG_W[0] * gap <= w <= FLAG_W[1] * gap
                and FLAG_H[0] * gap <= h <= FLAG_H[1] * gap
                and area >= 0.3 * w * h):
            sym = Sym("flag", float(x), float(y), float(w), float(h))
        elif w <= STEM_W_MAX * gap and h >= 0.5 * gap:
            sym = Sym("stem", float(x), float(y), float(w), float(h))
        else:
            sym = Sym("other", float(x), float(y), float(w), float(h))
        syms.append(sym)
    return syms


def _two_stroke_top(gray, x, y, w, h):
    """pending 字形整高的墨行是否多为两笔分叉(≥0.4×高)。

    × = 双笔交叉,上半与下半的行都是两段;数字的空心底(2 的弧/8 的腰)
    只有零星两支行。用于兜住「× 被穿线读成数字」(0/7/8 实测)。"""
    import numpy as np

    ya, yb = max(0, int(y)), max(0, int(y + h))
    xa, xb = max(0, int(x)), int(x + w)
    win = np.asarray(gray)[ya:yb, xa:xb] < INK_GRAY_MAX
    two = 0
    for row in win:
        xs = np.flatnonzero(row)
        if len(xs) == 0:
            continue
        if (np.diff(xs) > 2).any():
            two += 1
    return two >= 0.4 * h


def _chain_rollsegs(syms, gap):
    """rollseg 竖向链(缝 ≤0.45g、心距 ≤0.4g)→ 合体;总高 ≥ROLL_H_MIN →
    roll,否则归 other 证据(不静默丢)。"""
    segs = [s for s in syms if s.role == "rollseg"]
    rest = [s for s in syms if s.role != "rollseg"]
    segs.sort(key=lambda s: (s.x, s.y))
    groups = []
    for s in segs:
        placed = False
        for g in groups:
            if any(0 <= t.y - (u.y + u.h) <= 0.45 * gap
                   or 0 <= u.y - (t.y + t.h) <= 0.45 * gap
                   for t in g for u in [s]) \
                    and any(abs(t.cx - s.cx) <= 0.4 * gap for t in g):
                g.append(s)
                placed = True
                break
        if not placed:
            groups.append([s])
    out = list(rest)
    for g in groups:
        x0 = min(s.x for s in g)
        y0 = min(s.y for s in g)
        x1 = max(s.x1 for s in g)
        y1 = max(s.y1 for s in g)
        role = "roll" if (y1 - y0) >= ROLL_H_MIN * gap else "other"
        out.append(Sym(role, x0, y0, x1 - x0, y1 - y0))
    return out


def _row_widths(gray, x, y, w, h, line_ys):
    """组件窗口的行宽剖面:行 → [x0..x1] 跨度;-2 = 线行删除带,-1 = 真空行。"""
    import numpy as np

    ya, yb = max(0, int(y)), int(y + h)
    xa, xb = max(0, int(x)), int(x + w)
    win = (np.asarray(gray)[ya:yb, xa:xb] < INK_GRAY_MAX).copy()
    bands = []
    for ly in line_ys:
        lo, hi = int(ly) - 2 - ya, int(ly) + 3 - ya
        if hi > 0 and lo < yb - ya:
            win[max(0, lo):max(0, hi), :] = False
            bands.append((max(0, lo), min(yb - ya, hi)))
    out = []
    for i, row in enumerate(win):
        if any(a <= i < b for a, b in bands):
            out.append(-2)
            continue
        xs = np.flatnonzero(row)
        out.append((xs[-1] - xs[0] + 1) if len(xs) else -1)
    return out


def _tall_column(gray, x, y, w, h, gap, line_ys):
    """竖高柱三分:(「strum」,方向) | (「parts」,段列表) | None。

    判据序(工单50 实测剖面):
    a. 数字柱:首段 W 行高 ∈ [0.5g, 1.3g] 且段内最宽 ≥0.55g、其下有
       ≥0.3g 窄行段(杆)→ 行段分解:字形段(glyph → pending,OCR 分
       digit/×)+ 杆段(stem)+ 碎段(other 证据保留);
    b. 箭头:长窄杆段(连续 ≤0.3g 行 ≥0.3×h)+ 单端加宽段整体在谱线带外
       (①线−0.2g 上=上扫;④线+0.3g 下=下扫);
    c. 卷弦:细柱(w ≤0.52g)体宽振荡(std ≥0.45,3-5px 蛇形)贯穿 ≥2.1g;
    d. 其余(× 堆/纯杆/细杆)→ None 走原分类路径。
    """
    widths = _row_widths(gray, x, y, w, h, line_ys)
    real = [v for v in widths if v >= 0]
    if not real or len(real) < 8:
        return None
    n = len(real)
    n_lim = COLUMN_NARROW_FRAC * gap
    # 行段:W(>0.3g)/N(≤0.3g);-2(线带)延续段,-1(真空)断段
    runs = []
    for i, wd in enumerate(widths):
        if wd == -2:
            if runs:
                runs[-1][2] = i + 1
            continue
        if wd == -1:
            continue
        k = "N" if wd <= n_lim else "W"
        if runs and runs[-1][0] == k:
            runs[-1][2] = i + 1
            runs[-1][3] = max(runs[-1][3], wd)
        else:
            runs.append([k, i, i + 1, wd])
    # a. 数字柱:首个 W 段够高够宽 + 其后有杆段
    first_w = next((r for r in runs if r[0] == "W"), None)
    has_stem = any(r[0] == "N" and r[2] - r[1] >= int(0.3 * gap)
                   for r in runs)
    if first_w is not None and has_stem and w > ROLL_W[1] * gap \
            and int(COLUMN_HEAD_MIN * gap) <= first_w[2] - first_w[1] \
            <= int(COLUMN_HEAD_MAX * gap) \
            and first_w[3] >= COLUMN_GLYPH_MIN_W * gap:
        parts, i = [], 0
        while i < len(runs):
            k, a, b, mw = runs[i]
            if k == "W":
                j, total, wmax = i, b - a, mw
                while j + 2 < len(runs) and runs[j + 1][0] == "N" \
                        and runs[j + 2][0] == "W" \
                        and runs[j + 1][2] - runs[j + 1][1] \
                        <= int(0.45 * gap) \
                        and total + (runs[j + 1][2] - runs[j + 1][1]) \
                        + (runs[j + 2][2] - runs[j + 2][1]) \
                        <= int(1.3 * gap):
                    total += (runs[j + 1][2] - runs[j + 1][1]) \
                        + (runs[j + 2][2] - runs[j + 2][1])
                    wmax = max(wmax, runs[j + 2][3])
                    j += 2
                if wmax >= COLUMN_GLYPH_MIN_W * gap \
                        and total >= int(COLUMN_HEAD_MIN * gap):
                    parts.append((x, y + runs[i][1], w, total, "glyph"))
                else:
                    parts.append((x, y + a, w, total, "other"))
                i = j + 1
            else:
                seg = b - a
                if seg >= int(0.3 * gap):
                    parts.append((x, y + a, w, seg, "stem"))
                elif seg >= int(0.2 * gap):
                    parts.append((x, y + a, w, seg, "other"))
                i += 1
        if any(g[4] == "glyph" for g in parts):
            return ("parts", parts)
    # c. 卷弦:细柱体宽振荡(蛇形周期,3-5px 交替;箭头杆体恒定 std=0)
    if w <= ROLL_W[1] * gap and h >= ROLL_H_MIN * gap:
        body = real[int(0.25 * n):]
        mean = sum(body) / len(body)
        bstd = (sum((v - mean) ** 2 for v in body) / len(body)) ** 0.5
        if bstd >= 0.45 and mean <= 0.35 * gap:
            return ("roll", None)
    # b. 箭头:长窄杆段 + 端部加宽(数字柱已被 a 拦下;× 堆无长窄段)
    best_len = best_start = run = 0
    in_narrow = False
    for i, wd in enumerate(widths):
        if wd < 0:
            if in_narrow:
                run += 1
                if run > best_len:
                    best_len, best_start = run, i - run + 1
            continue
        if wd <= n_lim:
            run = run + 1 if in_narrow else 1
            in_narrow = True
            if run > best_len:
                best_len, best_start = run, i - run + 1
        else:
            run, in_narrow = 0, False
    if best_len >= 0.3 * h:
        tops = [ly - y for ly in line_ys]
        y1_line, y4_line = tops[0], tops[3]
        top_idx = [i for i, v in enumerate(widths[:best_start]) if v >= 0]
        bot_idx = [i for i, v in enumerate(widths) if v >= 0
                   and i >= best_start + best_len]
        if top_idx and top_idx[-1] <= y1_line + 0.25 * gap \
                and max(widths[i] for i in top_idx) >= 0.45 * gap:
            return ("strum", "strumUp")
        if bot_idx and bot_idx[0] >= y4_line - 0.2 * gap \
                and max(widths[i] for i in bot_idx) >= 0.45 * gap:
            return ("strum", "strumDown")
    return None


def _inpainted(gray, line_ys):
    """线行逐列线性插值回填:每条线带 [ly−2, ly+3) 由带外上下相邻行插值,
    供 OCR 读穿线数字(镜面复制会把 ①8 复制成 S;黑线穿字被读成 6/7)。"""
    import numpy as np

    out = np.asarray(gray).astype(np.float32)
    for ly in line_ys:
        lo, hi = max(0, int(ly) - 2), min(out.shape[0], int(ly) + 3)
        if hi - lo <= 0 or lo - 1 < 0 or hi >= out.shape[0]:
            continue
        top, bot = out[lo - 1], out[hi]
        n = hi - lo
        for i in range(n):
            t = (i + 1) / (n + 1)
            out[lo + i] = top * (1 - t) + bot * t
    return out.round().astype(np.uint8)


def _top_third_fill(gray, x, y, w, h):
    """组件上三分之一墨密度(八分休止的点实心;× 上段两细笔稀疏)。"""
    import numpy as np

    ya, yb = max(0, int(y)), max(0, int(y + h / 3))
    win = np.asarray(gray)[ya:yb, max(0, int(x)):int(x + w)]
    if win.size == 0:
        return 0.0
    return float((win < INK_GRAY_MAX).mean())


def _ocr_labels(ocr, gray, pending_idx, syms):
    """pending 组件批量 OCR;无 ocr(纯几何模式)给 (None, 0) 占位。"""
    from .melody import Glyph

    if not pending_idx:
        return []
    if ocr is None or not hasattr(ocr, "digit_labels"):
        return [(None, 0.0)] * len(pending_idx)
    glyphs = [Glyph("c", syms[i].x, syms[i].y, syms[i].w, syms[i].h)
              for i in pending_idx]
    return ocr.digit_labels(gray, glyphs)


def drop_bound_barlines(syms, bounds_x, gap):
    """贯穿杆落在小节界 ±0.15g 且 ±0.8g 内无音位 → barline(非箭头)。

    印张 ×/波浪右移 ~25px 仍在 0.8g 内,不误伤;骑在小节界上的无伴随之杆
    无演奏信息,归 barline 证据。"""
    company_roles = {"digit", "x_mark", "x_stack", "roll", "rest8", "tremolo"}
    out = []
    for s in syms:
        if s.role in ("shaft", "stem") and s.h >= 2.4 * gap:
            near = any(abs(s.cx - bx) <= BARLINE_NEAR * gap for bx in bounds_x)
            company = any(o.role in company_roles
                          and abs(o.cx - s.cx) <= BARLINE_COMPANY * gap
                          for o in syms)
            if near and not company:
                out.append(s.moved(role="barline"))
                continue
        out.append(s)
    return out


def _direct_strums(syms, gap):
    """贯穿杆端部有加宽小件(箭头头)= 扫弦箭头,定向:strumUp/strumDown。

    头 = other 角色小件,水平盖过杆心、竖向贴杆端(±0.3g);两端都有或
    都没有 → 保持 shaft(证据,方向未读)。"""
    heads = [s for s in syms if s.role == "other"
             and s.w <= 0.8 * gap and s.h <= 0.7 * gap]
    out = []
    for s in syms:
        if s.role != "shaft":
            out.append(s)
            continue
        top = bottom = False
        for hd in heads:
            if abs(hd.cx - s.cx) > 0.35 * gap:
                continue
            if abs(hd.y1 - s.y) <= 0.3 * gap:
                top = True
            if abs(hd.y + hd.h - s.y1) <= 0.3 * gap:
                bottom = True
        if top and not bottom:
            out.append(s.moved(role="strumUp"))
        elif bottom and not top:
            out.append(s.moved(role="strumDown"))
        else:
            out.append(s)
    return out


# ── attack 聚簇与节奏解释 ─────────────────────────────────────────────

PITCH_ROLES = ("digit", "x_mark", "x_stack")
EVENT_ROLES = ("rest8", "rest_whole", "roll")
RHYTHM_ROLES = ("stem", "flagstem", "flag", "beam", "dot")
EVIDENCE_ROLES = ("slide", "bracket", "ellipse", "tremolo", "barline", "other")


@dataclass
class Attack:
    """一个发音点:音位/事件簇 + 时值读数(页坐标 px,bbox 证据)。"""

    x0: float
    x1: float
    digits: list = field(default_factory=list)     # [Sym]
    x_marks: list = field(default_factory=list)    # [Sym](×/×堆,证据)
    events: list = field(default_factory=list)     # [Sym](rest8/roll/shaft)
    rhythm: list = field(default_factory=list)     # [Sym](杆/尾/杠/点)
    bracket: bool = False                          # 延音括线挂靠(四分攻读数)
    duration: float | None = None
    subs: int = 0                                  # 符尾+符杠层数
    warnings: list = field(default_factory=list)

    @property
    def cx(self) -> float:
        return (self.x0 + self.x1) / 2


def cluster_attacks(syms, gap):
    """音位/事件符号按 x(隙 ≤ATTACK_MERGE·g)聚 attack;返回 (attacks,
    evidence)。节奏符号(杆/尾/杠/点)与延音括线按簇心距离挂靠——括线
    挂靠用于「四分攻+延音括线」读数(工单50 实测:× 拨弦/旋律长音印张
    不画符尾,画括线,攻时值=四分)。slide 等不入簇,直接落 evidence。"""
    anchors = sorted((s for s in syms
                      if s.role in PITCH_ROLES or s.role in EVENT_ROLES
                      or s.role in ("shaft", "strumUp", "strumDown")),
                     key=lambda s: s.cx)
    rhythm = [s for s in syms if s.role in RHYTHM_ROLES]
    brackets = [s for s in syms if s.role == "bracket"]
    clusters = []
    for s in anchors:
        if clusters and s.cx - clusters[-1]["x1"] <= ATTACK_MERGE * gap:
            c = clusters[-1]
            c["x1"] = max(c["x1"], s.x1)
            c["syms"].append(s)
        else:
            clusters.append({"x0": s.x, "x1": s.x1, "syms": [s]})
    attacks = []
    for c in clusters:
        cx = (c["x0"] + c["x1"]) / 2
        att = Attack(c["x0"], c["x1"])
        for s in c["syms"]:
            if s.role == "digit":
                att.digits.append(s)
            elif s.role in ("x_mark", "x_stack"):
                att.x_marks.append(s)
            else:
                att.events.append(s)
        # 杆/尾/点按簇心距挂;符杠按跨度相交(一根杠盖多 attack,逐 attack 计层)
        att.rhythm = [r for r in rhythm
                      if abs(r.cx - cx) <= STEM_REACH * gap
                      or (r.role == "beam" and r.x < c["x1"] + 0.2 * gap
                          and r.x1 > c["x0"] - 0.2 * gap)]
        att.bracket = any(abs(b.cx - cx) <= STEM_REACH * gap
                          for b in brackets)
        attacks.append(att)
    clustered = {id(r) for a in attacks for r in a.rhythm}
    clustered |= {id(b) for b in brackets
                  if any(a.bracket and abs(b.cx - (a.x0 + a.x1) / 2)
                         <= STEM_REACH * gap for a in attacks)}
    evidence = [s for s in syms
                if s.role in EVIDENCE_ROLES
                or (s.role in RHYTHM_ROLES and id(s) not in clustered)]
    return attacks, evidence


def read_duration(att: Attack, gap: float, meter_beats: float) -> float | None:
    """attack 时值:基拍四分,每层符尾/符杠 ÷2,附点 ×1.5。

    rest8 模板即八分,固定 0.5;rest_whole = 整小节;无杆尾杠而有延音
    括线 = 四分攻+延音(印张长音画法);全无 → None(漂移可见,不瞎猜)。"""
    if any(s.role == "rest8" for s in att.events):
        return DEFAULT_REST8
    if any(s.role == "rest_whole" for s in att.events):
        return meter_beats
    stems = [s for s in att.rhythm if s.role in ("stem", "flagstem")]
    flags = sum(1 for s in att.rhythm if s.role in ("flag", "flagstem"))
    beams = [s for s in att.rhythm if s.role == "beam"]
    if not stems and not beams and not flags:
        if att.bracket:
            return 1.0
        return None
    if stems:
        subs = flags + sum(
            1 for b in beams
            if any(b.x < st.x1 + 0.2 * gap and b.x1 > st.x - 0.2 * gap
                   for st in stems))
    else:
        subs = flags + len(beams)     # 无杆而有杠(密集段被并簇)也计层
    dur = 0.5 ** min(subs, MAX_SUBS)
    if subs > MAX_SUBS:
        att.warnings.append(f"符尾/符杠 {subs} 层超考域,按 {MAX_SUBS} 层读")
    if _has_aug_dot(att, gap):
        dur *= 1.5
    return dur


def _has_aug_dot(att: Attack, gap: float) -> bool:
    """附点:数字右缘外 AUG_GAP 带内、同 cy 的小点(窄字 '1' 亦按缘判)。"""
    pitches = att.digits or att.x_marks
    if not pitches:
        return False
    top = min(pitches, key=lambda s: s.cy)
    for d in att.rhythm:
        if d.role != "dot":
            continue
        lat = d.cx - top.x1
        if (AUG_GAP[0] * gap <= lat <= AUG_GAP[1] * gap
                and abs(d.cy - top.cy) <= AUG_CY * gap):
            return True
    return False


# ── 装配层:attack 序 → 拍位累加 + 小节归属 + 闭合对账 ─────────────────

def _sym_json(s: Sym) -> dict:
    d = {"role": s.role, "bbox": [round(s.x, 1), round(s.y, 1),
                                  round(s.w, 1), round(s.h, 1)]}
    if s.label:
        d["label"] = s.label
    if s.conf:
        d["confidence"] = round(s.conf, 3)
    return d


def _string_of(sym: Sym, line_ys, gap) -> int | None:
    """数字所在弦:圆心最近弦线(1=最细=顶线)。落域外给 None(警告层)。"""
    dists = [abs(sym.cy - ly) for ly in line_ys]
    k = dists.index(min(dists))
    return (k + 1) if min(dists) <= 0.6 * gap else None


def _x_strings(sym: Sym, line_ys, gap) -> list:
    """×/×堆覆盖的弦号列表(1-4):块高折合弦数,中心对齐最近线。"""
    if sym.role == "x_stack":
        n = max(1, min(4, round(sym.h / gap)))
        lo = min(range(len(line_ys)), key=lambda i: abs(sym.cy - line_ys[i]))
        lo = max(0, min(lo - n // 2, len(line_ys) - n))
        return list(range(lo + 1, lo + n + 1))
    k = _string_of(sym, line_ys, gap)
    return [k] if k is not None else []


def assemble_measures(attacks, evidence, spans, meter_beats, line_ys, gap,
                      start_index=0):
    """拍位装配:attacks 按 x 序落小节;小节起点锚在小节网格(bar 数×拍号),
    小节内 beat=时值累加;duration=None 的 attack 照记拍位但按 0 累加并落
    警告(漂移只留在小节内,不跨小节级联)。× 不落音,落 x_marks 证据
    (票面);spans=单系统坐标系(工单49 zip 教训:各系统 x 域同形,跨
    系统拼 spans 会把全谱灌进首个系统)。"""
    out_measures = []
    for gi, span in enumerate(spans):
        inside = sorted((a for a in attacks
                         if span["x0"] <= a.cx < span["x1"]),
                        key=lambda a: a.cx)
        start = meter_beats * (start_index + gi)
        m_notes, m_rests, m_marks, m_tech, m_warn = [], [], [], [], []
        cum = 0.0
        prev_beat = start
        for a in inside:
            beat = start + cum
            if a.duration is None and not any(
                    s.role == "rest_whole" for s in a.events):
                m_warn.append(f"attack x={a.cx:.0f} 无节奏记号,时值未知按 0 计")
            dur = a.duration or 0.0
            for s in a.digits:
                string = _string_of(s, line_ys, gap)
                if string is None:
                    m_warn.append(
                        f"数字 {s.label!r} x={s.cx:.0f} 不落任何弦线带,弦号未知")
                m_notes.append({
                    "string": string, "fret": int(s.label),
                    "beat": beat, "duration": a.duration,
                    "confidence": round(s.conf, 3),
                    "x": round(s.cx, 1),
                    "evidence": _sym_json(s),
                })
            for s in a.x_marks:
                strings = _x_strings(s, line_ys, gap)
                if not strings:
                    m_warn.append(f"× {s.role} x={s.cx:.0f} 不落任何弦线带,"
                                  "弦号未知")
                m_marks.append({"kind": s.role,
                                "strings": strings,
                                "beat": beat, "x": round(s.cx, 1),
                                "evidence": _sym_json(s)})
            for s in a.events:
                if s.role == "rest8":
                    m_rests.append({"beat": beat, "beats": a.duration,
                                    "kind": "rest8", "x": round(s.cx, 1),
                                    "evidence": _sym_json(s)})
                elif s.role == "rest_whole":
                    m_rests.append({"beat": beat, "beats": meter_beats,
                                    "kind": "rest_whole",
                                    "x": round(s.cx, 1),
                                    "evidence": _sym_json(s)})
                elif s.role == "roll":
                    m_tech.append({"kind": "roll", "beat": beat,
                                   "x": round(s.cx, 1),
                                   "evidence": _sym_json(s)})
                elif s.role in ("shaft", "strumUp", "strumDown"):
                    m_tech.append({"kind": s.role, "beat": beat,
                                   "x": round(s.cx, 1),
                                   "evidence": _sym_json(s)})
            prev_beat = beat
            cum += dur
        for s in evidence:
            if not (span["x0"] <= s.cx < span["x1"]):
                continue
            if s.role in ("slide", "tremolo", "ellipse"):
                m_tech.append({"kind": s.role, "beat": prev_beat,
                               "x": round(s.cx, 1), "evidence": _sym_json(s)})
            elif s.role == "barline":
                m_marks.append({"kind": "barline", "beat": None,
                                "x": round(s.cx, 1),
                                "evidence": _sym_json(s)})
        closure_ok = bool(inside) and abs(cum - meter_beats) < 1e-9
        if inside and not closure_ok:
            m_warn.append(f"小节拍长闭合 {cum:g} ≠ 拍号 {meter_beats:g},"
                          "逐符号人工核对")
        out_measures.append({
            "index": span["index"], "x0": span["x0"], "x1": span["x1"],
            "start_beat": start, "read_beats": cum, "closure_ok": closure_ok,
            "notes": m_notes, "rests": m_rests, "x_marks": m_marks,
            "techniques": m_tech, "warnings": m_warn,
        })
    unmapped = [a for a in attacks
                if not any(sp["x0"] <= a.cx < sp["x1"] for sp in spans)]
    return out_measures, unmapped


# ── 编排层:单系统识别 + 全曲草稿 ─────────────────────────────────────

def recognize_system(crop_gray, system, ocr, meter_beats=DEFAULT_METER) -> dict:
    """单系统:裁图 → 组件 → 分类 → barline 排除 → 箭头定向 → attack
    聚簇 → 时值。

    几何以裁图坐标进分类器,出来的符号统一换到页坐标(crop x/y + 裁图
    偏移),小节 spans(页坐标)直接可比。"""
    staff = system["staff"]
    gap = staff["gap"]
    y_off = int(system["layers"]["tab"]["bbox"][1]) - CROP_PAD
    x_off = int(system["layers"]["tab"]["bbox"][0]) - CROP_PAD
    comps_int, comps_below = staff_components(
        crop_gray, [ly - y_off for ly in staff["line_ys"]],
        staff["top"] - y_off, staff["bottom"] - y_off, gap,
        staff["x0"] - x_off, staff["x1"] - x_off)
    syms = classify_symbols(comps_int, comps_below, gap,
                            [ly - y_off for ly in staff["line_ys"]],
                            staff["x0"] - x_off, crop_gray, ocr)
    bounds = [b["x"] - x_off for m in system["measures"]
              for b in (m["left"], m["right"])]
    syms = [s.moved(x=s.x + x_off, y=s.y + y_off) for s in syms]
    syms = drop_bound_barlines(syms, bounds, gap)
    syms = _direct_strums(syms, gap)
    attacks, evidence = cluster_attacks(syms, gap)
    for a in attacks:
        a.duration = read_duration(a, gap, meter_beats)
    return {"attacks": attacks, "evidence": evidence}


def recognize_tab_pdf(pdf: str, out_dir: str, dpi: int = 300,
                      ocr=None, header_reader=None,
                      models_dir: str | None = None) -> dict:
    """票面主入口:位图 PDF → split → 逐系统 TAB 识别 → tab.json。

    ocr 缺省走 PP-OCR(模型目录按 resolve 默认序找,models_dir 可指定);
    页眉复用工单49 的 read_header(调号/拍号/速度,读不出按 4/4 假定落
    警告)。"""
    import cv2

    from .melody import read_header
    from .report import sha256_file
    from .split import split_pdf

    layout = split_pdf(pdf, out_dir, dpi=dpi)
    if ocr is None:
        from .paddle_ocr import DigitOCR
        ocr = DigitOCR(models_dir)
    systems = [s for pg in layout["score_pages"] for s in pg["systems"]]
    if header_reader is None and systems and hasattr(ocr, "line_text"):
        first_top = systems[0]["staff"]["top"]
        header_reader = lambda: read_header(pdf, dpi, first_top, ocr)  # noqa: E731
    header = {"key": None, "meter": None, "tempo_bpm": None,
              "meter_assumed": True, "evidence": None, "warnings": []}
    if header_reader is not None:
        header = header_reader()
    meter_beats = DEFAULT_METER
    if header.get("meter"):
        meter_beats = float(header["meter"].split("/")[0])
    per_system, all_attacks, all_evidence = [], [], []
    for s in systems:
        crop = cv2.imread(str(Path(out_dir) / s["layers"]["tab"]["crop"]),
                          cv2.IMREAD_GRAYSCALE)
        res = recognize_system(crop, s, ocr, meter_beats)
        per_system.append({
            "index": s["index"],
            "n_digits": sum(len(a.digits) for a in res["attacks"]),
            "n_x_marks": sum(len(a.x_marks) for a in res["attacks"]),
            "n_rests": sum(1 for a in res["attacks"] for e in a.events
                           if e.role.startswith("rest")),
            "n_rolls": sum(1 for a in res["attacks"] for e in a.events
                           if e.role == "roll"),
            "n_evidence": len(res["evidence"]),
        })
        all_attacks.append(res["attacks"])
        all_evidence.append(res["evidence"])
    measures, unmapped = [], []
    for s, attacks, evidence in zip(systems, all_attacks, all_evidence):
        spans = [{"index": m["index"], "x0": m["x0"], "x1": m["x1"]}
                 for m in s["measures"]]
        # 小节起点锚在小节网格(bar 数 × 拍号):barline 是真值,read_beats
        # 被 None 时值毒化时会跨小节级联漂移;拍位漂移只许留在小节内
        asm, un = assemble_measures(attacks, evidence, spans, meter_beats,
                                    s["staff"]["line_ys"],
                                    s["staff"]["gap"],
                                    start_index=len(measures))
        for m in asm:
            m["index"] = len(measures)
            m["system"] = s["index"]
            measures.append(m)
        unmapped.extend(un)
    draft = {
        "schema": SCHEMA,
        "tool_version": __version__,
        "created_at": datetime.datetime.now().astimezone().isoformat(
            timespec="seconds"),
        "source": {"file": str(Path(pdf).resolve()),
                   "sha256": sha256_file(pdf), "dpi": dpi},
        "header": header,
        "systems": per_system,
        "measures": measures,
        "unmapped_attacks": [{
            "x": round(a.cx, 1),
            "digits": [_sym_json(s) for s in a.digits],
            "x_marks": [_sym_json(s) for s in a.x_marks],
            "events": [_sym_json(s) for s in a.events],
        } for a in unmapped],
    }
    out = Path(out_dir)
    with open(out / "tab.json", "w", encoding="utf-8") as fh:
        fh.write(json.dumps(draft, ensure_ascii=False, indent=2) + "\n")
    return draft
