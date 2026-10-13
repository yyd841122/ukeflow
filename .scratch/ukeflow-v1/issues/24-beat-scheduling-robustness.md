# 24: 节拍调度与时间轴鲁棒性(cc-suite 审计发现)

**What to build:** 工单09 后的 cc-suite Mini 审计(gpt-6-astra)在 core/audio 与 core/practice **既有**代码里发现的问题收拢:①changeBpm 重锚不取消旧网格已预定拍,大跨度变速时新旧拍倒挂(High,40→208 边角;节拍器/训练器运行中变速路径,跟练 v1 固定速不触及)②scheduleDue 迟滞轮询后过期拍无界回放,违反文档窗语义③BPM/periodMs 公共缝无校验(负值死循环、非有限值抛错)④compileTimeline 校验靠 assert,release 消失,应 ArgumentError 化⑤BeatScheduler 错误恢复路径的 stop() 可再抛、掩盖原错误⑥beatAt 未取整边界与 beatTime 取整时刻亚毫秒错位(practice_state 下游表现:跟练条带跨小节守卫 ~0.4ms 窗内空白一帧,16ms 轮询下偶发亚感知)⑦PlayTimeline 公共构造器可传入与分类视图发散/失序的列表⑧compileTimeline 行→小节分配拆帮助函数(74 行四层嵌套)。

**Blocked by:** (无;①②③为正确性项建议优先,⑥与工单10 变速重编译同缝,修时对齐)

**Status:** ready-for-agent

- [x] 重锚有界:changeBpm 不再与已排队拍倒挂(40→208 边角有测试)
- [x] 迟到拍策略有界并有测试
- [x] BPM/periodMs 校验 ArgumentError 化(assert 依赖清零)
- [x] 错误恢复不掩盖原错误
- [x] beatAt/beatTime 边界统一,或文档化「亚毫秒错位可接受」决策并消跟练条带瞬空

## Comments

- 2026-10-13 (工单09 会话): 来源 = cc-suite Mini 审计,findings 文件 `.cc-suite/audits/audit-20261013-084529-findings.md` #1–#10(工单09 自有文件的 8 项已当场修复,标 fixed)。这些是 core 层既有项——工单03/06/08 各自评审时未覆盖的边角,第二意见的价值所在。
- 2026-10-13 (工单24 会话): 五项验收全落,全库 229 测试绿、analyzer 零告警(原 216,+13)。findings #1–#10 全部处置(#14/#19/#20 归工单19 不动):
  - **#1 重锚有界**:`BeatScheduler._pending` 记录拍号;changeBpm 停掉旧网格已排队未响拍(时间 > now),把 nextBeat 回拨到最早被取消的拍号,交还正常过窗按新网格重排(拍号与相位保持;时间恰为 now 的拍视为正在响,不动)。40→208 审计现场(旧拍1@1500 vs 新拍2@1482 倒挂)有测试,已对旧实现验证过红。纯函数 `reanchored` 本身不变(调度态感知归调度器,文档改写)。
  - **#4 迟到拍有界**:`scheduleDue` 新增 `maxLate`(缺省 40ms = BeatScheduler.pollInterval,调度器显式传入):窗口改 [now−maxLate, now+lookahead],超容差的过期拍越过不回放、nextBeat 不回头;容差同时兜住启拍时引擎时钟两次读数的亚毫秒漂移(第 0 拍不丢)。原「时钟跳跃一次补齐」等两测试按新语义改写。
  - **#3/#5/#7 校验 ArgumentError 化**:BeatSchedule 构造器(const→非 const)periodMs 限有限正值(reanchored 同受保护);BeatScheduler.start/changeBpm 入口限正 BPM(此前 changeBpm(0) 从 round(inf) 抛 UnsupportedError);compileTimeline 校验 bpm/speed 及算出的 period;beatAt 校验 periodMs。core/audio+core/practice assert 清零。
  - **#2 错误恢复**:`_pass` 的 catch 先 `_clearScheduleState()`(取消定时器、清 pending/时间轴,不碰引擎)再做引擎清理,engineTime/各 stop 逐项独立容错;onError 必达原错误。HalfBrokenEngine 现场(第 6 次 playClocked 失败 + stop 必失败,拍 4 在途),旧实现次生「引擎停止失败」异常外泄、onError 不达——已对旧实现验证过红。
  - **#6/#10 边界统一**:beatAt 拍序号 = 最大的 b 使 round(b×periodMs) ≤ elapsed 毫秒(连续网格估算 ±1 修正),与 beatTime 同一取整边界——拍声与视觉同毫秒翻转,`practice_view._currentSlot` 跨小节守卫的 ~0.4ms 空白帧消除(61BPM 3934ms 回归锁定)。副产物:曲末边界与名义曲长 totalDuration 恰好重合(同为 round(totalBeats×periodMs)),practiceStateAt 文档随之更新,富余窗归末拍。
  - **#8/#9 顺带**:PlayTimeline 构造收私有,strums/lyrics/sections 分类视图自 events 单一来源派生(外部无法再供给发散/失序列表);行→小节分配抽 `_lineBarChords` 帮助函数(74 行四层嵌套拆薄)。
  - 评审(双轴子代理):spec 轴全项落地、无超范围;按 findings 收尾——reanchored 直调缝在 round() 前先校验(此前抛 UnsupportedError 而非 ArgumentError),changeBpm 取消循环各 stop 独立容错(与恢复路径同一纪律);共享校验谓词 `requirePositiveFinite` 收拢 5 处;`_pending` 改具名 record,重排回拨抽 `withNextBeat`。start 双读引擎时钟在 >40ms 线程停顿时会丢第 0 拍(旧实现必响,但那正是无界追赶的缝)——文档化接受。测试侧校验循环同形 4 处未收拢(量小不值得抽),留观。
