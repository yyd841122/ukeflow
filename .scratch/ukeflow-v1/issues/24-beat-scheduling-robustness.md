# 24: 节拍调度与时间轴鲁棒性(cc-suite 审计发现)

**What to build:** 工单09 后的 cc-suite Mini 审计(gpt-6-astra)在 core/audio 与 core/practice **既有**代码里发现的问题收拢:①changeBpm 重锚不取消旧网格已预定拍,大跨度变速时新旧拍倒挂(High,40→208 边角;节拍器/训练器运行中变速路径,跟练 v1 固定速不触及)②scheduleDue 迟滞轮询后过期拍无界回放,违反文档窗语义③BPM/periodMs 公共缝无校验(负值死循环、非有限值抛错)④compileTimeline 校验靠 assert,release 消失,应 ArgumentError 化⑤BeatScheduler 错误恢复路径的 stop() 可再抛、掩盖原错误⑥beatAt 未取整边界与 beatTime 取整时刻亚毫秒错位(practice_state 下游表现:跟练条带跨小节守卫 ~0.4ms 窗内空白一帧,16ms 轮询下偶发亚感知)⑦PlayTimeline 公共构造器可传入与分类视图发散/失序的列表⑧compileTimeline 行→小节分配拆帮助函数(74 行四层嵌套)。

**Blocked by:** (无;①②③为正确性项建议优先,⑥与工单10 变速重编译同缝,修时对齐)

**Status:** ready-for-agent

- [ ] 重锚有界:changeBpm 不再与已排队拍倒挂(40→208 边角有测试)
- [ ] 迟到拍策略有界并有测试
- [ ] BPM/periodMs 校验 ArgumentError 化(assert 依赖清零)
- [ ] 错误恢复不掩盖原错误
- [ ] beatAt/beatTime 边界统一,或文档化「亚毫秒错位可接受」决策并消跟练条带瞬空

## Comments

- 2026-10-13 (工单09 会话): 来源 = cc-suite Mini 审计,findings 文件 `.cc-suite/audits/audit-20261013-084529-findings.md` #1–#10(工单09 自有文件的 8 项已当场修复,标 fixed)。这些是 core 层既有项——工单03/06/08 各自评审时未覆盖的边角,第二意见的价值所在。
