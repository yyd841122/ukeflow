# 工单61 m0:oracle-glyph 天花板实验报告

2026-11-03。票面问题:**把冻结评测集当正确字形(adjudicated marks 即
oracle)喂回 50 的自动定位+节奏解码 → `eval-joint`,联合事件 F1 到几?**
≥0.90 → 缺口确认在字形层(A 档「只训字形」成立);<0.90 → 定位/节奏解码
同为缺口(分类目标必须纳入杆底符杠,或明确降级并如实报终线上限)。

**判读:0.1688,远低于 0.90——m0 不利。字形全对时现有机器几乎原地踏步
(59a 基线 0.1589 → oracle 字形 0.1688);缺口主导项是节奏解码(时值读数
正确率 ≈10.8%),其次是定位层(48 幻影小节线 + 漏检列毒化小节尾)。**

## 分数表(eval-joint × gs-aini-tab-v1,sha034d42c42c98…,τ=1/32,已裁定 115 列/324 事件)

| 变体 | 事件层 F1 | 符号层 | intro | verse-a | chorus |
|---|---|---|---|---|---|
| 59a 基线(对照) | 0.1589 | 0.2880 | 0.3117 | 0.0000 | 0.1794 |
| **V1 oracle-marks(票面主数)** | **0.1688** | 0.3455 | 0.3944 | 0.0000 | 0.1757 |
| V2 = V1+真值时值(归因诊断) | 0.4715 | 0.6754 | 0.5250 | **0.9910** | 0.2955 |
| V2b = V2+幻影小节线修复(上限诊断) | **0.5044** | 0.7100 | 0.5250 | 0.9910 | 0.3579 |

变体梯度 = 归因阶梯:V1→V2 隔离「节奏解码缺口」;V2→V2b 隔离「48 小节
线缺陷」。V2/V2b 是诊断数,票面主数是 V1(定位+节奏解码保持管线原样)。

## 方法(切拼契约)

- **oracle = 真值 marks**(digit/×;m1 TAB 词表 {×, digit, muted, empty}
  的字形半边)。配对上的 attack 整束换成真值记号(含弦号——m1 格子天然
  按 (拍位格×弦) 出内容,弦轴来自几何);多余 attack 清空音位记号(保留
  管线事件/节奏记号),漏检真值列照实 FN。
- **定位保持自动**:attack 存在性(组件检测+聚簇)、小节归属、拍位(小节
  网格锚+小节内时值累加)全走 50 原样。**节奏解码保持自动**:杆/尾/杠/
  点读数与休止模板原样;ties 管线不读,照实 FN。
- **OCR 旁路**:注入替换全部音位标签,OCR 不参与(load_ocr=False,纯几何
  确定可复现);注入字形 conf=1.0 表 oracle。meter=4/4(= 基线页眉实读)。
- **注入对齐**(实验管线,非评分):小节内单调 1:1 DP,配对数最大、平手
  取 Σ|Δnorm| 最小,位置守卫 POS_TOL=0.3(attack 归一 x vs 列归一拍)。
  对齐统计全量落盘(oracle.alignment):配 111 / 多余 attack 9 / 漏检列 4
  (115 列中 111 配上,列级检出 96.5%)。
- **链路自洽验证**:真值当候选过同一链 = 事件层/符号层 F1 双 1.0
  (test_truth_self_score_perfect);V2 verse-a 0.9910 为机器端到端实证。

## 发现①:48 幻影小节线(实验中抓出,影响一切下游跑分)

split 在 sys4(谱页1 第5系统)探得 5 根小节界,但该系统只有 4 小节
(工单57 报告冻结映射「谱页1 sys4[18-21]/sys5[22-24]、谱页2 sys6[25-27]」)。
像素探针定根因:**x≈2015.5/2035.8 两根「贯穿谱高竖线」是真值 tremolo@82
椭圆(h≈5.2g,w≈1.45g)的两缘**——右缘被立为小节界 → sys4 幻影第 5 小节
→ sys5/sys6 全局小节号 +1 → **副歌全部内容拍位 +4(整拍一拖)**。物理
佐证:幻影 span(2036-2306)内近乎无墨,11 列的 b22 不可能在 270px 内;
且 10/8/8/10/10/10 攻击数与 57 映射的真值列数逐系统吻合。

影响:幻影界不在 m0 里修(修定位=改被测对象),而是**(a) 注入锚按 57
映射对准实际印张位置;(b) 装配骨架分 split(照罚错位)/repaired(并合
幻影、起点锚真值小节号)两档**。V2→V2b 副歌 0.2955→0.3579 即该缺陷的
代价切片。**59a 基线(0.1589)同样带此伤**(副歌内容 +4,靠相邻副歌小节
符号级重复才没崩到 0)——**建议另立 48 修复票(椭圆缘/箭头杆贯穿判据
收紧),修复后 59a 基线须复跑**;61 采纳门比较以此为准。

## 归因(为什么 oracle 字形救不了)

1. **节奏解码近乎全聋(主犯)**:111 个配对列上,时值读数 None 54 /
   读出数值 57 / 数值且与真值全对 **12(≈10.8%)**。None 按 0 累加 →
   小节内拍位塌缩(整小节挤在拍 0),数值错则级联漂移。V1→V2 的
   verse-a 0.0000→**0.9910** 证明:基线在 verse-a 的全灭**全部**来自
   时值读数,与字形识别无关。
2. **定位层空洞(次犯,V2b 仍封 ~0.50)**:
   - **漏检列毒化小节尾**:τ=1/32 下,一列缺席 = 该列之后整小节拍位
     偏移(漏 4 列:bar20×2、bar21(连音列,无害)、bar22×1——bar20/22
     尾段全灭)。bar24 的 2 个多余 attack(幻影 roll)各吃 1.0 拍,
     同样毒化小节尾。
   - **空 attack 不可见**:真值箭头列(marks=[] 且管线未检出 tech)注入
     后为空 attack → 候选无列 → 该拍真值展开事件 FN + 前列持续窗延长
     (rhythm_miss;bars 23/25 各 12 条即此形)。
   - 幻影小节线整拍移位(见发现①)。
3. **技巧记号(roll/箭头)不在 m1 词表,保持管线检测**:与真值方向/类别
   的分歧只伤符号层(roll↔strum 方向混淆;事件层 roll 与 strum 展开同形,
   不伤事件分)。
4. 休止:候选 @(0,4)+@(7.5,½) vs 真值 @(0,4)+@(7,½)——@7 那枚错位半拍,
   与 59a 同形(管线 rest8 落位机制未动)。

## 判读与 61 票面决策

- **V1 = 0.1688 < 0.90:m0 不利,A 档「只训字形」不成立**——与 57 VLM
  (0.1905/0.1924)、59a 规则管线(0.1589)三方互证一致。
- V1→V2 缺口(0.1688→0.4715)量化「节奏解码缺口」:**只训字形(含 ×)
  的天花板就是 ~0.17**;分类目标纳入杆底符杠(列级时值/梁结构)后,
  本曲上限也被定位层封在 **~0.50**(V2b)——因为漏检列/空列/多余列在
  时值全对的世界里照样毒化拍位。
- 按票面:m0 不利 → **全票关闭,或转「纳入符杠」版**。若转纳入符杠版,
  本实验再加两条钉子:(i) 分类目标除符杠外须含**列存在性/空列**(格子
  词表已含 empty,但列锚仍来自聚簇——漏检列在分类器外);(ii) 48 幻影
  小节线先修(否则任何下游学习都吃 +4 拍错位)。**起不起 m1 由用户按
  此定夺;两案的工时代价都显著高于原 A 档估计。**

## 复现

```sh
cd tools/score_workbench
PY=.venv/bin/python
$PY -m score_workbench.cli oracle-glyph ~/ukeflow-sources/gs-aini.pdf \
    --out-dir ~/ukeflow-sources/m0-61/layout --variant marks            # V1
$PY -m score_workbench.cli oracle-glyph ~/ukeflow-sources/gs-aini.pdf \
    --out-dir ~/ukeflow-sources/m0-61/layout --variant marks+durations  # V2
$PY -m score_workbench.cli oracle-glyph ~/ukeflow-sources/gs-aini.pdf \
    --out-dir ~/ukeflow-sources/m0-61/layout --variant marks+durations \
    --skeleton repaired                                                 # V2b
# 各产物再走 59a 同链:
$PY -m score_workbench.cli tab-candidate <oracle-tab*.json> --out cand-*.json
$PY -m score_workbench.cli eval-joint cand-*.json --out eval-*.json
```

原始产物(仓库外):`~/ukeflow-sources/m0-61/`(layout/{oracle-tab,
oracle-tab-durations,oracle-tab-durations-repaired}.json、cand/eval-*.json)。

## 落地物

- `score_workbench/oracle_glyph.py`:对齐 DP(`align_columns`)/注入
  (`inject_bar`)/骨架映射(`_repair_spans` + `GS_AINI_BAR_MAP`,57 冻结
  映射+幻影并合,含依据注释)/编排(`build_oracle_tab`,tab-doc 同形 +
  oracle 段落)。
- `tab.py` 拆出 `recognize_tab_attacks`(50 到 attack 为止的缝,工单50
  装配层与 m0 注入共用;`recognize_tab_pdf` 行为不变——重构后产物与
  baseline-59a tab.json 逐字节一致,created_at/tool_version 除外)。
- CLI `oracle-glyph`(--variant/--skeleton/--bar-map)。
- pytest 239→**257**(+18:对齐 DP 六案/注入六案/骨架映射三案/编排装配
  两案/真值自评链)。
