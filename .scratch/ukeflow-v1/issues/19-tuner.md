# 19: 调音器正式页

**What to build:** spike A 管线迁入正式工程并打磨:record 采集(PCM16/44.1kHz/单声道)→pitch_detector_dart(YIN,2048 窗口)→音名/音分换算;调音器页:GCEA 四弦目标、实时音名+偏差指示、±5 音分"已调准"提示、静音不乱报、读数适度阻尼;麦克风权限流程。A4 参考音本票固定 440(接设置在 20)。

**Blocked by:** 01 工程骨架与五页导航壳

**Status:** done

- [x] 真琴逐弦调准全流程可用(对照实体调音器)
- [x] 读数有阻尼不狂跳,±5 音分判准
- [x] 静音/说话不误报音高
- [x] 权限拒绝给引导态
- [x] 音名/音分换算逻辑有单元测试

## Comments

- 2026-10-12: 工单 05 评审留的重复提示:调音器页四弦钮与和弦详情页按法 chips 是同形「等分一行+收小内边距防折行」的两份实现(各带 360dp 回归测试)。本票重做调音器页时顺手提取共享等分行组件,消掉一份。
- 2026-10-13 (工单09 会话): 又添两份重复,提取时可一并处理:①箭头槽位条——8 槽视觉状态机(当前点亮/已扫淡出/未到描边)在节奏型训练页(`_arrowStrip`/`_slotCell`)与跟练 `PracticeView`(`_ArrowStrip`/`_slotCell`)各一份,仅 key 前缀与状态来源不同,提取目标 core/ui;②BPM 控件(步进+滑杆)与引擎状态行在训练页与跟练空闲面板近乎逐字两份。cc-suite 审计另记两份:③tick 音源装载/就绪处理三份控制器重复(含同样初始化弱点,抽共享装载器时顺修)④跟练 `_LibraryErrorView` 与和弦库页错误面板同形。
- 2026-10-13 (工单13 会话): 指弹跟练会话页(TabChartPage)再添一份:引擎状态行/_bpmControl/_SpeedControl 与弹唱跟练页近乎逐字(页内注释已指归本票);另加两壳——16ms 轮询壳(_pollInterval/_startPoll/_stopPoll + 曲末 stop)与 dispose 的 scheduleMicrotask 停声纪律,两会话页同形,提取时抽「跟练会话页基类/混入」一并收。
- 2026-10-17 (实现会话): 三笔提取债全部落地(提交 5d9520f):EqualRow/ArrowStrip/BpmControl/EngineStatusLine/SpeedControl/LoadErrorView 六件入 core/ui;TickSounds+SingleFlight 收拢**四**控制器(注释记三份,节拍器同形一并收;顺修节拍器/训练器缺在途合并,并发 warmup 防回归测试红验证入档);PracticeSessionState 会话页基类收两跟练页轮询壳/预备过渡/弹回即停。调音器本体(提交 82f04f4):管线迁入、页面重做、权限两段式流程;code-review 双轴发现全处置(SingleFlight 测试硬伤、A4 前瞻注释改如实、双音分口径收拢)。真机验收中用户反馈两处当场修:①拾音「离开页面即停」——切页签(activeTabIndexProvider 感知,IndexedStack 保活不 dispose)与退后台(lifecycle paused)即停麦,回来不自动续;②页面顶部留白 24→48dp。三改后复测,用户确认验收项全过,logcat 无异常。测试 546 绿,analyzer 零告警。
