"""像素考古探针(工单49/50 retro):裁图组件表 + ASCII 图 + 灰度分层 +
行宽剖面,一条命令替代每票现写的 /tmp 一次性脚本。只读不判,给人工/agent
目验用。

  $PY -m score_workbench.cli probe crops/p00h0s01_jianpu.png --x0 0 --x1 420
  $PY -m score_workbench.cli probe crop.png --gray-steps 100,180,208   # 亚阈分层
  $PY -m score_workbench.cli probe crop.png --widths --y0 10 --y1 90   # 行宽剖面
"""

import argparse

import cv2
import numpy as np

MIN_AREA = 12              # 组件最小面积(与 melody/split 同源)
GRAY_CHARS = "#+o:"        # 灰度分层字符:第 k 档 ≤ steps[k],更深字符更黑


def probe_image(path: str, x0: int = 0, x1: int | None = None,
                y0: int = 0, y1: int | None = None, ink_max: int = 195,
                ascii_step: int = 2, gray_steps: str | None = None,
                widths: bool = False) -> str:
    """组件表(≥MIN_AREA,x 序)+ 指定窗口的 ASCII 图。

    --gray-steps "100,180,208" 开灰度分层:字符取窗口内最黑档
    (≤100=#,≤180=+,≤208=o,余=空白),反锯齿尾/线芯灰度一目了然;
    --widths 开行宽剖面(窗口内逐墨行的 [x0..x1] 跨度,竖柱/行段判据查表)。
    """
    img = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise FileNotFoundError(f"读不了图:{path}")
    x1 = img.shape[1] if x1 is None else min(x1, img.shape[1])
    y1 = img.shape[0] if y1 is None else min(y1, img.shape[0])
    win = img[y0:y1, x0:x1]
    lines = [f"{path} {img.shape[1]}×{img.shape[0]} 窗口 x[{x0},{x1}) "
             f"y[{y0},{y1}) 墨阈<{ink_max}"]
    if gray_steps:
        lines.append(f"灰度分层 {gray_steps}"
                     f"(字符 {'<'.join(GRAY_CHARS)}):")
    if widths:
        lines.append("行宽剖面(墨行 → [x0..x1] 跨度):")
    ink = (img < ink_max).astype(np.uint8)
    n, _, stats, _ = cv2.connectedComponentsWithStats(ink)
    rows = []
    for i in range(1, n):
        x, y, w, h, a = (int(v) for v in stats[i])
        if a >= MIN_AREA and x + w > x0 and x < x1 and y + h > y0 and y < y1:
            rows.append((x, y, w, h, a))
    rows.sort()
    lines.append(f"组件 {len(rows)} 个(≥{MIN_AREA}px²,x 序):")
    lines.append("   x    y    w    h  area")
    for x, y, w, h, a in rows:
        lines.append(f"{x:4d} {y:4d} {w:4d} {h:4d} {a:5d}")
    if gray_steps:
        steps = sorted(int(s) for s in gray_steps.split(","))
        sub = win
        for r in range(sub.shape[0]):
            cells = []
            for c in range(sub.shape[1]):
                v = sub[r, c]
                ch = " "
                for k, t in enumerate(steps):
                    if v < t:
                        ch = GRAY_CHARS[min(k, len(GRAY_CHARS) - 1)]
                        break
                cells.append(ch)
            line = "".join(cells)
            if line.strip():
                lines.append(f"{y0 + r:4d} {line}")
    if widths:
        band = win < ink_max
        for r in range(band.shape[0]):
            xs = np.flatnonzero(band[r])
            if len(xs):
                lines.append(f"{y0 + r:4d} [{xs[0] + x0:4d}..{xs[-1] + x0:4d}] "
                             f"w={xs[-1] - xs[0] + 1:3d}")
    sub = ink[y0:y1, x0:x1]
    lines.append(f"ASCII({ascii_step}px 步进,#=墨<{ink_max}):")
    for r in range(0, sub.shape[0], ascii_step):
        line = "".join("#" if sub[r:r + ascii_step, c:c + ascii_step].any()
                       else " " for c in range(0, sub.shape[1], ascii_step))
        lines.append(f"{y0 + r:4d} {line}")
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="probe", description="像素考古探针")
    ap.add_argument("image", help="裁图/渲染页 PNG")
    ap.add_argument("--x0", type=int, default=0)
    ap.add_argument("--x1", type=int, default=None)
    ap.add_argument("--y0", type=int, default=0)
    ap.add_argument("--y1", type=int, default=None)
    ap.add_argument("--ink-max", type=int, default=195, help="墨阈(默认 195)")
    ap.add_argument("--ascii-step", type=int, default=2, help="ASCII 步进 px")
    ap.add_argument("--gray-steps", default=None,
                    help="灰度分层阈(逗号分隔,如 100,180,208);字符 #+o")
    ap.add_argument("--widths", action="store_true",
                    help="行宽剖面(逐墨行 [x0..x1] 跨度)")
    args = ap.parse_args(argv)
    print(probe_image(args.image, args.x0, args.x1, args.y0, args.y1,
                      args.ink_max, args.ascii_step, args.gray_steps,
                      args.widths))
    return 0
