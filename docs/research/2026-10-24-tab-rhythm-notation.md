# TAB 记谱排版调研:成熟引擎的节奏/装饰音画法(工单 39)

用户指出琴弦行音符画法不对、要求照行业实现。调研对象:alphaTab(跨平台
TAB 渲染库)、Soundslice( stems on tab 的工程博客)、VexTab/VexFlow、
LilyPond。结论已落 `score_sheet_layout.dart` 的节奏带体系。

## 定案的画法约定

- **节奏记号画在 TAB staff 下方专用带**:alphaTab `NotationSettings.rhythmHeight`
  —「Controls how high the rhythm notation is rendered **below the tab staff**,
  default 25」;Soundslice 的 stemmed tablature 自述与吉他杂志/Songsterr 同式。
  → 采纳:`rhythmBandHeight = 25`,置于琴弦行与简谱行之间。
- **每组(同拍)一根符杆下垂**,杆长:四分裸杆、八分/十六分标准长、
  二分及以上更长裸杆(Guitar Pro/TuxGuitar 同式;LilyPond:tab 符杆方向
  规则与普通记谱一致)。
- **符杠按拍分组横连**:同一整数拍窗内连续的八分连一条一级杠;相邻对都
  是十六分加二级杠;**孤立八分/十六分画符尾**(两条斜杠);拍界断杠。
  → 采纳:`rhythmStems / rhythmBeams / rhythmFlags` 纯函数推导,合成小节
  测试逐条锁定(四分裸杆/八分连杠/十六分双杠/孤立符尾)。
- **延音(tie)= 同音弧**:两谱号间弧线;本谱转录只录 attack,数据无
  tie 对——长音(组时值 ≥2 拍)以「更长裸杆 + 延音弧」表达(印张圆圈
  数字/椭圆×柱一族)。
- **滑音(slide)= 两品位数字间的斜线**(上行/下行随音高),alphaTab/
  GP/VexTab 同式;**击勾弦 = 弧线 + H/P 字**。数据层目前无滑音/击勾
  事件——待用户指认位置后落 `ScoreSheetDef` 事件表(与 strums 同模式);
  KS 合成器的滑音声效另立票。

## 引用

- alphaTab NotationSettings: https://alphatab.net/docs/reference/types/notationsettings
- Soundslice stemmed tablature: https://www.soundslice.com/blog/25/stemmed-tablature
- VexTab tutorial(tab-stems): https://vexflow.com/vextab/tutorial.html
- LilyPond tablature stems/beams: https://lilypond.org/doc/v2.24/Documentation/snippets/stems-and-beams-in-tablatures
- Guitar Tricks tab symbols(slides/H/P/×): https://www.guitartricks.com/blog/Guitar-Tab-Symbols-Explained

## 补充(2026-10-25):休止与音符头的 TAB 画法(guitar.ch 节奏 TAB 规范)

- **音符头**:全音符 = 数字外套椭圆(无杆,4 拍);二分 = 椭圆+杆(2 拍);
  四分 = 数字带杆;八分 = 数字+旗/杠;十六分 = 两条杠。
  → 长音(≥2 拍)已实现为「数字外套椭圆」。
- **休止(TAB 内直接画)**:全休止 = 矩形挂第 3 弦;二分休止 = 矩形坐第 4 弦
  (2 拍);四分 = 弯钩;**八分 = 单条符尾钩;十六分 = 双钩**。
  → 采纳:休止钩(八分)+ 钩上标拍数的占位画法(经典多小节休止编号法,
  印张「带数字 2 的鱼钩」)。
- **其他**:三连音 = 括号/弧线标 3(本谱三连音直化段暂不标,数据在案);
  附点 = 延长一半;tie = 连接保持音;fermata = 弧+点。

## 引用(补充)

- guitar.ch 节奏 TAB 规范(音符头/休止/装饰音逐一图文): https://www.guitar.ch/en/guitars/theory/theory-rhythmic-tablature.html
- 古典吉他休止教学(休止形状): https://www.classicalguitarcorner.com/rests-in-music
- Guitar Pro Academy(全/二/四分休止): https://www.guitar-pro.com/academy/l/49284-whole-rest-half-rest-and-quarter-rest
