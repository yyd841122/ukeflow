# 01: 工程骨架与五页导航壳

**What to build:** 正式 UkeFlow Flutter 工程落地(取代临时 spike 工程的正式地位):引入 Riverpod 与 drift,统一主题,底部导航五个页签——调音器、和弦、跟练、路径、曲库(此票全部为占位页)。真机可安装运行,后续所有工单都在这个壳上长。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `flutter build apk` 成功并安装到真机(OPPO PCAM00,连接方式见 spikes/tech_validation/README.md)
- [x] 底部导航五页可切换,主题统一(中文 UI)
- [x] drift 数据库打开无错(空库可用),Riverpod ProviderScope 就位
- [x] 一条有意义的冒烟测试(App 启动渲染出导航壳)通过

## Comments

- 2026-10-09: 骨架落地于仓库根(lib/ 按架构文档分 core/features/data)。`flutter test` 3/3(导航壳冒烟 2 条 + drift 空库内存开库 1 条),`flutter analyze` 无告警,`flutter build apk` 出包成功(app-release.apk)。启动即预热数据库(`HomeShell._warmUpDatabase`),真机上 drift 打开失败会打 logcat。
- 待真机验证:安装 APK → 五页切换肉眼过一遍主题 → `adb shell run-as com.ukeflow.ukeflow ls databases` 确认空库文件生成。设备未连接,等配对。
