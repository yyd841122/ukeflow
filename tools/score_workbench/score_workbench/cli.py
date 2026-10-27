"""CLI 入口(python -m score_workbench.cli):

  triage <pdf> [--out FILE] [--type solo|strum|image|vector]
      体检+谱型判别,输出分流报告 JSON(无 --out 打到 stdout);
      --type 人工改判(ADR-0009:误判可手改),自动判定保留在 auto_type。
  checkup <pdf> [--json]
      只体检:文本层/位图覆盖率/矢量指令,矢量谱到此为止。
"""

import argparse
import dataclasses
import json
import sys

from . import __version__
from .checkup import checkup_pdf
from .classify import SCORE_TYPES, checkup_kind
from .report import report_json, triage_pdf


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="score_workbench",
        description=f"UkeFlow 识谱工作台 v{__version__}(工单47:体检+谱型判别 CLI)")
    sub = parser.add_subparsers(dest="command", required=True)
    p_tri = sub.add_parser("triage", help="体检+谱型判别,输出分流报告 JSON")
    p_tri.add_argument("pdf", help="曲谱 PDF 路径")
    p_tri.add_argument("--out", metavar="FILE",
                       help="报告落盘路径(缺省打到 stdout;给出时 stdout 出人话摘要)")
    p_tri.add_argument("--type", choices=SCORE_TYPES, default=None,
                       help="人工改判谱型(自动判定保留在 auto_type)")
    p_chk = sub.add_parser("checkup", help="只体检(矢量/位图信号)")
    p_chk.add_argument("pdf", help="曲谱 PDF 路径")
    p_chk.add_argument("--json", action="store_true", help="输出体检信号 JSON")
    args = parser.parse_args(argv)

    try:
        if args.command == "checkup":
            return _checkup(args)
        return _triage(args)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"打不开或读不了 {args.pdf}:{exc}", file=sys.stderr)
        return 2


def _triage(args) -> int:
    report = triage_pdf(args.pdf, override=args.type)
    if args.out is None:
        print(report_json(report))
        return 0
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(report_json(report) + "\n")
    cls = report["classification"]
    print(f"{report['file']}: {cls['score_type']} → {cls['disposition']}"
          + ("(人工改判)" if cls["overridden"] else ""))
    for r in cls["reasons"]:
        print(f"  理由: {r}")
    print(f"  体检: {_signals_line(report['checkup'])}")
    print(f"  报告: {args.out}")
    return 0


def _signals_line(cu: dict) -> str:
    """体检信号摘要行(报告 JSON 与数据类 asdict 皆为此形状)。"""
    return (f"{cu['pages']} 页 | 位图覆盖率 {cu['image_coverage']:.2f}"
            f" | 文本 {cu['text_chars']} 字符 | 位图对象 {cu['n_images']}"
            f" | 矢量指令 {cu['n_drawings']}")


def _checkup(args) -> int:
    sig = checkup_pdf(args.pdf)
    if args.json:
        print(json.dumps(dataclasses.asdict(sig), ensure_ascii=False))
        return 0
    print(f"{args.pdf}: {checkup_kind(sig)}")
    print(f"  {_signals_line(dataclasses.asdict(sig))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
