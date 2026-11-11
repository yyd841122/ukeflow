# 01: 慢放(0.5 / 0.75 倍速)

**What to build:** 流水谱跟练页速度选择(0.5 / 0.75 / 1.0)。慢放只缩放时间轴:
排版层不动,示范声调度与红线推进按 `pixelsPerSecond × speed` 重排(变速瞬间
无突跳,有全曲匀速扫描闸);数字/光晕等渲染字号不随速度变。

**Blocked by:** None

**Status:** done

- [x] 速度选择 UI(0.5/0.75/1.0 三档)
- [x] 慢放下的匀速无突跳(现有扫描闸按新斜率复跑)
- [x] 慢放下示范声节距正确( KS 音色基频不变,只变时刻)
- [x] 真机验收:0.5 倍整曲无漂移

## Comments

- 2026-11-10: 建票。codex 参照实现同款三档(transport.setSpeed)。
- 2026-11-10: 落地(机检通过,待用户听感验收)。实现与 codex 同构:一切
  时刻都是不缩放的音乐秒,速度只进两处——控制器 `currentSeconds() =
  speed ×(引擎时钟 − t0)`,调度器攻击时刻 `t0 + music/speed`(KS 音色基频
  不动);排版层(FlowingLayout/FlowingEngraving)零改动,红线推进速率
  自动降为 pps × speed。播放中切速 = 取当前音乐秒重锚
  (t0 = now − pos/newSpeed)+ 调度器重建(consumedUntil=now,已响不重放),
  在途未响旧预定停弃、尾音自然衰减(变速不该听得见)。
- 2026-11-10: 机检记录(OPPO PCAM00,debug 装机)。①0.5 倍整曲:152 个
  遥测采样全程 speed=0.5,music−0.5×wall 最大偏差 **+0.019s**(305.7s 墙钟
  上,零漂移),pace≈1.000,consumed 309/309,曲末 finished、终点保留、
  2:32/2:32。②播放中即切:0.75→1.0 的 `SPEED 1.0 pos=41.053` 与前后帧
  逐帧连续(41.053+0.789=41.842),无突跳无重放。③播放→暂停→再播→
  切速全循环红屏已修(见下),终态截图正常。④logcat 无 E/flutter、
  无 FATAL。
- 2026-11-10: **机检顺手抓到存量红屏 bug(已修)**:页面原混入
  `SingleTickerProviderStateMixin`,「播放→暂停→同页再播」时我们的代码
  dispose 后只置空自持字段,mixin 内部 `_ticker` 引用仍在,第二次
  `createTicker` 抛「multiple tickers were created」红屏(声音调度不受
  影响继续推进,只有画面死)。此前机检从没在一次进页里播→停→再播过,
  本次「曲末→从头→再练一遍」路径踩出。修 = 换复数 `TickerProviderStateMixin`
  (错误信息推荐做法,faithful 页 initState 单建是安全写法无此雷)。
  另:机检脚本 ukeflow-flowing.sh `dump_get` 里 `adb cat` 缺 `shell`
  (adb 无裸 cat 命令)已顺手修。
- 2026-11-11: 用户听感验收通过,翻 done。三档速度、播放中即切、整曲零漂移听感无异议。
