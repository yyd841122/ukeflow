# score_workbench — 识谱工作台骨架(工单47,dev-only)

谱面体检(矢量/位图)+ 谱型判别(solo/strum/image/vector)+ 分流报告 JSON。
只分流不识别:符号识别是工单 48-50,校对台是 51;矢量谱遇到只报告不处理。

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
/tmp/swwenv/bin/python -m pytest tests/ -q                                # 全部测试
```

## 报告形状(`ukeflow.workbench.triage/1`)

`checkup`(对象层信号)+ `layout`(位图版面信号,矢量谱为 null)+ `classification`
(`score_type`/`disposition`/`reasons[]`,人工改判时 `auto_type`/`overridden`)。
分流去向:`solo→process`(完整识谱管线)、`strum|image→archive`(归档图片谱待识别)、
`vector→report_only`。

## 模块

- `classify.py` — 谱型判别缝(spec 实现决策7):信号→判定的纯函数,fixture 特征驱动
- `checkup.py` — 体检①:PDF 对象层(文本层/位图覆盖率/矢量指令,PyMuPDF)
- `layout.py` — 版面信号:scale3 渲染→四线谱系统/文本带/简谱证据(几何档案 census 直移)
- `report.py` — 编排+报告;`cli.py` — argparse 入口

## 几何基线

谱全了曲源 = 每页 4 条全宽位图带(993×1404/条)、零文本层零矢量;scale3 渲染弦距
14px。谱线检测用「行墨量 ≥75% 页宽 @灰度235」(连续 run 判据被字形白晕打断,实测漏检)。
