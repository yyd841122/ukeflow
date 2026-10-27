"""谱面体检(工单47①):PDF 对象层探测——文本层有无/位图覆盖率/矢量指令。

判读交给 classify(纯函数);本模块只如实报信号。
实测基线:谱全了曲源 PDF(工单39/41)= 每页 4 条全宽位图带拼接,
覆盖率 1.0、零文本层、零矢量指令。
"""

import pymupdf

from .classify import CheckupSignals


def checkup_pdf(path: str) -> CheckupSignals:
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
        cov = sum(max(0.0, b["bbox"][2] - b["bbox"][0])
                  * max(0.0, b["bbox"][3] - b["bbox"][1])
                  for b in infos) / area
        coverage_sum += min(cov, 1.0)
        n_drawings += len(page.get_drawings())
    doc.close()
    return CheckupSignals(pages=pages, text_chars=text_chars, n_images=n_images,
                          image_coverage=coverage_sum / max(pages, 1),
                          n_drawings=n_drawings)
