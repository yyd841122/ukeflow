"""CLI 入口(python -m score_workbench.cli):

  triage <pdf> [--out FILE] [--type solo|strum|image|vector]
      体检+谱型判别,输出分流报告 JSON(无 --out 打到 stdout);
      --type 人工改判(ADR-0009:误判可手改),自动判定保留在 auto_type。
  checkup <pdf> [--json]
      只体检:文本层/位图覆盖率/矢量指令,矢量谱到此为止。
  split <pdf> --out-dir DIR [--dpi N]
      版面切分(工单48):逐系统逐层裁图 + 小节/拍位骨架 JSON(layout.json)。
  recognize <pdf> --out-dir DIR [--dpi N] [--models DIR]
      旋律层识别(工单49):PaddleOCR 数字 + 几何规则 → 简谱旋律声部草稿
      (melody.json,度数+八度点+拍位+时值,逐符号证据)。
  diff-melody <draft.json> <truth.json> [--start-measure N] [--out FILE]
      草稿×人工真值逐位 diff(度数/拍位/时值/八度点 + 热点清单)。
      truth 由 dart run tools/dump_melody_truth.dart 导出。
"""

import argparse
import dataclasses
import json
import sys

from . import __version__
from .checkup import checkup_pdf
from .classify import SCORE_TYPES, checkup_kind
from .melodic_diff import diff_melody
from .melody import recognize_melody_pdf
from .paddle_ocr import DEFAULT_MODEL_DIRS
from .report import report_json, triage_pdf
from .split import split_pdf


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
    p_split = sub.add_parser("split", help="版面切分:逐系统逐层裁图+骨架 JSON")
    p_split.add_argument("pdf", help="曲谱 PDF 路径(位图)")
    p_split.add_argument("--out-dir", required=True, metavar="DIR",
                         help="产物目录:layout.json + crops/")
    p_split.add_argument("--dpi", type=int, default=300, metavar="N",
                         help="渲染 dpi(300-400,越界报错;默认 300)")
    p_chk = sub.add_parser("checkup", help="只体检(矢量/位图信号)")
    p_chk.add_argument("pdf", help="曲谱 PDF 路径")
    p_chk.add_argument("--json", action="store_true", help="输出体检信号 JSON")
    p_rec = sub.add_parser("recognize", help="旋律层识别(工单49)")
    p_rec.add_argument("pdf", help="曲谱 PDF 路径(位图)")
    p_rec.add_argument("--out-dir", required=True, metavar="DIR",
                       help="产物目录:melody.json(复用/重跑 split)")
    p_rec.add_argument("--dpi", type=int, default=300, metavar="N",
                       help="渲染 dpi(300-400;默认 300)")
    p_rec.add_argument("--models", default=None, metavar="DIR",
                       help=f"PP-OCR 模型目录(缺省按 {' → '.join(DEFAULT_MODEL_DIRS)} 找)")
    p_dif = sub.add_parser("diff-melody", help="草稿×真值逐位 diff")
    p_dif.add_argument("draft", help="recognize 产物 melody.json")
    p_dif.add_argument("truth", help="dump_melody_truth.dart 导出的真值 JSON")
    p_dif.add_argument("--start-measure", type=int, default=5, metavar="N",
                       help="草稿窗口起点小节(默认 5=aini 主歌 |: 起)")
    p_dif.add_argument("--chunk-beats", type=float, default=4.0, metavar="N",
                       help="真值块长(拍,默认 4=4/4 连拍格)")
    p_dif.add_argument("--out", metavar="FILE", help="diff 报告落盘(缺省 stdout 摘要)")
    args = parser.parse_args(argv)

    try:
        if args.command == "checkup":
            return _checkup(args)
        if args.command == "split":
            return _split(args)
        if args.command == "recognize":
            return _recognize(args)
        if args.command == "diff-melody":
            return _diff_melody(args)
        return _triage(args)
    except (OSError, RuntimeError, ValueError) as exc:
        # diff-melody 无 pdf 位(吃 draft/truth 两 JSON),取实际输入位防遮掩
        what = getattr(args, "pdf", None) or getattr(args, "truth", "")
        print(f"打不开或读不了 {what}:{exc}", file=sys.stderr)
        return 2


def _split(args) -> int:
    report = split_pdf(args.pdf, args.out_dir, dpi=args.dpi)
    systems = sum(len(pg["systems"]) for pg in report["score_pages"])
    measures = sum(len(s["measures"])
                   for pg in report["score_pages"] for s in pg["systems"])
    print(f"{report['source']['file']}: {report['source']['dpi']}dpi,检出 {systems} 系统 / "
          f"{measures} 小节")
    for pg in report["score_pages"]:
        if pg["systems"]:
            print(f"  谱页{pg['index']}(pdf{pg['pdf_page']} {'上' if pg['half']==0 else '下'}半):"
                  f" {len(pg['systems'])} 系统")
    for w in report["warnings"]:
        print(f"  警告: {w}")
    print(f"  产物: {args.out_dir}/layout.json + crops/")
    return 0


def _recognize(args) -> int:
    draft = recognize_melody_pdf(args.pdf, args.out_dir, dpi=args.dpi,
                                 models_dir=args.models)
    notes = sum(len(m["notes"]) for m in draft["measures"])
    rests = sum(len(m["rests"]) for m in draft["measures"])
    warn = sum(len(m["warnings"]) for m in draft["measures"]) \
        + sum(len(s["warnings"]) for s in draft["systems"]) \
        + len(draft["header"]["warnings"])
    head = draft["header"]
    print(f"{draft['source']['file']}: {notes} 音 / {rests} 休止 / "
          f"{len(draft['measures'])} 小节")
    print(f"  页眉: key={head['key']} meter={head['meter']}"
          f"(assumed={head['meter_assumed']}) tempo={head['tempo_bpm']}")
    print(f"  警告 {warn} 条(未知符号/闭合不齐/歧证,见 melody.json)")
    print(f"  产物: {args.out_dir}/melody.json")
    return 0


def _diff_melody(args) -> int:
    with open(args.draft, encoding="utf-8") as fh:
        draft = json.load(fh)
    with open(args.truth, encoding="utf-8") as fh:
        truth = json.load(fh)
    report = diff_melody(draft, truth, start_measure=args.start_measure,
                         chunk_beats=args.chunk_beats)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(report, ensure_ascii=False, indent=1) + "\n")
    s = report["summary"]
    pairs = s["degree_ok"] + s["degree_bad"]
    print(f"窗口自小节 {args.start_measure}:{pairs} 对音"
          f"(草稿尾部 {s.get('tail_notes_beyond_truth', 0)} 音超出真值不比)")
    print(f"  度数 {s['degree_ok']}/{pairs}"
          f"  拍位 {s['beat_ok']}/{s['beat_ok'] + s['beat_bad']}"
          f"  时值 {s['duration_ok']}/{s['duration_compared']}")
    hot = [(c["truth_measure"], c["draft_measures"], c["mismatches"])
           for c in report["chunks"] if c["mismatches"]]
    print(f"  热点 {len(hot)} 块:")
    for k, ms, mms in hot:
        print(f"    truth b{k} ↔ m{ms}: "
              + "; ".join(f"{m['field']}@{m.get('beat', '?')}"
                          f" 草{m.get('draft')}/真{m.get('truth')}"
                          for m in mms[:4]))
    if args.out:
        print(f"  报告: {args.out}")
    return 0


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
