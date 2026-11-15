# 65: 审计消化 2026-11-15(月度全仓,GPT-6.1-Sol/high)

原始报告:.cc-suite/audits/audit-20261115-audit-mwhetd1v-findings-raw.md
(threadId 01a1ddbc-1bd2-7092-89c4-514a4c397c49,/continue 可续查)
31 条:3 High / 24 Medium / 4 Low,无 Critical。

**Status:** ready-for-agent

## Work Packages

- [x] WP-A(F01,F14)评分麦克风:启动可取消(abort/切页后 pending 请求失效,
  await 后逐点检查)+ 拆线字段先同步摘除再等取消。High+Medium。
- [x] WP-B(F03)备份补 flowing_sessions 段:格式加键,老备份无该段 = 保留
  现有(前向兼容同 image_charts 惯例);恢复到新机不再丢练琴记录。High。
- [ ] WP-C(F04,F12,F13)设置域:备份导入值过界钳制(A4/BPM/打卡日);
  A4 改动用 copyWith 保住 latency;缺键回退改为「默认值」而非「当前值」。
- [ ] WP-D(F05)Cifra Club 搜索源:拒绝带 authority 的 path,导航前校验
  https+host+曲目 path,比对加 origin。
- [x] WP-E(F07,F10)调度器族:时钟不可用时停止全部在响音(三实现同病,
  契约测试锁);start 同步 onError 不再被 playing 态覆盖。
- [x] WP-F(F08,F09)流水谱循环/数拍:清循环要真停循环音频(区分「未传」
  与「显式关」);数拍配置变更先采样旧配置;起始计数中变速显式重排或缓办。
- [x] WP-G(F11)流水谱 play() 重入:同步进 starting 态 + 共享启动 future +
  取消代数。
- [x] WP-H(F15,F21)评分暂停重启恢复采集;退页位置记账把循环回绕/数拍
  间隙/曲末钳制并入(与正常播放共用一份换算)。
- [x] WP-I(F16,F17,F18)体检闸三件:体检过的谱传给跟练(现在跟练页自行
  加载默认资产,票07 多曲后必炸——随 07 一并修);gate 加 chord strings
  长度=4/空谱拒绝;泛音收紧(仅已核验的 12 品自然泛音放行)。
- [x] WP-J(F19)静默 catch 补日志并收窄(仓库已知坑的机械面)。
- [x] WP-K(F24)暂停评分的麦克风缓冲设上限(小时级 ≈318MB)。
- [x] WP-L(F06,F20,F27,F29)→ 票化(68)。
- [x] WP-M(F22,F23)→ 票化(67)。
- [x] WP-N(F28,F30,F31)清理:fake_webview 平台桩/未用依赖(photo_view、
  crypto、cupertino_icons、webview_flutter_platform_interface)/残留注释。
- [x] WP-O(F02)**复核判误报, wontfix**:证据链——①Riverpod 3.4.3
  源码删除了 AutoDispose 变体,全 provider 监听清空即回收(keepAlive 链
  才是选退);②仓库迁移期测试注释「Riverpod 3 无监听即回收」为既立规矩;
  ③票06 真机机检实证退页落库(onDispose 路径执行)。审计引 Riverpod 2
  旧文档误判。
- [ ] WP-P(F25,F26)随 WP-O/WP-F 补测试:真路由弹出保留容器、过旧循环
  边界听音频、坏档输入后重触发 load。

## Comments

- 2026-11-15: 建票。来源 audit-mwhetd1v-8ol3ub(9 分钟完成)。执行顺序
  建议:WP-O 复核(先判误报)→ WP-A/B(High)→ WP-E/F/G(调度族)→
  WP-C/D/H/I/J/K(中小)→ WP-N 清理 → WP-L/M 票化。 WP-I 的谱传递件
  与票07 同批落地。
- 2026-11-15: WP-O/WP-A/WP-B 落地。WP-O 判误报(见上)。WP-A:评分/
  调音两控制器加停麦代数(abort/finish/fail/teardown 经 _stopMic 递增,
  启动流程跨 await 校验过期即弃,迟到麦流就地 stop 不接线不翻状态),
  _stopMic 先同步摘字段再等取消;竞速回归测试×2(开麦门闩挂起→中途
  abort→放行,断言停麦≥2次/不复活/嘀声不接线)。WP-B:备份格式 v2 补
  flowing_sessions 段(v1 备份无该段=空段,覆盖语义按备份清空;未知键
  前向兼容惯例),collect/restore 全字段往返(id 保留自评寻址不变),
  回归测试锁定时长/位置/速度/自评逐字段 + v1 旧格式可解析。938 全过。
- 2026-11-15(第二批): WP-E 四调度器时钟故障宁滥勿漏全停;F10 start
  同步 onError 后 status 有变即不覆盖 playing;WP-F 清循环 loopFromState
  关断(F08,回归红验证过)、数拍开关旧配置先采样、数拍中变速重起数拍
  (F09);WP-G play 重入闸(共享启动 future);WP-H onPassStart 清挂起
  (F15)+ 位置换算单一来源 resolvePosition 微秒域、窗镜像补循环/间隙/
  曲长(F21,期间踩「t0=音乐零点锚无 from 项」语义坑,连续性测试抓回);
  WP-I 闸门谱传递(local scope 覆盖装载缝)+守门三规则(空谱/和弦弦数/
  非12品泛音,电池用例红绿验证);WP-J 三处静默 catch 补日志;WP-K 重听
  缓冲 20 分钟窗口淘汰+挂起期不进缓冲;WP-N 清理(fake_webview/依赖/
  注释)。WP-M/L 票化(67/68)。941→944 全绿。
