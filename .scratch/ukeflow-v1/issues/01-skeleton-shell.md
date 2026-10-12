# 01: 工程骨架与五页导航壳

**What to build:** 正式 UkeFlow Flutter 工程落地(取代临时 spike 工程的正式地位):引入 Riverpod 与 drift,统一主题,底部导航五个页签——调音器、和弦、跟练、路径、曲库(此票全部为占位页)。真机可安装运行,后续所有工单都在这个壳上长。

**Blocked by:** None (can start immediately)

**Status:** done

- [x] `flutter build apk` 成功并安装到真机(OPPO PCAM00,连接方式见 spikes/tech_validation/README.md)
- [x] 底部导航五页可切换,主题统一(中文 UI)
- [x] drift 数据库打开无错(空库可用),Riverpod ProviderScope 就位
- [x] 一条有意义的冒烟测试(App 启动渲染出导航壳)通过

## Comments

- 2026-10-09: 骨架落地于仓库根(lib/ 按架构文档分 core/features/data)。`flutter test` 3/3(导航壳冒烟 2 条 + drift 空库内存开库 1 条),`flutter analyze` 无告警,`flutter build apk` 出包成功(app-release.apk)。启动即预热数据库(`databaseWarmupProvider`),真机上 drift 打开失败会打 logcat。
- 2026-10-09: 真机验收通过(OPPO PCAM00,无线 adb):安装启动正常,截屏核对五页签渲染与琥珀木色主题,adb input 点「跟练」切换正常;logcat 无「数据库打开失败」(release 无法 run-as 查库文件,开库成功依据=logcat 静默+宿主内存开库测试;首个加表工单落地时可在真机复验)。评审修改已并入:迁移策略 createAll 兜底、预热迁入 data 层、_tabs 记录列表、架构文档补 core/theme 与 core/ui。**本票完成。**
