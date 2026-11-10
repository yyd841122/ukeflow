# 02: AB 选段循环

**What to build:** 起点 A / 终点 B 选段循环:播放到 B 无缝回到 A(示范声尾音
在 A 点前截断,不叠上一轮余音);红线随循环回跳;循环边界不漏音不重音。

**Blocked by:** None

**Status:** ready-for-agent

- [ ] A/B 设定 UI(当前位设为 A/B)
- [ ] 循环回跳无缝(边界无漏音/重音/旧尾音残留)
- [ ] 循环中匀速无漂移
- [ ] 真机验收:难点小节连续 5 轮

## Comments

- 2026-11-10: 建票。codex 参照:playbackRange 有界播放+完成回 A。
