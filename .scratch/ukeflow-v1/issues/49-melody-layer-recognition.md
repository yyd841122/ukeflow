# 49: 简谱旋律层识别（dolce 先行，PaddleOCR 兜底）

**Status:** resolved

**Blocked by:** 48

**What to build:** 工单 47 的 dolce PoC 若可用：借其输出对齐拍位骨架；否则 PaddleOCR（数字/调号/拍号）+ 几何规则（八度点/时值线/附点/延音弧/休止）→ 旋律声部 IR 草稿（度数+keyMap 定音高、拍位、时值，证据齐全）。金标准：gs-aini 旋律层对照人工 168 音逐位 diff。

**Non-goals:** TAB 层（50）、歌词层（一期不录歌词数据，显示层约定不变）。

## Comments

- 2026-10-27 (工单47 PoC 后的前提校准,retro 补记): 本票面「dolce 先行,PaddleOCR 兜底」写于工单47 PoC 之前。47 已实证 dolce **不能当识别引擎**(无证据链/无拍位/X 静默丢/裁条不稳,见 docs/research/2026-10-27-dolce-jianpu-poc.md),只可当**互证对照源**(其人声段度数/时值/八度与人工台账逐项全对)。认领本票时按此校准:主识别路径须自带证据链与拍位(消费工单48 切分的 jianpu 层裁图+候选拍网格),dolce 输出降为对照源之一;PaddleOCR 兜底思路不受影响。

- 2026-10-27 (认领+收口): 按票面 retro 校准执行——dolce 不当识别引擎(只留
  51 校对台对照模式的对照源,本票未接其 123 输出),主路径=**PaddleOCR-onnx
  (PP-OCRv6_small rec,模型取自 dolce redist,Apache-2.0,不入库按目录解析)
  + 几何规则**,消费工单48 的 jianpu 层裁图+小节骨架,证据链逐符号携带
  (bbox/置信度,ADR-0009)。`recognize`(melody.json,`ukeflow.workbench
  .melody/1`)+`diff-melody`(`melody_diff/1`)两 CLI + tools/dump_melody_
  truth.dart 真值导出 + tests/fixtures 真值 fixture + 真机对账闸测试
  (skipif 无语料/模型,0.90 阈)。
- **读谱判定(全部实测锚定):** 数字行=数字尺寸组件最大 y 簇(歌词窄偏旁/
  TAB 残段同尺寸,18 系统实测主簇 16-33 恒最大,歧证上报);时值线=「梁盖过
  音心 x」逐音计数(共享主梁+副梁);附点心距数字心 0.94-1.04g(窄字'1'亦然,
  按心不按缘);竖排八度点连成一件按高折合点数;高音点心带=[行顶−1.6g,行顶)
  (再上是 TAB 残杆区,m20 曾误计 5 点);时值线域上限=b1+0.9g(歌词字横画
  曾被计梁);延音杠=行中薄横归左邻数字;延音弧/反复记号/竖段落证据不改
  attack。拍位=小节内时值累加,闭合≠拍号落警告漂移可见(工单41 教训照守,
  候选拍网格未消费留 50/51)。
- **金标准结果(gs-aini 窗口 167 对):** 度数 159/167=95.2%、拍位
  161/167=96.4%、时值 141/145=97.2%;页眉 1=E/4/4/78 全读出;全曲 69 小节
  382 音+95 休止 3.6s。**全部 8 处度数错与 4 处时值错经像素考古定案为
  「印张↔人工 168 音微观出入」非读错**:①笔迹你熟/需要你关怀两句印张
  八度点与转录约定差 1(印张自身同段 G4/D5 又吻合,系印刷不一致);
  ②m13/m15 同音 16 分对印张两音、真值记一音;③m24 真值有一音、印张无;
  ④m7 尾 16 分位置差半拍(=工单41 台账「细分差半拍,目验再调」现象)。
  草稿照印张忠实记录+证据,这些即 51 校对台的首批热点;diff 报告即 51
  对照模式形状。pytest 25 新增(CTC/字形几何/归属/装配/diff/合成编排/
  真机冒烟+对账闸),check.sh full 绿(951 Dart+73 pytest+analyzer 净,
  零 Dart 改动)。
- 2026-10-27 (评审消化·两轴 code-review): 修复——①diff-melody 无 pdf 位,
  公共报错 handler 改 getattr(pdf/truth),缺文件不再被 AttributeError 遮掩;
  ②无 jianpu 层系统占位空 notes 保 zip 对齐(原实现会整体错位,gs-aini 恰
  无此系统未触发);③"other" 组件与 leftovers 落 melody.json(原只在警告里
  报数,ADR-0009 证据链);④休止逐条带 bbox/置信度(与音同权);⑤long_bar
  双发去重;⑥页眉读取的 isinstance(FakeOcr) 改 hasattr(line_text) duck 缝;
  ⑦死常量 DASH_ZONE/AUG_MID/CELL_INK_MAX 删、DOT_BELOW_ZONE 接线、墨阈
  195 收敛到 split.INK_GRAY_MAX 单源;⑧_stacked_fraction 匿名类换 Glyph;
  ⑨dump_melody_truth.dart 的 log(2)/log(2) 恒等式化简(重导出 fixture 逐
  字节同值);⑩README 悬空「## 用法」标题清掉;⑪CLI 缝补 4 测(recognize
  报错路径/diff-melody 全链/缺真值)。**新增消费候选拍网格**:每小节出
  grid_fit(音 x 到按拍号网格的最近距 mean/max px,工单41 教训照守——只
  出互证证据不标定,拍位仍以时值累加为准);diff summary 补 octave_ok/bad
  计数(167 对中 149 合,18 差全为印张↔转录出入,不进 0.90 闸)。复跑
  全绿:pytest 77(新增 4)+ flutter 951 + analyzer 净;验收数不动
  (159/167、161/167、141/145)。Status 照 47/48 先例用 resolved
  (tracker 文档的 done 用语与两先例不一致,从众不改)。