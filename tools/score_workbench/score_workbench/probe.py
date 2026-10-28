"""像素考古探针(工单49 retro):裁图组件表 + ASCII 图,一条命令替代
每票现写的 /tmp 一次性脚本。只读不判,给人工/agent 目验用。

  $PY -m score_workbench.cli probe crops/p00h0s01_jianpu.png --x0 0 --x1 420
  $PY -m score_workbench.cli probe crop.png --y0 30 --y1 62 --ascii
"""

import argparse

import cv2
import numpy as np

MIN_AREA = 12              # 组件最小面积(与 melody/split 同源)


def probe_image(path: str, x0: int = 0, x1: int | None = None,
                y0: int = 0, y1: int | None = None, ink_max: int = 195,
                ascii_step: int = 2) -> str:
    """组件表(≥MIN_AREA,x 序)+ 指定窗口的 ASCII 图(--ascii 时)。"""
    img = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise FileNotFoundError(f"读不了图:{path}")
    x1 = img.shape[1] if x1 is None else min(x1, img.shape[1])
    y1 = img.shape[0] if y1 is None else min(y1, img.shape[0])
    ink = (img < ink_max).astype(np.uint8)
    n, _, stats, _ = cv2.connectedComponentsWithStats(ink)
    lines = [f"{path} {img.shape[1]}×{img.shape[0]} 窗口 x[{x0},{x1}) "
             f"y[{y0},{y1}) 墨阈<{ink_max}"]
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
    sub = ink[y0:y1, x0:x1]
    lines.append(f"ASCII({ascii_step}px 步进,#=墨):")
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
    args = ap.parse_args(argv)
    print(probe_image(args.image, args.x0, args.x1, args.y0, args.y1,
                      args.ink_max, args.ascii_step))
    return 0
