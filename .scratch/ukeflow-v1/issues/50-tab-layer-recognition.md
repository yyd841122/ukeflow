# 50: TAB 层识别 + 拍位计算

**Status:** resolved

**Blocked by:** 48

**What to build:** TAB 条带内：fret 数字 OCR（0-9 印刷体白名单）+ 四线定位 →（弦,品,候选拍位）；节奏解释：符杠/符尾/附点/休止模板匹配 → 时值 → 拍位（谱全了独奏谱带节奏记号，这是与纯 TAB 的关键差别，亦是识别层最难一段）；记号模板：滑音斜线/卷弦波浪/震音椭圆/实心点休止/X 闷音（X 照读谱法不落音，落证据）。输出伴奏声部 IR 草稿。金标准：gs-aini 独奏层对照人工 484 音逐位 diff（数字正确率/时值误差/休止 P-R/技巧 F1）。

**Non-goals:** 五线谱、通用 OMR、矢量 PDF。

## Comments

- 2026-10-28 (认领+收口): 主路径 = 消费工单48 split 的 tab 层裁图+谱表几何,
  PaddleOCR(数字白名单)+ 几何规则 → 伴奏声部草稿(tab.json,
  `ukeflow.workbench.tab/1`)+ `tab.py`/`tab_diff.py` + CLI `recognize-tab`/
  `diff-tab` + `tools/dump_tab_truth.dart` 真值导出 + tests/fixtures 真值
  fixture。× 照票面不落音、落弦号证据(x_marks);技巧记号(卷弦/扫弦箭头/
  滑音/震音/延音括线/长音椭圆)单列 techniques/evidence;拍位 = 小节网格
  锚定(bar×拍号,barline 是真值,read_beats 毒化不跨小节级联)+ 小节内
  时值累加(符尾/符杠/附点;无杆尾杠而有延音括线 = 四分攻——印张长音画法;
  无节奏记号的 attack 落警告按 0 计)。
- **像素考古新档案(全部实测进常量)**:谱线芯部 300dpi <195(墨阈分不开线
  与字形,须按 line_ys 删带);品位数字/× 压线(圆心=弦线,与简谱「行下
  空间」两套坐标);数字 ~13×14、× ~14×19、卷弦 8-9px 蛇形、箭头 4px 细杆+
  端头、八分休止 = 实心点15×8+尾钩、全小节休止 = 20×6 扁杠挂②线下、滑音
  = 26×7 斜杠、震音 = 19×59 瘦椭圆、延音括线 = ④线下空心矩形(证据,真值
  模型不记持续);小节线与箭头同形,靠「距小节界+无音位」排除;谱号区
  T-A-B 竖排字母与 4/4 拍号靠「压线」判据天然排除。×/波浪印张右移 ~25px
  (census 锚位漂移照录)。同拍列(数字+杆+低弦 ×)物理粘连,行宽剖面分段
  拆解(头部致密=数字柱;体宽振荡=卷弦;恒窄+单端加宽=箭头定向)。
- **金标准结果(gs-aini 484 音窗口,诚实数字)**:数字配对 3-8 对、正确率
  0-17%;时值 1/1-2/6;休止 P/R 0(检出但拍位漂移超容差);技巧 F1
  0.24(roll 0.35 / strumUp 0.32 / strumDown 0)。**识别层 v1 的墙,四条**:
  ①草稿音符召回低——印张和弦堆/轻拍以 × 表达(约半数真值音),× 还原为音
  须查和弦指形(本票面明确 × 不落音,归 51);②品位数字印张字体系统偏离
  OCR(8 常读 6、4 常读 7,顶部横杠/细笔画在 300dpi 亚阈值);③无符尾杠的
  attack 时值印张不编码(延音括线只表「响到下 attack」),拍位在小节内漂移;
  ④b10 印张字形与人工转录分歧(印张 7 形,转录 4+滑音,diff 照报归校对台)。
  diff-tab 报告即 51 校对台工作清单;识别质量迭代(×+指形还原、字体适配
  模板、括线跨度解时值)为后续票留口。pytest 103 绿(新增 26)+ flutter 951
  绿 + analyzer 净(零 Dart 运行时改动,tools/dump_tab_truth.dart 为
  dev-only 脚本)。
- 2026-10-28 (评审消化·两轴 code-review): 修复——①check.sh 真值漂移闸接
  TAB(dump_tab_truth.dart ↔ fixture,工单49 同款,漏接即 canary 莫名
  diff);②slides 并入 diff 真值事件表(原恒 FP,配对按 fromBeat)+ 新测
  滑音配对;③assemble 空段(有证据无 attack)prev_beat 接地,不再
  UnboundLocalError + 新测;④unmapped_attacks 证据链补全(bbox/label/
  置信度,原只 x);⑤× 弦号未知落警告(与数字同纪律);⑥P/R/F1 三处
  手搓归一 _prf;⑦竖柱分解门槛提常量(COLUMN_NARROW_FRAC/HEAD_MIN/
  HEAD_MAX/GLYPH_MIN_W);⑧子进程 CLI 测试无模型时 skip(同真机纪律);
  ⑨死代码清(all_warnings/start 赋值/空 warnings 字段)。复跑全绿:
  pytest 105(+2) + check.sh 全闸(含双漂移闸) + flutter 951。
