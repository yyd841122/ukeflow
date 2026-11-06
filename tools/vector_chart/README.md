# vector_chart — 矢量谱页解析(票01,ADR-0011)

谱站 alphaTab 整页渲染 HTML(矢量谱页)→ 识谱源 ScoreIR JSON。
规则与「已钉事实」见 `.scratch/vector-chart-import/issues/01-tiankongzhicheng-e2e.md`,
架构决策见 `docs/adr/0011-vector-score-page-source.md`。

## 用法

```bash
# 解码(默认在仓库样本上;文件 UTF-16LE 或 UTF-8 均可)
python3 -m vector_chart.cli decode ~/ukeflow-sources/vector-pages/tiankongzhicheng.html \
    --out /tmp/tiankong.scoreir.json --report /tmp/tiankong.report.md

# 测试(纯 stdlib + pytest)
python3 -m venv .venv && .venv/bin/pip -q install pytest
.venv/bin/python -m pytest tests/ -q
```

## 模块

- `page.py`:HTML → 元素模型(text/rect/path,含 bbox 与字体分类)
- `decode_tab.py`:四线 TAB 版面 → 小节/列/音/时值/和弦/卷弦(票01 规则集)
- `score_ir.py`:内部模型 → ScoreIR JSON(schemaVersion 1,与
  `lib/core/import/score_ir.dart` 逐字段对齐)
- `gate.py`:体检闸(校验器规则镜像:拍长闭合/弦品合法/midi 一致/红旗清单)
- `cli.py`:decode 子命令,产 JSON + 人读报告

## 边界

- 只支持「四线 TAB 型」矢量谱页(天空之城型);弹唱谱型(萱草花)在票03。
- 证据 = SVG 坐标(bbox,page=系统号),source 标 vector-page;
  不产渲染裁片(可选后置)。
