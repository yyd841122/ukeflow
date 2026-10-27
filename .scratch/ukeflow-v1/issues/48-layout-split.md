# 48: 版面切分（四层条带 + 小节 + 拍位网格）

**Status:** resolved

**Blocked by:** 47

**What to build:** 位图路径：300-400dpi 渲染 → 倾斜纠正 → 按谱全版式规则切四层条带（和弦图+和弦名 / TAB / 简谱 / 歌词）→ 小节线定位 → 每小节候选拍位 x 网格。像素考古结论直移（页宽 993×1404、tabLineGap≈14px@scale3；读谱约定见工单 39 与 docs/research/2026-10-25-pdf-census-gs-aini.md）。输出：逐系统逐层裁图 + 小节/拍位骨架 JSON，bbox 证据全程携带。

**Non-goals:** 符号识别、矢量 PDF 路径。

## Comments

- 2026-10-27 (收口): `tools/score_workbench/split.py` 落地(渲染 300-400dpi→纠偏→
  系统检测→内容感知分块→组件级分层→小节线/候选拍网格→`ukeflow.workbench.layout/1`
  + 逐系统逐层裁图;CLI `split` 子命令,pytest 46 绿含双真机冒烟,flutter 951 绿
  analyzer 净零 Dart 改动)。真机实数:gs-aini 18 系统/69 小节/25 段记号/102 裁图,
  gs-bbw 16 系统/66 小节/96 裁图(末谱页空,半幅末系统 trunc 标志)。
- **版式真相(纠工单41/47 的系统计数):** 谱全了 PDF 每页 = 2×2 排 4 条
  993×1404 位图 = **上下两个整谱页**,系统通栏跨左右两半(左半 x137..992 + 右半
  x0..853 拼合)。工单47 检出的 aini 17/bbw 15 组是「左右同高配对行」数:75% 全宽
  行检漏掉无右半配对的**半幅末系统**(aini sp6 y572、bbw sp5 y1300),物理系统实为
  **aini 18、bbw 16**。工单41 人工普查的「17 系统」同源同漏,台账按 18 系统读。
  行判据降为 ≥30% 页宽 + 等距四线验证后全数检出。
- **每系统条带模型(像素考古定案):** 自上而下 = 段落标注(小字 h≈13,语义未考,
  annotation 层带 bbox)/ 和弦图(52×54 框,含指法点)/ 和弦名(h≈19-25)/
  TAB(谱线 4 根 gap15.5 + 上探梁杆 + 下探扫弦箭头)/ 简谱(数字 14×20 + 八度点 +
  时值线 h2-3)/ 歌词(h≈18-31,每系统一行;无歌词=间奏类 6 系统)。分块切缝=
  「本系统时值线底与下系统段标注间最大空行隙」中点,页眉(标题/调号行)在块外。
- **小节线判据三折:** ①贯穿谱高竖线(census 直移)+ 上/下延 ≤0.5g 排箭头;
  ②线与密集段长音杆同为 4px 厚、厚度不可判,靠延伸闸+迭代 10g 最小节宽清理
  (真小节最窄 12g、census 最窄 23g;杆距≈1/4 小节);③双线/段落线 ≤0.8g 并名
  义界,被清界的归 `non_measure_marks`(证据不丢)。逐小节不等宽实证(445/398/
  451/413),拍位只出 {2,3,4,6,8} 拍等分候选网格不标定——工单41 无锚标定撞墙
  教训照守,拍位定案留给 49/50 识别证据+人工锚。
- Non-goals 未越界:零符号识别(数字/和弦名/歌词内容全部未读),零矢量路径。
- 2026-10-27 (评审消化·两轴 code-review): 修复——①split_pdf 加双闸:非位图
  (零位图对象或矢量谱特征)与 dpi 越界 300-400 大声 ValueError(闸=「有位图且非
  矢量谱特征」而非 triage 的 0.5 覆盖率线,半页位图合法输入 FP 0.4999 不误触;
  仓库先例 override 报错,替换原静默钳制);②MIN_MEASURE docstring 6g→10g 对齐;
  ③split_page_systems 注解 -> dict;④split 的 GAP_MIN/MAX 换名 TAB_GAP_MIN/MAX
  (与 layout.py 同名异值,共导入会踩);⑤LAYER_KINDS 单源化(内联字面删除);
  ⑥report.py 删 _sha256 别名,triage 直用 sha256_file;⑦测试画布工厂按仓约定挪
  conftest(sb_* 前缀,SW/SH 避与 triage fixture 的 W/H 混);⑧CLI 弱断言
  "3" in text 改「检出 3 系统」;⑨layout.py 行判据 0.75→0.30+等距窗扫(真机实数
  aini 18/notation 0、bbw 16,triage 版面信号与切分对齐;五线谱=第5线延续等距,
  杂行不算)。保留(可辩护超集,已记 GLOSSARY「切分层」):四层首层拆
  chord_diagram/chord_name 两子层 + annotation 证据行(段落标注语义未考);
  五线谱跳过、truncated、non_measure_marks 皆证据携带。GLOSSARY 补「整谱页/
  切分层」两词条。判断题未动:编排内部裸 dict(即转 JSON 的管道)、Measure 内嵌
  beat_grids dict(JSON 形状直通)、merge-runs 形状 layout/split 各持(47 票
  已收口,不为此翻新)。pytest 47 绿(新增矢量/越界 dpi 拒绝测试)。
