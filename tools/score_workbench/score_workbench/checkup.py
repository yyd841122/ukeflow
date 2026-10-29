"""谱面体检(工单47①):PDF 对象层探测——文本层有无/位图覆盖率/矢量指令。

判读交给 classify(纯函数);本模块只如实报信号。
实测基线:谱全了曲源 PDF(工单39/41)= 每页 4 条全宽位图带拼接,
覆盖率 1.0、零文本层、零矢量指令。
"""

import pymupdf

from .classify import CheckupSignals


def checkup_pdf(path: str) -> CheckupSignals:
    doc = pymupdf.open(path)
def _union_area(bboxes: list, px0: float, py0: float, px1: float,
                py1: float) -> float:
    """矩形并集面积(坐标压缩网格;页数/图数都小,精确即可)。裁到页内,
    重叠不双计(评审51:直加会把叠放位图算成双倍覆盖)。"""
    if not bboxes:
        return 0.0
    rects = []
    for b in bboxes:
        x0, y0 = max(b[0], px0), max(b[1], py0)
        x1, y1 = min(b[2], px1), min(b[3], py1)
        if x1 > x0 and y1 > y0:
            rects.append((x0, y0, x1, y1))
    if not rects:
        return 0.0
    xs = sorted({v for r in rects for v in (r[0], r[2])})
    ys = sorted({v for r in rects for v in (r[1], r[3])})
    total = 0.0
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            cx, cy = (xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2
            if any(r[0] <= cx <= r[2] and r[1] <= cy <= r[3] for r in rects):
                total += (xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j])
    return total


def checkup_pdf(path: str):
    """体检①(工单47):PDF 对象层信号。"""
    import pymupdf

    doc = pymupdf.open(path)
    pages = len(doc)
    text_chars = 0
    n_images = 0
    coverage_sum = 0.0
    n_drawings = 0
    for page in doc:
        text_chars += len("".join(page.get_text().split()))
        infos = page.get_image_info()
        n_images += len(infos)
        area = abs(page.rect) or 1.0
        cov = _union_area([b["bbox"] for b in infos],
                          page.rect[0], page.rect[1],
                          page.rect[2], page.rect[3]) / area
        coverage_sum += min(cov, 1.0)
        n_drawings += len(page.get_drawings())
    doc.close()
    return CheckupSignals(pages=pages, text_chars=text_chars, n_images=n_images,
                          image_coverage=coverage_sum / max(pages, 1),
                          n_drawings=n_drawings)
