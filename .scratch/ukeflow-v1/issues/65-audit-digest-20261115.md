# 65: 审计消化 2026-11-15(月度全仓,GPT-6.1-Sol/high)

原始报告:.cc-suite/audits/audit-20261115-audit-mwhetd1v-findings-raw.md
(threadId 01a1ddbc-1bd2-7092-89c4-514a4c397c49,/continue 可续查)
31 条:3 High / 24 Medium / 4 Low,无 Critical。

**Status:** ready-for-agent

## Work Packages

- [ ] WP-A(F01,F14)评分麦克风:启动可取消(abort/切页后 pending 请求失效,
  await 后逐点检查)+ 拆线字段先同步摘除再等取消。High+Medium。
- [ ] WP-B(F03)备份补 flowing_sessions 段:格式加键,老备份无该段 = 保留
  现有(前向兼容同 image_charts 惯例);恢复到新机不再丢练琴记录。High。
- [ ] WP-C(F04,F12,F13)设置域:备份导入值过界钳制(A4/BPM/打卡日);
  A4 改动用 copyWith 保住 latency;缺键回退改为「默认值」而非「当前值」。
- [ ] WP-D(F05)Cifra Club 搜索源:拒绝带 authority 的 path,导航前校验
  https+host+曲目 path,比对加 origin。
- [ ] WP-E(F07,F10)调度器族:时钟不可用时停止全部在响音(三实现同病,
  契约测试锁);start 同步 onError 不再被 playing 态覆盖。
- [ ] WP-F(F08,F09)流水谱循环/数拍:清循环要真停循环音频(区分「未传」
  与「显式关」);数拍配置变更先采样旧配置;起始计数中变速显式重排或缓办。
- [ ] WP-G(F11)流水谱 play() 重入:同步进 starting 态 + 共享启动 future +
  取消代数。
- [ ] WP-H(F15,F21)评分暂停重启恢复采集;退页位置记账把循环回绕/数拍
  间隙/曲末钳制并入(与正常播放共用一份换算)。
- [ ] WP-I(F16,F17,F18)体检闸三件:体检过的谱传给跟练(现在跟练页自行
  加载默认资产,票07 多曲后必炸——随 07 一并修);gate 加 chord strings
  长度=4/空谱拒绝;泛音收紧(仅已核验的 12 品自然泛音放行)。
- [ ] WP-J(F19)静默 catch 补日志并收窄(仓库已知坑的机械面)。
- [ ] WP-K(F24)暂停评分的麦克风缓冲设上限(小时级 ≈318MB)。
- [ ] WP-L(F06,F20,F27,F29)票化四件:备份体积/解析隔离、隐藏集读改写
  原子化、迁移覆盖补强(活表行保留+中断回滚)、调度器生命周期机制抽取。
- [ ] WP-M(F22,F23)性能票:每帧整页重建拆分 + 文本画笔显式 dispose。
- [ ] WP-N(F28,F30,F31)清理:fake_webview 平台桩/未用依赖(photo_view、
  crypto、cupertino_icons、webview_flutter_platform_interface)/残留注释。
- [ ] WP-O(F02)**复核判误报**:审计称 flowing provider 非 autoDispose
  导致退页不停声——引的是 Riverpod 2 文档;Riverpod 3 默认全 provider
  自动回收(仓库迁移记录「AutoDispose 类已删」),票06 机检亦实证退页
  落库路径执行。复核确认后标 wontfix;若复核翻案,升格 WP 修复。
- [ ] WP-P(F25,F26)随 WP-O/WP-F 补测试:真路由弹出保留容器、过旧循环
  边界听音频、坏档输入后重触发 load。

## Comments

- 2026-11-15: 建票。来源 audit-mwhetd1v-8ol3ub(9 分钟完成)。执行顺序
  建议:WP-O 复核(先判误报)→ WP-A/B(High)→ WP-E/F/G(调度族)→
  WP-C/D/H/I/J/K(中小)→ WP-N 清理 → WP-L/M 票化。 WP-I 的谱传递件
  与票07 同批落地。
