# 30: cc-suite 全库审计消化(2026-10-16,full 9 维度)

**What to build:** 消化 [.cc-suite/audits/audit-20261016-144935-findings.md](../../.cc-suite/audits/audit-20261016-144935-findings.md) 的 51 条 Codex 审计发现(2 High / 36 Medium / 13 Low;38 文件 CLEAN)。发现是**线索非定论**,修复前逐条核实(尤其 #7 须对照 ADR-0005——playClocked+引擎时钟锚定是 spike 锁定决策,Codex 不掌握该背景,该条可能误解设计)。按四个工作包消化,每包 TDD 修复+验证:

- **WP-A 音频与调度**(发现 1-9):含 2 个 High——减速调度冻结(#2)与 soloud 时序锚定(#7,须先对照 ADR-0005 核实)。修复纪律对照票 24 先例(上轮审计同区域)。
- **WP-B 跟练/节拍控制器**(发现 25,33-35,37,39-50):大量同型重复模式——warmup 释放后访问(#43/48)、首播失败被覆盖(#45/50)、成功保留旧错(#44/49)、重建重放在途声(#37/39/42)、changePeriod 清调度器空断言(#34/41)。同型问题考虑抽共享基类/帮助函数一次修透,而非逐处打补丁。
- **WP-C 导入链路**(发现 11-14,26-30):cifra_extract 转义/混排行归一/连续和弦行/token 正则;JS 提取的 CHORD_SHAPE 拒 7M 写法(**与巴西记谱映射直接冲突,优先级高**)与 DIV 双 flush 假空行;cifraclub_page mounted 守卫与导航令牌;DB 错误逃逸。
- **WP-D 数据与内容**(发现 10,18,21-24,32,38,51):**小星星 C5→C4 音高错(目标曲内容级错误,用户可直接听出,建议单独先修)**;和弦库空 positions 崩溃;chord_tips 横按手指;打卡页错误逃逸与连击刷新。

**Blocked by:** 无(审计已完成,发现文件即输入)

**Status:** needs-triage

- [x] WP-A 音频与调度(9 条,含 2 High;#7 先对照 ADR-0005 核实)
- [x] WP-B 跟练/节拍控制器(17 条,同型模式抽共享修透)
- [x] WP-C 导入链路(10 条;#26 CHORD_SHAPE 拒 7M 优先)
- [x] WP-D 数据与内容(13 条;#10 小星星音高错建议先修)
- [ ] 全部修复后 `/cc-suite:verify` 复核,findings 状态翻 fixed(状态已翻;verify 命令本会话不可用,留用户侧执行)

## Comments

- 2026-10-16 (立票): 工单 01 预约的「16+17 落地后全库跨模型审计」执行完毕。cc-suite 插件(xiaolai/claude-plugin-marketplace,v2.0.0)本项目级安装,Codex CLI(gpt-6.1-sol,effort high,read-only 沙箱)8 批串行审 71 个 Dart 文件(lib+test,排除 .g.dart),全部批次 completed。51 条发现:2 High(均在音频调度区)、36 Medium、13 Low、0 Critical;38 文件 CLEAN。审计原始输出线程 ID 与逐条线索见 findings 文件。**分票建议**:WP-D 的小星星音高错是内容级错误可立即小修;WP-B 的四组同型问题适合一次抽共享修透;WP-A 的 #7 必须先对照 ADR-0005 核实再动手——审计模型不了解「引擎时钟唯一权威」是 spike 锁定的架构决策。上轮审计(2026-10-13,mini,9 文件)的消化先例即票 24。
- 2026-10-16 (工单30 会话): **四工作包全部消化完毕**。51 条处置:36 fixed / 5 partial(#28/#29 WebView 壳不可替身待真机补验、#46 mounted 守卫落地微任务推迟不取、#32 当日值刷新落地单测缺位)/ 4 skipped 带核实结论(#1/#8 取消失败无现实「声仍在」路径、#2 目标平台不成立——soloud_miniaudio_pause 在 Android 是空操作,iOS 启动时随 #7 一并重评、#7 对照 ADR-0005 核实为锁定设计,playScheduled 迁移留未来 spike)。**核实改写审计前提两处**:#2 的 500ms 空闲冻结是 4.0.10 引入的真实特性但 Android 平台分支为 no-op(包内 soloud_miniaudio.cpp 明言);#7 的「独立锚点」恰是 playClocked 契约本身(绝对引擎时钟=单一 physics 时基)。五个 WP 提交(WP-A..WP-D),逐包全库测试+analyzer 收口:测试 439→488 全绿,新增 49 个回归。微妙项均做红验证(旧实现跑新测试确认失败);WP-A #5 音准修复经环内实测标定「整环延迟=N−0.5+a/2」经验律(261–1397Hz 误差<0.02 样本),880Hz 由 +21 音分修到 ±0.02。同型三纪律评估过抽共享基类:两控制器状态形各异需回调管道,以同注释+双回归锁定替代(票面「考虑抽共享」的判断落地为不抽,理由见 WP-B 纪要)。票面 WP-C 写 10 条列了 9 条编号:发现 15-17(strum_chart_parser)不在任何包清单里,已并入 WP-C(导入解析链路),51 条全覆盖。`/cc-suite:verify` 本会话不可用(插件命令不在本会话技能表),留用户侧执行;findings 状态已全数翻毕。
- 2026-10-16 (工单30 会话,评审更正): 双轴评审(Standards/Spec 子代理)抓出**账目缺口**:发现 19/20/31/36 不在票面任何 WP 编号清单里(各包列表总和只有 48 条,前一条纪要「51 条全覆盖」不实——已核,15-17 并入 WP-C 后仍漏这 4 条)。已全部补修:**#31 fixed** path_page 打卡库错误就地可读可重试(与 #30 同型同修,炸 DAO 测试+红验证);**#36 fixed** practice_view 歌词余高 <24px 钳零(280px 视口隔离测试,负 BoxConstraints 断言崩收口,红验证);**#19/#20 fixed** 预备倒计与节奏槽位改经 beatAt 同一取整网格派生(拍声/倒计/箭头同毫秒翻转;40..208 跨 BPM 边界扫域测试,红验证)。另落实 Standards 轴:快进补全周期域扫描(160 档非整除+40..208 逐 BPM 对独立 brute-force)、不支持指令 issue 定位到指令原文 span、demo 文案按 GLOSSARY 归位「示范试听」、5 测试文件补行尾换行。Spec 轴披露:#26 CHORD_SHAPE 无仓库内自动化测试(JS 只在 WebView 执行,node 冒烟是会话外 ad-hoc,真机 div 实页机检待续)——验证形态已在 WP-C 纪要明示。终态:39 fixed / 5 partial / 4 skipped,findings 无 open。全库 493 测试绿,analyzer 零告警。
