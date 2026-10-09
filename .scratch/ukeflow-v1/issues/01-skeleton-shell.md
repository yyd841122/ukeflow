# 01: 工程骨架与五页导航壳

**What to build:** 正式 UkeFlow Flutter 工程落地(取代临时 spike 工程的正式地位):引入 Riverpod 与 drift,统一主题,底部导航五个页签——调音器、和弦、跟练、路径、曲库(此票全部为占位页)。真机可安装运行,后续所有工单都在这个壳上长。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `flutter build apk` 成功并安装到真机(OPPO PCAM00,连接方式见 spikes/tech_validation/README.md)
- [ ] 底部导航五页可切换,主题统一(中文 UI)
- [ ] drift 数据库打开无错(空库可用),Riverpod ProviderScope 就位
- [ ] 一条有意义的冒烟测试(App 启动渲染出导航壳)通过
