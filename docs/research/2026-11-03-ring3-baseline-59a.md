# 第三环基线:49/50 管线 × 评分器「不训练」分数表(工单 59a,ADR-0010 追记二)

2026-11-03。目的:为工单 61(格子分类器)全部里程碑提供**对照锚与采纳门
基线**——采纳门 = per-layer/section 对本表非回归 + 校对时间不劣化。本表
全部由 48/49/50 现有确定性管线产出,零训练、零合成数据。

## 方法(管线链与适配契约)

```
split(48) → recognize(49)→ melody.json ─→ eval-melody ──→ 逐窗 melody_score
         → recognize-tab(50)→ tab.json → tab-candidate → eval-joint(56 评分器)
                                              ↓
                              cand-tab.json(ukeflow.eval.candidate/1,过筛标段)
```

适配在候选侧(`draft_candidate.py`),评分器零改动(工单 56 纪律):

- **TAB**:tab.json 逐拍聚列(同 attack 数字/×/技巧共享 beat);时值持续窗
  重算与真值同规(至下一 attack/休止截断、曲尾封顶 108 拍);scope/标段复用
  57 的 `scope_filter`(已裁定拍段 0-36+80-108);× 展开用真值和弦锚
  (eval-joint 内置,报告注明 `chords_used=truth(frozen)`)。50 不读的记号
  不伪造:ties/slides 留空(符号层照实计 FN),barline×59/slide×7(无端点)/
  ellipse×1 跳过入 warnings;同拍 tech 冲突 43 条按优先级
  (roll>strumUp/strumDown>tremolo:具体字形>泛化定向>近邻挂靠)保优记账;
  弦号未知
  的记号照落(string=None)计 FP 不静默。
- **旋律**:melody.json → dolce_poc.Attack(melody_score 与 58③ dolce 复评
  **同尺同函数**);midi 折算沿用 melodic_diff 净点数式(印张点数=应用+1,
  工单 39 实测);拍位按小节网格锚定(4×全曲小节序+小节内拍),read_beats
  累加漂移不进拍位。**authority=reference**:真值是 dump_melody_truth(App
  纯旋律 168 音,真机听验参照级)——**非 56 TAB 冻结闸,不得混称**(票面
  纪律;56 评测集是 TAB 层,324 事件中 digit 仅 7)。

**对齐假设验证**(小节序=印张小节号,48 layout 全曲小节序):草稿 melody
小节 idx5-8 逐小节音数 8/7/10/4 与真值旋律 bar1-4(=印张 b6-9)逐数吻合;
TAB 同一 layout 同锚定。句法上主歌段连音数都一致,无系统性错位。

## 分数表

### TAB 层(eval-joint × 冻结评测集 gs-aini-tab-v1,payload sha256 034d42c42c98…,已裁定范围 115 列/324 事件,τ=1/32)

| 层 | tp | fp | fn | P | R | **F1** |
|---|---|---|---|---|---|---|
| 事件层(弦品+起音+时值三全对) | 39 | 128 | 285 | 0.234 | 0.120 | **0.1589** |
| 印张符号层(×/数字/技巧/休止) | 36 | 95 | 83 | 0.275 | 0.303 | **0.2880** |

事件层 per-segment:

| 段 | tp | fp | fn | F1 |
|---|---|---|---|---|
| intro(b2-5 前奏) | 12 | 24 | 29 | 0.3117 |
| verse-a(b6-9 主歌) | 0 | 58 | 55 | **0.0000** |
| chorus(b21-27 副歌+尾段) | 27 | 46 | 201 | 0.1794 |

诊断(另报,不进 F1):空间漂移 19 处(平均|Δ拍|=0.25,最大 1/4——拍位累加
在错漏处级联的形态);节奏错(配上但时值不对)71;休止:候选 @(0,4)+@(6,½)
vs 真值 @(0,4)+@(7,½)——@6 那枚错位一拍;展开告警 0。**晋级线(TAB 联合
事件 F1≥0.90):未过**(0.1589)。

互证量级(57 VLM 同尺):整页 0.1905/0.1905、裁块 0.1924/0.3025(事件/符号)
——50 规则管线(0.1589/0.2880)与 VLM 同档,规则管线的「近聋」由分数坐实:
8 音/347 × 证据/217 记号里只捞到 39 个全对事件。

### 旋律层(melody_score × dump_melody_truth,**参照级**)

| 窗(印张小节) | 真值音 | 候选 | tp | fp | fn | **F1** | dolce 58③ 参照 |
|---|---|---|---|---|---|---|---|
| verse-a(b6-9) | 29 | 29 | 23 | 6 | 6 | **0.7931** | — |
| chorus(b21-27) | 61 | 52 | 19 | 33 | 42 | **0.3363** | — |
| 58p0(b6-13) | 57 | 57 | 46 | 11 | 11 | **0.8070** | 0.842 |
| 58p1(b14-24) | 86 | 76 | 49 | 27 | 37 | **0.6049** | 0.856 |
| full(b6-27) | 168 | 161 | 107 | 54 | 61 | **0.6505** | — |

失败模式分解(full 窗,拍位 τ=1/32 内按 onset 配对):真值 168 音中 148
(88.1%)拍位配上;配上 148 中音高全对 107、**八度点 ±1 翻转 16**
(+12×11 / −12×5,≈9.5%)、度数错 25;真值未配上 20(拍位错或漏读);
候选多出 13。unknown 度数槽 0(全曲 382 攻击无一弃读)。

判读:49 管线旋律层低于 dolce 互证源(p1 差 0.25),弱区与 dolce 同构——
副歌高置段(印张双点区)F1 崩到 0.336,八度点仍是主犯(16 翻)但**度数错
25 是 49 管线特有**的次犯(dolce 无此模式)。

## 对 61 的锚定意义

- 采纳门的逐层逐段锚即本表:61 各里程碑跑同一 `eval-joint`/`eval-melody`
  链,per-layer/section 不得低于本表,校对时间不劣化。
- **m0(oracle-glyph 天花板)的问题现在有量化语境**:50 管线在 verse-a 段
  事件 F1=0——× 拨痕段全部展开错,说明瓶颈不只在字形识别,更在 ×→音的
  拍位/和弦锚联动;oracle 实验(冻结真值当正确字形过同一管线)将把「字形
  全对时还剩多少」从这个问题里剥出来。
- 符号层(0.288)>事件层(0.159)的缺口 = 展开/时值解释的损失,即 57 结论
  「混合路须外部拍位骨架锚定」在本管线的对应形态。

## 复现

```sh
cd tools/score_workbench
PY=.venv/bin/python
$PY -m score_workbench.cli recognize ~/ukeflow-sources/gs-aini.pdf \
    --out-dir ~/ukeflow-sources/baseline-59a/layout
$PY -m score_workbench.cli recognize-tab ~/ukeflow-sources/gs-aini.pdf \
    --out-dir ~/ukeflow-sources/baseline-59a/layout
$PY -m score_workbench.cli tab-candidate ~/ukeflow-sources/baseline-59a/layout/tab.json \
    --out ~/ukeflow-sources/baseline-59a/cand-tab.json
$PY -m score_workbench.cli eval-joint ~/ukeflow-sources/baseline-59a/cand-tab.json \
    --out ~/ukeflow-sources/baseline-59a/eval-tab.json     # 包内评测集缺省已修
cd ../.. && dart run tools/dump_melody_truth.dart > ~/ukeflow-sources/baseline-59a/melody-gt.json
cd tools/score_workbench
$PY -m score_workbench.cli eval-melody ~/ukeflow-sources/baseline-59a/layout/melody.json \
    --truth ~/ukeflow-sources/baseline-59a/melody-gt.json \
    --out ~/ukeflow-sources/baseline-59a/eval-melody.json
```

原始产物(仓库外,不入 git):`~/ukeflow-sources/baseline-59a/`
(layout/{melody,tab,layout}.json、cand-tab.json、eval-tab.json、
eval-melody.json、run.log)。

## 落地物

- `tools/score_workbench/score_workbench/draft_candidate.py`:59a 适配层
  (tab→candidate 聚列/时值重算/scope 复用/冲突优先级记账;melody→Attack
  同尺适配+逐窗驱动)。
- CLI:`tab-candidate`(tab.json → 候选落盘)、`eval-melody`(逐窗跑分,
  报告带 authority=reference 标注)。
- `eval-joint` 缺省评测集路径修复(`Path(__file__).parent.parent`,此前
  57 起一直靠显式 `--evalset`,缺省从未可用)。
- `dolce_poc._C_MAJOR_BASE` → 公开 `C_MAJOR_BASE`(59a 旋律适配同用落指
  框架表)。
- pytest 230→**239**(+9:聚列/时值窗/休止截断/不伪造记账/冲突优先级/
  scope 落盘回吃/网格锚定漂移免疫/unknown 槽计数/窗口切分+τ 判错行为)。
  check.sh 全闸绿(analyzer 净 + flutter 979 + pytest 239 + 双漂移闸)。
