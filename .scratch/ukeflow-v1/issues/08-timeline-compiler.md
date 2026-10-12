# 08: 时间轴编译器+练习状态纯函数(核心缝)

**What to build:** 同步引擎的心脏(可验证型工单):弹唱谱+节奏型+BPM→动作事件时间轴(事件含引擎时刻,类型覆盖扫弦[方向+和弦]、歌词行、段落);练习状态纯函数:(时间轴,引擎时刻)→当前拍、当前动作、预告窗口、高亮歌词行——当前动作二分查找,预告取时间窗。变速(50%–100%)作为编译参数。此工单把音画同步的全部正确性锁死在纯函数测试里,不含任何引擎/UI。

**Blocked by:** 06 节奏型训练器, 07 文本谱解析+校验+5 首目标曲录入

**Status:** done

- [x] 时间轴编译测试:给定谱+节奏型+BPM,事件时刻逐一精确断言
- [x] 练习状态测试:任意时刻查询正确(事件边界、段落切换、曲末之后)
- [x] 预告窗口查询正确(窗口内动作按序、去已完成)
- [x] 变速重编译正确(50% 时全部事件时刻等比)
- [x] 全部为标准 flutter test,零引擎依赖;时间源唯一语义在此定型

## Comments

- 2026-10-12: 落地。两文件住 core/practice(架构树既定):`play_timeline.dart`(PlayEvent 三型 section/lyric/strum+PlayTimeline+compileTimeline)、`practice_state.dart`(PracticeState+practiceStateAt,当前动作/行/段落二分查找,预告取 (now,now+窗] 时间窗,当前拍复用 beatAt)。19 新测试全绿(analyze 无告警,全库 185),零引擎依赖。
- 2026-10-12: **时间源唯一语义定型**(票面交付项):时间轴时刻是相对量(自 0),锚定 t0 是播放方的事,编译器不知道引擎存在;事件时刻=逐事件「网格位置×单位毫秒」四舍五入不累加(与 BeatSchedule.beatTime 同语义,奇 BPM 61 手算字面量锁死,累加式会得 3936 而非 3934);小节首扫弦==同序号拍 beatTime 有跨模块不变量测试——工单 09「扫弦箭头与节拍声同源同刻」的结构保证在此。练习状态查询只认调用方传入的引擎时刻,t0 前/曲末(≥t0+曲长,半开)返回 null。
- 2026-10-12: **小节分配约定**(文本谱无小节线的唯一裁量处):每个和弦记号独占一小节(行内 k 记号=k 小节),无记号行占一小节延续当前和弦,曲首无和弦的扫弦 chord=null。已写进编译器 doc 注释+assets/charts/README.md(内容录入须知)+GLOSSARY 新词条「动作事件时间轴/练习状态」。工单 10 的俄罗斯方块预告传自己的窗口即可(defaultPreviewWindow 2s 是视觉量级,音频 400ms 提前量仍归 BeatScheduler);变速参数 speed(50%–100%)已进编译签名,50% 网格等比有测试:整网格(120 BPM)时刻严格×2;奇 BPM 下逐事件对**最终网格**四舍五入,与「原速时刻×2 再取整」可差 1ms——这是定型语义而非误差,换来拍点扫弦与拍声在任何变速下同刻(61 BPM×0.5 有精确字面量+同刻断言)。
- 2026-10-12: 节拍声不进时间轴事件:节拍是规则网格,工单 09 控制器按时间轴的 periodMs/totalBeats 复用 BeatScheduler(工单 06 已验证的强弱管线),与拍视觉(beatAt)同源;时间轴只装动作事件。architecture.md 模块树已更新。
- 2026-10-12: 双轴评审修复(/code-review Standards+Spec):①曲末判定改认节拍网格(beat≥totalBeats 即 null),杜绝名义曲长前亚毫秒富余窗内 beat==totalBeats 的幻拍(61 BPM 有亚毫秒窗测试)②「小节首同刻」不变量收窄为「拍点(偶数槽)扫弦==该拍 beatTime」并扩到全部偶数槽 ③补 61 BPM×50% 等比语义测试(上条)④用语修正(「事件表/播放方」撞 GLOSSARY Avoid)⑤测试 helper 去重(test/helpers/chart_fixtures.dart)、architecture.md 同步引擎节更新到 sealed 事件+相对时刻(单音 note 归工单 12/13)、triage-labels.md 补 done 记法。修复后全库测试绿。
