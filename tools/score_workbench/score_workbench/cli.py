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
  recognize-tab <pdf> --out-dir DIR [--dpi N] [--models DIR]
      TAB 伴奏层识别(工单50):品位数字 OCR + 四线定位 + 节奏/记号解释
      → 伴奏声部草稿(tab.json;× 不落音落证据,ADR-0009)。
  diff-tab <draft.json> <truth.json> [--start-measure N] [--out FILE]
      TAB 草稿×人工真值 diff(数字正确率/时值/休止 P-R/技巧 F1)。
      truth 由 dart run tools/dump_tab_truth.dart 导出。
  probe <png> [--x0 N --x1 N --y0 N --y1 N] [--gray-steps 100,180,208]
      [--widths] [--ascii-step N]   # 灰度分层/行宽剖面(工单50 retro)
      像素考古探针(retro):组件表 + ASCII 图,目验裁图用。
  serve <out-dir> [--port N]
      校对台 web(工单51,localhost 单页):左系统条带(bbox 高亮)/右
      小节 IR 表,点击互跳、逐小节确认、全曲确认导出 ScoreIR JSON;
      载 builtin 真值 JSON 跑对照(diff 报告即验收面板)。
      只绑 127.0.0.1。状态存 <out-dir>/proof.json,导出落 <out-dir>/ir.json。
  vlm-prepare --pdf PDF --layout FILE --out-dir DIR --score-pages 0,1,2
      [--systems page0:0,page0:1,...]
      工单57 输入制备:PDF 嵌入位图原生拼装整谱页(page{N}.png)+ 系统条带
      裁块(整块全层,保留完整节奏带;300dpi 骨架坐标→原生换算)。
  vlm-run --image FILE --unit NAME --out-dir DIR [--model M] [--budget-cny N]
      工单57 VLM 直读:冻结提示词 × 图片 → DeepSeek vision → 归一候选。
      key 从环境变量 DEEPSEEK_API_KEY 读;原始响应/候选/账本落 out-dir
      (仓库外,不入库不入 git);候选未过筛留全时值轴。
  vlm-assemble --runs-dir DIR --units a,b,c --out FILE
      工单57 候选合并 → 过筛已裁定拍段(0-36+80-108)→ 标段 → 整表候选,
      交 eval-joint 评分。
  tab-candidate <tab.json> --out FILE
      工单59a:50 TAB 草稿 → ukeflow.eval.candidate/1(聚列+时值持续窗
      重算+scope 标段),落盘交 eval-joint——不训练基线的候选半边。
  oracle-glyph <pdf> --out-dir DIR [--evalset FILE]
      [--variant marks|marks+durations] [--skeleton split|repaired]
      [--bar-map PRESET] [--dpi N]
      工单61 m0:真值字形 oracle 注入(61 票面:冻结评测集当正确字形喂回
      50 自动定位+节奏解码)。产物 oracle-tab*.json(同 tab.json schema
      + oracle 对齐段),随后 tab-candidate → eval-joint 与 59a 同链。
      marks=票面主数;marks+durations=时值亦真值的归因诊断(非主数)。
      skeleton=split(装配吃 split 小节界,幻影界错位照罚)| repaired
      (幻影界按映射并合的上限诊断);bar-map=注入锚的小节映射预设。
  eval-melody <melody.json> --truth FILE [--out FILE]
      工单59a:49 旋律草稿 × dump_melody_truth(参照级)逐窗 melody_score
      (56 配对机制;authority=reference,不与 TAB 冻结闸混称)。
"""

import argparse
import dataclasses
import json
import sys
from pathlib import Path

from . import __version__
from .checkup import checkup_pdf
from .classify import SCORE_TYPES, checkup_kind
from .eval_build import build_evalset
from .eval_scorer import joint_report
from .eval_truth import DEFAULT_PATH, load_evalset
from .melodic_diff import diff_melody
from .melody import recognize_melody_pdf
from .probe import probe_image
from .paddle_ocr import DEFAULT_MODEL_DIRS
from .report import report_json, triage_pdf
from .split import split_pdf
from .tab import recognize_tab_pdf
from .tab_diff import diff_tab
from . import vlm_poc


def _build_parser() -> argparse.ArgumentParser:
    """参数表构建(评审51 #cli):main 只留分发与异常上报,加命令不搅
    dispatch。"""
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
    p_tab = sub.add_parser("recognize-tab", help="TAB 伴奏层识别(工单50)")
    p_tab.add_argument("pdf", help="曲谱 PDF 路径(位图)")
    p_tab.add_argument("--out-dir", required=True, metavar="DIR",
                       help="产物目录:tab.json(复用/重跑 split)")
    p_tab.add_argument("--dpi", type=int, default=300, metavar="N",
                       help="渲染 dpi(300-400;默认 300)")
    p_tab.add_argument("--models", default=None, metavar="DIR",
                       help=f"PP-OCR 模型目录(缺省按 {' → '.join(DEFAULT_MODEL_DIRS)} 找)")
    p_dtab = sub.add_parser("diff-tab", help="TAB 草稿×真值 diff(工单50)")
    p_dtab.add_argument("draft", help="recognize-tab 产物 tab.json")
    p_dtab.add_argument("truth", help="dump_tab_truth.dart 导出的真值 JSON")
    p_dtab.add_argument("--start-measure", type=int, default=0, metavar="N",
                       help="草稿窗口起点小节(默认 0,全曲)")
    p_dtab.add_argument("--out", metavar="FILE", help="diff 报告落盘(缺省 stdout 摘要)")
    p_prb = sub.add_parser("probe", help="像素考古探针:组件表+ASCII")
    p_prb.add_argument("image", help="裁图/渲染页 PNG")
    p_prb.add_argument("--x0", type=int, default=0)
    p_prb.add_argument("--x1", type=int, default=None)
    p_prb.add_argument("--y0", type=int, default=0)
    p_prb.add_argument("--y1", type=int, default=None)
    p_prb.add_argument("--ink-max", type=int, default=195)
    p_prb.add_argument("--ascii-step", type=int, default=2)
    p_prb.add_argument("--gray-steps", default=None,
                       help="灰度分层阈(逗号分隔,如 100,180,208)")
    p_prb.add_argument("--widths", action="store_true", help="行宽剖面")
    p_srv = sub.add_parser("serve", help="校对台 web(工单51,localhost)")
    p_srv.add_argument("out_dir", metavar="OUT-DIR",
                       help="识别产物目录(须含 layout/melody/tab.json)")
    p_srv.add_argument("--port", type=int, default=8765, metavar="N",
                       help="监听端口(默认 8765;恒绑 127.0.0.1)")
    p_bev = sub.add_parser("build-evalset", help="构建冻结评测集(工单56)")
    p_bev.add_argument("--tab-gt", required=True, metavar="FILE",
                       help="dump_tab_truth.dart 导出的底稿 JSON")
    p_bev.add_argument("--chords", required=True, metavar="FILE",
                       help="dump_eval_chords.dart 导出的和弦锚 JSON")
    p_bev.add_argument("--corrections", required=True, metavar="FILE",
                       help="裁决修正 JSON(裁片终审记录)")
    p_bev.add_argument("--out", required=True, metavar="FILE",
                       help="冻结评测集落盘路径")
    p_bev.add_argument("--version", type=int, required=True, metavar="N",
                       help="评测集版本号(冻结后改动走新版本)")
    p_ev = sub.add_parser("eval-joint", help="联合事件 F1 评分(工单56)")
    p_ev.add_argument("candidate", metavar="CANDIDATE.json",
                      help="候选草稿(ukeflow.eval.candidate/1)")
    p_ev.add_argument("--evalset", default=None, metavar="FILE",
                      help=f"冻结评测集(缺省包内 {DEFAULT_PATH})")
    p_ev.add_argument("--include-pending", action="store_true",
                      help="待裁定项也入分(默认只评已裁定)")
    p_ev.add_argument("--out", metavar="FILE", help="报告落盘(缺省 stdout 摘要)")
    p_vpr = sub.add_parser("vlm-prepare", help="工单57 输入制备:整谱页拼装+系统裁块")
    p_vpr.add_argument("--pdf", required=True, metavar="FILE",
                       help="曲源 PDF(嵌入位图原生拼装,不重采样)")
    p_vpr.add_argument("--layout", required=True, metavar="FILE",
                       help="split 产物 layout.json(系统 block 坐标)")
    p_vpr.add_argument("--out-dir", required=True, metavar="DIR",
                       help="产物目录(page{N}.png + crop-*.png)")
    p_vpr.add_argument("--score-pages", default="0", metavar="N,N",
                       help="整谱页号(逗号分隔,对应 layout score_pages)")
    p_vpr.add_argument("--systems", default="", metavar="pageN:M",
                       help="裁块清单(逗号分隔,如 page0:0,page1:4)")
    p_vrun = sub.add_parser("vlm-run", help="工单57 VLM 直读单单元")
    p_vrun.add_argument("--image", required=True, metavar="FILE",
                        help="输入位图(整谱页或系统条带 PNG)")
    p_vrun.add_argument("--unit", required=True, metavar="NAME",
                        help="单元名(候选/原始响应/账本按此命名)")
    p_vrun.add_argument("--out-dir", required=True, metavar="DIR",
                        help="运行产物目录(raw/ cand/ ledger.jsonl)")
    p_vrun.add_argument("--model", default=vlm_poc.MODEL_DEFAULT, metavar="M",
                        help=f"模型(默认 {vlm_poc.MODEL_DEFAULT})")
    p_vrun.add_argument("--budget-cny", type=float,
                        default=vlm_poc.BUDGET_CNY_DEFAULT, metavar="N",
                        help=f"预算上限 ¥(默认 {vlm_poc.BUDGET_CNY_DEFAULT};"
                             f"越线告警停止)")
    p_dce = sub.add_parser("dolce-eval", help="工单58③ dolce 整页输出×旋律真值复评")
    p_dce.add_argument("doc", metavar="FILE", help="dolce -f 123 输出文件")
    p_dce.add_argument("--layout", required=True, metavar="FILE",
                       help="工单48 版面切分 layout.json")
    p_dce.add_argument("--score-page", type=int, default=0, metavar="N",
                       help="layout.score_pages 下标(默认 0;p0=印张b1-13)")
    p_dce.add_argument("--start-bars", default=None, metavar="N,N",
                       help="显式印张起始小节,按存活行序(如 p1 灰字锚 14,18,22;"
                            "不给则走结构枚举)")
    p_dce.add_argument("--truth", required=True, metavar="FILE",
                       help="dump_melody_truth 旋律真值 JSON(参照级)")
    p_dce.add_argument("--align-beats", type=float, default=20.0, metavar="N",
                       help="melodyAlignBeats(旋律格→印张格偏移)")
    p_dce.add_argument("--window", default="6-13", metavar="A-B",
                       help="计分印张小节号窗(默认 6-13;p0 布局号==印张号)")
    p_dce.add_argument("--dot-shift", type=int, default=-1, metavar="N",
                       help="印张八度点位移(gs 约定=点数减一,默认 -1)")
    p_vas = sub.add_parser("vlm-assemble", help="工单57 候选合并+过筛标段")
    p_vas.add_argument("--runs-dir", required=True, metavar="DIR",
                       help="vlm-run 产物目录(读 cand/)")
    p_vas.add_argument("--units", required=True, metavar="NAME,NAME",
                       help="参与合并的单元名(逗号分隔)")
    p_vas.add_argument("--out", required=True, metavar="FILE",
                       help="整表候选落盘路径(ukeflow.eval.candidate/1)")
    p_tcd = sub.add_parser("tab-candidate", help="工单59a:tab.json → 候选草稿")
    p_tcd.add_argument("draft", metavar="TAB.json",
                       help="recognize-tab 产物 tab.json")
    p_tcd.add_argument("--out", required=True, metavar="FILE",
                       help="候选落盘路径(ukeflow.eval.candidate/1,已过筛标段)")
    p_org = sub.add_parser("oracle-glyph", help="工单61 m0:真值字形注入草稿")
    p_org.add_argument("pdf", help="曲谱 PDF 路径(位图)")
    p_org.add_argument("--out-dir", required=True, metavar="DIR",
                       help="产物目录:oracle-tab.json(复用/重跑 split)")
    p_org.add_argument("--evalset", default=None, metavar="FILE",
                       help=f"冻结评测集(缺省包内 {DEFAULT_PATH})")
    p_org.add_argument("--variant", default="marks",
                       choices=("marks", "marks+durations"),
                       help="marks=票面主数;marks+durations=时值亦真值(归因)")
    p_org.add_argument("--skeleton", default="split",
                       choices=("split", "repaired"),
                       help="装配骨架:split 原样(幻影界照罚);repaired=按"
                            "映射并幻影 span 的上限诊断(非管线行为)")
    p_org.add_argument("--bar-map", default="gs-aini57", metavar="PRESET",
                       help="系统→真值小节映射:gs-aini57(工单57 冻结映射"
                            "+幻影并合,缺省)| split(按 split 累计小节号)")
    p_org.add_argument("--dpi", type=int, default=300, metavar="N",
                       help="渲染 dpi(300-400;默认 300)")
    p_eml = sub.add_parser("eval-melody", help="工单59a:旋律草稿逐窗跑分")
    p_eml.add_argument("draft", metavar="MELODY.json",
                       help="recognize 产物 melody.json")
    p_eml.add_argument("--truth", required=True, metavar="FILE",
                       help="dump_melody_truth 旋律真值 JSON(参照级)")
    p_eml.add_argument("--out", metavar="FILE", help="报告落盘(缺省 stdout)")
    return parser


def _dolce_eval(args) -> int:
    from . import dolce_poc

    doc_text = open(args.doc, encoding="utf-8").read()
    layout_doc = json.load(open(args.layout, encoding="utf-8"))
    truth = json.load(open(args.truth, encoding="utf-8"))
    lo, hi = (int(x) for x in args.window.split("-"))
    starts = (None if args.start_bars is None
              else [int(x) for x in args.start_bars.split(",")])
    rep = dolce_poc.run_eval(
        doc_text, layout_doc, args.score_page, truth["notes"],
        args.align_beats, lo, hi, dot_shift=args.dot_shift,
        start_bars=starts)
    print(json.dumps(rep, ensure_ascii=False, indent=2))
    return 0


def main(argv=None) -> int:
    args = _build_parser().parse_args(argv)

    try:
        if args.command == "checkup":
            return _checkup(args)
        if args.command == "split":
            return _split(args)
        if args.command == "recognize":
            return _recognize(args)
        if args.command == "diff-melody":
            return _diff_melody(args)
        if args.command == "recognize-tab":
            return _recognize_tab(args)
        if args.command == "diff-tab":
            return _diff_tab(args)
        if args.command == "serve":
            return _serve(args)
        if args.command == "build-evalset":
            return _build_evalset(args)
        if args.command == "eval-joint":
            return _eval_joint(args)
        if args.command == "vlm-prepare":
            return _vlm_prepare(args)
        if args.command == "vlm-run":
            return _vlm_run(args)
        if args.command == "vlm-assemble":
            return _vlm_assemble(args)
        if args.command == "tab-candidate":
            return _tab_candidate(args)
        if args.command == "oracle-glyph":
            return _oracle_glyph(args)
        if args.command == "eval-melody":
            return _eval_melody(args)
        if args.command == "dolce-eval":
            return _dolce_eval(args)
        if args.command == "probe":
            print(probe_image(args.image, args.x0, args.x1, args.y0,
                              args.y1, args.ink_max, args.ascii_step,
                              args.gray_steps, args.widths))
            return 0
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
    sys_warn = sum(len(s["warnings"]) for s in draft["systems"]
                   if s.get("warnings"))
    warn = sum(len(m["warnings"]) for m in draft["measures"]) \
        + len(draft["header"]["warnings"]) + sys_warn
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


def _recognize_tab(args) -> int:
    draft = recognize_tab_pdf(args.pdf, args.out_dir, dpi=args.dpi,
                              models_dir=args.models)
    notes = sum(len(m["notes"]) for m in draft["measures"])
    rests = sum(len(m["rests"]) for m in draft["measures"])
    marks = sum(len(m["x_marks"]) for m in draft["measures"])
    techs = sum(len(m["techniques"]) for m in draft["measures"])
    sys_warn = sum(len(s["warnings"]) for s in draft["systems"]
                   if s.get("warnings"))
    warn = sum(len(m["warnings"]) for m in draft["measures"]) \
        + len(draft["header"]["warnings"]) + sys_warn
    head = draft["header"]
    print(f"{draft['source']['file']}: {notes} 音 / {rests} 休止 / "
          f"{marks} × 证据 / {techs} 记号 / {len(draft['measures'])} 小节")
    print(f"  页眉: key={head['key']} meter={head['meter']}"
          f"(assumed={head['meter_assumed']}) tempo={head['tempo_bpm']}")
    print(f"  警告 {warn} 条(无节奏记号/闭合不齐/弦号未知,见 tab.json)")
    print(f"  产物: {args.out_dir}/tab.json")
    return 0


def _diff_tab(args) -> int:
    with open(args.draft, encoding="utf-8") as fh:
        draft = json.load(fh)
    with open(args.truth, encoding="utf-8") as fh:
        truth = json.load(fh)
    report = diff_tab(draft, truth, start_measure=args.start_measure)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(report, ensure_ascii=False, indent=1) + "\n")
    s = report["summary"]
    acc = s["digit_accuracy"]
    d = report["duration"]
    rs = report["rests"]
    t = report["techniques"]
    fmt = lambda v: f"{v:.3f}" if isinstance(v, float) else str(v)  # noqa: E731
    print(f"窗口自小节 {args.start_measure}:配对 {s['digit_matched']} 对"
          f"(草稿 {s['draft_notes']} 音,同弦错位 {s['string_mismatch']})")
    print(f"  数字正确率 {s['digit_ok']}/{s['digit_matched']} = {fmt(acc)}"
          f"  时值 {d['ok']}/{d['compared']}")
    print(f"  休止 P={fmt(rs['precision'])} R={fmt(rs['recall'])}"
          f"(tp {rs['tp']} / fp {rs['fp']} / fn {rs['fn']};"
          f"全小节休止 {rs['whole_bar_not_in_truth']} 不在真值模型,单列)")
    print(f"  技巧 F1={fmt(t['f1'])}(P={fmt(t['precision'])} "
          f"R={fmt(t['recall'])};tp {t['tp']} / fp {t['fp']} / fn {t['fn']})")
    for k, v in sorted(t["by_kind"].items()):
        if v["tp"] or v["fp"] or v["fn"]:
            print(f"    {k}: tp {v['tp']} fp {v['fp']} fn {v['fn']}"
                  f" F1={fmt(v['f1'])}")
    hot = report["hotspots"]
    print(f"  热点 {len(hot)} 条:")
    for h in hot[:8]:
        print(f"    {h['field']}@b{h.get('beat', '?')}"
              f"(弦{h.get('string', '?')}) 草{h.get('draft')}/真{h.get('truth')}")
    if args.out:
        print(f"  报告: {args.out}")
    return 0


def _serve(args) -> int:
    out = Path(args.out_dir)
    missing = [f for f in ("layout.json", "melody.json", "tab.json")
               if not (out / f).is_file()]
    if missing:
        print(f"{out}: 缺 {'、'.join(missing)}——先跑 split/recognize/"
              "recognize-tab 生成识别产物", file=sys.stderr)
        return 2
    from .webapp import create_app
    app = create_app(str(out))
    print(f"校对台:http://127.0.0.1:{args.port}/ ({out};Ctrl-C 退出,"
          "状态即改即存 proof.json)")
    app.run(host="127.0.0.1", port=args.port, debug=False)
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



def _build_evalset(args) -> int:
    with open(args.tab_gt, encoding="utf-8") as fh:
        tab_gt = json.load(fh)
    with open(args.chords, encoding="utf-8") as fh:
        chords = json.load(fh)
    with open(args.corrections, encoding="utf-8") as fh:
        corrections = json.load(fh)
    doc = build_evalset(tab_gt, chords, corrections, args.version,
                        corrections.get("date", ""))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n",
                   encoding="utf-8")
    from .eval_truth import ledger_stats, validate_evalset
    validate_evalset(doc)
    led = ledger_stats(doc)
    cols = doc["payload"]["columns"]
    by_seg = {}
    for c in cols:
        by_seg[c.get("segment")] = by_seg.get(c.get("segment"), 0) + 1
    print(f"评测集 v{doc['version']} → {args.out}(payload sha256 "
          f"{doc['payload_sha256'][:12]}…)")
    print(f"  列 {len(cols)} / 事件 {doc['meta']['event_count']}:"
          + " ".join(f"{k or '无段'}={v}" for k, v in by_seg.items()))
    print(f"  台账:已裁定列 {led['columns']['adjudicated']} / "
          f"待裁定列 {led['columns']['pending']} / "
          f"方向未核 {led['pending_direction_slots']} 槽 / "
          f"可评事件覆盖率 {led['coverage_of_scorable_events']:.0%}")
    for u in led["uncovered"]:
        print(f"  未覆盖: {u['from_beat']}–{u['to_beat'] or '∞'} {u['desc']}")
    return 0


def _eval_joint(args) -> int:
    # DEFAULT_PATH 相对包根(tools/score_workbench/,evalset/ 在彼处)
    path = args.evalset or str(
        Path(__file__).parent.parent / DEFAULT_PATH)
    doc = load_evalset(path)
    with open(args.candidate, encoding="utf-8") as fh:
        cand = json.load(fh)
    report = joint_report(doc, cand, include_pending=args.include_pending)
    if args.out:
        Path(args.out).write_text(
            json.dumps(report, ensure_ascii=False, indent=1) + "\n",
            encoding="utf-8")
    ev, sy = report["events"], report["symbols"]
    print(f"{Path(args.candidate).name} × 评测集 v{doc['version']}"
          f"(τ={report['tol_beat']} 拍,和弦锚={report['chords_used']})")
    print(f"  事件层: tp={ev['tp']} fp={ev['fp']} fn={ev['fn']} "
          f"P={ev['precision']} R={ev['recall']} F1={ev['f1']:.4f} "
          f"(节奏错 {ev['rhythm_miss']['count']})")
    print(f"  符号层: tp={sy['tp']} fp={sy['fp']} fn={sy['fn']} "
          f"F1={sy['f1']:.4f}")
    sp = report["diagnostics"]["spatial"]
    if sp["n"]:
        print(f"  空间漂移诊断(另报):n={sp['n']} "
              f"平均|Δ拍|={sp['mean_abs_beat']} 最大={sp['max_abs_beat']}")
    for seg, r in report["per_segment"].items():
        print(f"    [{seg}] F1={r['f1']:.4f} (tp={r['tp']} fp={r['fp']} "
              f"fn={r['fn']})")
    g = report["gate"]
    print(f"  晋级线(事件 F1≥0.90):{'PASS' if g['pass'] else '未过'}"
          f"(F1={g['events_f1']:.4f})")
    if report["expansion_warnings"]:
        print(f"  展开告警 {len(report['expansion_warnings'])} 条"
              f"(详见报告)", file=sys.stderr)
    return 0




def _vlm_prepare(args) -> int:
    import json as _json
    with open(args.layout, encoding="utf-8") as fh:
        layout = _json.load(fh)
    pages = [int(x) for x in args.score_pages.split(",") if x]
    made = vlm_poc.prepare_pages(args.pdf, layout, pages, args.out_dir)
    for m in made:
        print(f"整谱页 → {m}")
    if args.systems:
        specs = [s.strip() for s in args.systems.split(",") if s.strip()]
        for m in vlm_poc.prepare_crops(args.out_dir, layout, specs,
                                       args.out_dir):
            print(f"系统条带 → {m}")
    return 0


def _vlm_run(args) -> int:
    cand = vlm_poc.run_image(args.image, args.unit, args.out_dir,
                             model=args.model, budget_cny=args.budget_cny)
    meta = cand["meta"]
    if meta["finish_reason"] not in ("stop", None):
        print(f"⚠ finish_reason={meta['finish_reason']}(输出可能被截断,"
              f"原始响应见 raw/)", file=sys.stderr)
    return 0


def _vlm_assemble(args) -> int:
    units = [u.strip() for u in args.units.split(",") if u.strip()]
    vlm_poc.assemble(args.runs_dir, units, args.out)
    return 0


def _oracle_glyph(args) -> int:
    from .oracle_glyph import GS_AINI_BAR_MAP, build_oracle_tab

    path = args.evalset or str(
        Path(__file__).parent.parent / DEFAULT_PATH)
    doc = load_evalset(path)
    bar_map = GS_AINI_BAR_MAP if args.bar_map == "gs-aini57" else None
    tab_doc = build_oracle_tab(args.pdf, args.out_dir, doc,
                               variant=args.variant, dpi=args.dpi,
                               bar_map=bar_map, skeleton=args.skeleton)
    al = tab_doc["oracle"]["alignment"]
    stem = "oracle-tab" + ("-durations" if args.variant != "marks" else "") \
        + ("-repaired" if args.skeleton != "split" else "") + ".json"
    print(f"{Path(args.pdf).name} × oracle({args.variant},"
          f"{args.skeleton}) → {Path(args.out_dir) / stem}")
    print(f"  对齐:配对 {al['n_pairs']} / 多余 attack {al['n_extra']} / "
          f"漏检列 {al['n_missed']};注入记号 {al['n_injected']}"
          f"(坏记号 {len(al['bad_marks'])})")
    for b in al["bars"]:
        if b["n_extra"] or b["n_missed"]:
            print(f"    bar {b['bar']}: attack {b['n_attacks']} / 列 "
                  f"{b['n_cols']} / 配 {b['n_pairs']}(+{b['n_extra']}extra "
                  f"-{b['n_missed']}missed {b['missed_beats']})")
    print("  下一步: tab-candidate <oracle-tab*.json> --out …;eval-joint …")
    return 0


def _tab_candidate(args) -> int:
    from .draft_candidate import scope_and_store, tab_to_candidate

    with open(args.draft, encoding="utf-8") as fh:
        tab_doc = json.load(fh)
    cand, notes = tab_to_candidate(tab_doc)
    merged = scope_and_store(cand, args.out)
    skip = notes["skip"]
    print(f"{Path(args.draft).name} → {args.out}(scope 过筛后 "
          f"{len(merged['columns'])} 列 / {len(merged['rests'])} 休止)")
    print(f"  跳记号: barline {skip['barline']} / slide {skip['slide']}"
          f"(无端点)/ ellipse {skip['ellipse']};"
          f"ties/slides 留空(50 不读,漏报照实计)")
    if notes["tech_conflicts"]:
        print(f"  同拍 tech 冲突 {len(notes['tech_conflicts'])} 条"
              f"(优先级保优,详候选 warnings)")
    return 0


def _eval_melody(args) -> int:
    from .draft_candidate import melody_draft_attacks, melody_window_scores

    with open(args.draft, encoding="utf-8") as fh:
        melody_doc = json.load(fh)
    with open(args.truth, encoding="utf-8") as fh:
        truth_doc = json.load(fh)
    attacks, n_unknown = melody_draft_attacks(melody_doc)
    reps = melody_window_scores(attacks, truth_doc)
    report = {
        "schema": "ukeflow.eval.melody_baseline/1",
        "tool_version": __version__,
        "authority": "reference",
        "authority_note": "真值=dump_melody_truth(App 纯旋律,参照级;"
                          "非 56 TAB 冻结闸,不得混称)",
        "n_unknown_degree_slots": n_unknown,
        "n_cand_attacks": len(attacks),
        "windows": {k: v for k, v in reps.items()},
    }
    if args.out:
        Path(args.out).write_text(
            json.dumps(report, ensure_ascii=False, indent=1) + "\n",
            encoding="utf-8")
    print(f"{Path(args.draft).name} × dump_melody_truth"
          f"(参照级,align={truth_doc['melodyAlignBeats']:g};"
          f"草稿 {len(attacks)} 攻击 / unknown 槽 {n_unknown})")
    for name, r in reps.items():
        p = f"{r['precision']:.3f}" if r["precision"] is not None else "—"
        rc = f"{r['recall']:.3f}" if r["recall"] is not None else "—"
        print(f"  [{name}] F1={r['f1']:.4f} P={p} R={rc} "
              f"(tp={r['tp']} fp={r['fp']} fn={r['fn']} "
              f"τ={r['tau']} 真{r['n_truth']}/读{r['n_cand']})")
    if args.out:
        print(f"  报告: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
