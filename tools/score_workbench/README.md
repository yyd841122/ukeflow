# score_workbench — 识谱工作台(工单47/48,dev-only)

谱面体检(矢量/位图)+ 谱型判别(solo/strum/image/vector)+ 分流报告 JSON +
**版面切分**(工单48:逐系统逐层裁图 + 小节/拍位骨架)。
符号识别是工单 49-50,校对台是 51;矢量谱遇到只报告不处理。

## 搭建

```sh
python3 -m venv /tmp/swwenv           # venv 路径随意,/tmp 惯例同 pdf_census
/tmp/swwenv/bin/pip install -r requirements.txt
cd tools/score_workbench              # 以下命令均在此目录跑
```

## 用法

```sh
PY=/tmp/swwenv/bin/python
$PY -m score_workbench.cli checkup ~/ukeflow-sources/gs-aini.pdf          # 只体检
$PY -m score_workbench.cli triage  ~/ukeflow-sources/gs-aini.pdf          # 判别,JSON → stdout
$PY -m score_workbench.cli triage  x.pdf --out report.json                # 报告落盘
$PY -m score_workbench.cli triage  x.pdf --type strum --out report.json   # 人工改判(ADR-0009)
$PY -m score_workbench.cli split   x.pdf --out-dir out/layout             # 版面切分(48)
$PY -m score_workbench.cli split   x.pdf --out-dir out/layout --dpi 350   # 300-400dpi
/tmp/swwenv/bin/python -m pytest tests/ -q                                # 全部测试
```

## 报告形状

- `triage`:`ukeflow.workbench.triage/1` — `checkup`(对象层信号)+ `layout`
  (位图版面信号,矢量谱为 null)+ `classification`(`score_type`/`disposition`/
  `reasons[]`,人工改判时 `auto_type`/`overridden`)。分流去向:`solo→process`
  (完整识谱管线)、`strum|image→archive`(归档图片谱待识别)、`vector→report_only`。
- `split`:`ukeflow.workbench.layout/1` — `source`(sha256/dpi)+ `deskew`(逐页角)
  + `score_pages[]`(谱全了每 PDF 页 2×2 位图=上下两个整谱页)→ 每系统 `staff`/
  `block`/`layers{}`(bbox+crop 路径,六层:tab/chord_diagram/chord_name/jianpu/
  lyrics/annotation)/`measures[]`(左右界证据+各拍数假设的候选拍位网格)/
  `non_measure_marks[]`(段落双线等,证据保留)。bbox 全程携带(渲染 px)。
  产物:`layout.json` + `crops/p<页>h<半>s<序>_<层>.png`。

## 模块

- `classify.py` — 谱型判别缝(spec 实现决策7):信号→判定的纯函数,fixture 特征驱动
- `checkup.py` — 体检①:PDF 对象层(文本层/位图覆盖率/矢量指令,PyMuPDF)
- `layout.py` — 版面信号:scale3 渲染→四线谱系统/文本带/简谱证据(几何档案 census 直移)
- `split.py` — 版面切分(工单48):纠偏→系统检测→内容感知分块→组件级分层→
  小节线/候选拍网格→裁图+骨架 JSON
- `report.py` — 编排+报告;`cli.py` — argparse 入口

## 几何基线(像素考古档案,工单39/41/48 实测)

谱全了曲源 = 每 PDF 页 2×2 排 4 条 993×1404 位图(上下两个整谱页,系统通栏);
scale3 渲染弦距 14px(原生位图 15.5px)。谱线检测用「行墨量 ≥30% 页宽 @灰235 +
等距四线验证」(工单47 的 75% 全宽判据会漏半幅末系统)。每系统条带自上而下 =
段落标注(小字 h≈13)/ 和弦图(框 52×54)/ 和弦名(h≈19-25)/ TAB(谱线+梁杆+
扫弦箭头)/ 简谱(数字 14×20+八度点+时值线)/ 歌词(h≈18-31)。小节线=贯穿谱高
竖线(上/下延 ≤0.5g;箭头与长音杆越线被排;线杆同厚 4px,厚度不可判);逐小节
不等宽(实测同系统 445/398/451/413),拍位只出候选拍网格不标定(工单41 教训:
无锚标定撞墙,锚留给 49/50 识别证据+人工)。
