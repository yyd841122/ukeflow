"""分流报告(工单47③):体检+版面+判别 → 落盘 JSON。

判别策略在 classify(纯函数);本模块管流水线编排与报告形状。
版面信号只在位图路径取(矢量谱只报告不处理,工单47①)。
"""

import dataclasses
import datetime
import hashlib
import json
from pathlib import Path

from . import __version__
from .classify import LayoutSignals, SCORE_TYPES, classify_score, is_bitmap
from .checkup import checkup_pdf
from .layout import extract_layout_gray, extract_layout_pixmap

SCHEMA = "ukeflow.workbench.triage/1"


def triage_pdf(path: str, override: str | None = None) -> dict:
    if override is not None and override not in SCORE_TYPES:
        raise ValueError(f"override 须是 {SCORE_TYPES} 之一,得 {override!r}")
    checkup = checkup_pdf(path)
    layout = None
    if is_bitmap(checkup):  # 矢量谱只报告不取版面(is_vector_score 对位图恒 False)
        layout = _layout_of(path)
    verdict = classify_score(checkup, layout, override=override)
    return {
        "schema": SCHEMA,
        "tool_version": __version__,
        "file": str(Path(path).resolve()),
        "sha256": sha256_file(path),
        "checked_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "checkup": dataclasses.asdict(checkup),
        "layout": dataclasses.asdict(layout) if layout is not None else None,
        "classification": dataclasses.asdict(verdict),
    }


def _layout_of(path: str) -> LayoutSignals:
    import pymupdf

    total = None
    doc = pymupdf.open(path)
    try:
        for page in doc:
            pix = page.get_pixmap(matrix=pymupdf.Matrix(3.0, 3.0),
                                  colorspace=pymupdf.csGRAY)
            sig = extract_layout_pixmap(pix)
            total = sig if total is None else LayoutSignals(
                **{f.name: getattr(total, f.name) + getattr(sig, f.name)
                   for f in dataclasses.fields(LayoutSignals)})
    finally:
        doc.close()
    return total if total is not None else LayoutSignals(0, 0, 0, 0, 0, 0)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def report_json(report: dict) -> str:
    return json.dumps(report, ensure_ascii=False, indent=2)
