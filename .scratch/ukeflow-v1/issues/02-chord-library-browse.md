# 02: 和弦库浏览(数据+指法图+要点)

**What to build:** 和弦库页:内置和弦指法数据(chords-db ukulele.json,MIT),按字母/常用程度分组浏览;详情页自绘和弦指法图(品位点、手指编号、空弦与闷音标记)+按法要点与常见错误文字提示;可按和弦名搜索直达。这是 Glossary 中"和弦指法"的可视化("和弦图")。

**Blocked by:** 01 工程骨架与五页导航壳

**Status:** done

- [x] 真机可浏览常用和弦全集(至少含 C G Am F G7 Em Dm D E7 A7 等新手套件,20+ 个)
- [x] 指法图绘制与数据一致(品位、手指、空弦/闷音标记)
- [x] 分组浏览与搜索直达可用
- [x] 和弦数据加载有测试(fixture 驱动,坏数据可见报错)

## Comments

- 2026-10-09: 落地。资产 = chords-db master 快照原文件(`assets/chords/ukulele.json`,215KB,552 和弦 / 2114 指法,MIT 许可证随库入库)。语义先验证后编码:baseFret>1 时 frets/barres 为窗口相对品位,已对全量 midi 零误差验证。切片 TDD:① `ChordLibrary.parse` 解析+校验(8 种坏 fixture 可见报错,真实资产过校验)② `ChordDiagramLayout` 指法→几何纯函数(品位/空弦○/闷音×/横按跨度,手算真值)③ 浏览/详情页 widget 测试。34 测试全绿,analyzer 无告警。
- 2026-10-09: 常用套件 25 个置顶(C~Bb,含工单要求全部 10 个);`primaryFingering` 启发式选主指法(第一品窗口 > 空弦多 > 品位和低)——数据源首指法未必是入门按法(如 Asus2 首选 5 品横按,已排除出套件)。要点/常见错误为人工内容(25 条),且**逐条对 chords-db 实测指法核对过**(评审抓到初稿 G/G7/Cm/F7/D7 凭吉他记忆写错,已全部重写);套件×文案一致性有测试守护。长尾和弦按指法形状生成通用提示。
- 2026-10-09: 跨模型双轴评审修复:①域模型迁 `core/model/chord.dart`(对齐 architecture.md 模块树,data 层只留解析+provider)②双横按全画(资产 74 处,如 A7sus4)③坏数据异常改名 `ChordDataError` 并继承 Error——Riverpod 3.4 默认对 Exception 自动退避重试(200ms→6.4s×10 次),坏数据重读同一资产毫无意义,Error 类型即刻可见报错④删除死字段 capo、品位窗固化为解析契约(`fretsOnChord==4` 否则拒载)⑤浏览列表条目密封类化⑥测试 helper 去重。搜索"直达"实现为过滤+点瓦片(精确命中不自动进详情),v1 解释为可接受,后续有需求再做结果直达。
- 2026-10-09: 测试环境两坑,记录备查:testWidgets 的 FakeAsync 里 `rootBundle` 真实文件 I/O 永远完不了(会挂死)——widget 测试一律注入 fixture 数据(普通 `test()` 里 rootBundle 可用);评审过程发现的探针测试忘了删会挂死全量运行。APK 已构建(56MB)并装真机(OPPO PCAM00,无线 adb)启动,真机浏览/搜索/详情待人工过目后勾第一项。
- 2026-10-09: 真机验收通过(用户过目:浏览/搜索/详情)。**本票完成。**
