# 27: 搜索源 UX——Cifra Club 原生中文搜索列表

**What to build:** 不换站,把搜索体验原生化:App 内输歌名(中文提示「搜歌名」)→ WebView 载入 `/busca/?q=...`(SPA 浮层结果已验证会自动渲染,2026-10-16 真机实证)→ 注入 JS 抽取结果数组(歌名/艺人/链接/是否有 ukulele 版)→ 渲染成**原生 Flutter 列表页**(中文 UI:歌名+艺人)→ 点结果直达既有 ukulele-first 导入流程(工单 17)。搜索从「葡语浮层里找条目」变成「输歌名→点结果」两次点击,全程中文。

**Blocked by:** 无(17 已落地,本票是其搜索体验的 UX 改造)

**Status:** done

- [x] 输歌名 → 原生中文结果列表(歌名+艺人),不再暴露站点葡语搜索 UI
- [x] 点结果 → 直达导入(ukulele 优先+回退告知,复用 17 管线)
- [x] 搜索失败/零结果给可读中文空态

## Comments

- 2026-10-16 (立票): 用户反馈「搜索界面不太友好」后定向讨论,四方向择一并选「都先立票缓行」,本票为其一(唯一不换站的方向,直接治「界面不友好」而非「覆盖不够」)。**已知情报**:①busca SPA 浮层结果由客户端 API 驱动,真机秒出(beat it/let it be/deixe me ir 三次实证),但浮层 DOM 是 client-rendered,不在存档 HTML 里——抽取 JS 需真机逆向(调试期可临时把 `document.querySelector` 结果 dump 到 logcat);②结果条目含歌名/艺人/Música 类型标(截图实证),URL 需从 DOM href 取;③若 SPA 内部 API 端点可发现(同源 fetch),结果抽取可更稳——逆向时顺带确认;④全页搜索结果页(非浮层)真机实证骨架屏不渲染,不要走那条路。⑤工单 17 的 ukulele-first/回退告知/巴西记谱映射全部复用,本票只做「结果列表」一层。风险:浮层 DOM 类名混淆(同 cifra 正文),抽取按结构不按类名;站点改版即失效——失效形态=回退到现状 WebView 手动搜索,可接受。
- 2026-10-16 (立票): 中文歌覆盖说明(适用于 27/28/29 全部搜索源票):中文曲谱站(弹琴吧等)几乎全是图片谱,ADR-0002 已定图片谱 v1 只读不可跟练、自动转换是物理性难题——**中文歌「搜到可跟练谱」在文本谱源里无解**,兜底路径是粘贴导入+票 26 两行式转换。本票解决的是「搜国际歌的体验」,不解决「中文歌来源」。

- 2026-10-17 (实现): **逆向结论推翻立票的一处预设**——`/busca/?q=` 直载是 404 壳(「全页搜索页不渲染」的实态就是 404 页),浮层只在站内搜索框输入时由 SPA 页内驱动。真机 dump(WebView 里 performance entries + DOM 抽取,两轮):SPA 实际向 `https://solr.sscdn.co/cc/c7/?q=<q>&limit=30` 发请求取**结构化 JSON**(Solr 形状),响应头 `access-control-allow-origin: *`。立票情报③的「内部 API 端点+同源 fetch」路线成立,抽取不走混淆 DOM:WebView 常驻站点首页,**搜索不导航**,页内 fetch 端点(ADR-0002 不破:提取全在 WebView 里,站点主域从不被 Dart 侧直连)。doc 字段实证:`txt` 歌名/`art` 艺人/`dns`+`url` 拼 `/艺人/歌/` 路径/`tipo` 类型('2'=Música 歌页、'6'=Álbum——专辑过滤);零结果=`numFound:0` 空数组。失效形态收口不变:端点挂/改版→fetch 落空→「搜索失败」可读态→退路(右上角浏览原站/文本导入)。
- 2026-10-17 (实现): 结构落点:①17 的导入编排从页面提出 `cifraclub_import.dart`(CifraClubImporter+WebView 驱动最小面),ukulele 优先/导航令牌/落点核对/就绪重试**原样随迁**,补 8 条 fake-driver 单测(这段时序逻辑 17/30 时代只有真机验收覆盖);②搜索编排 `cifraclub_search.dart`(解码+轮询+supersede+连续 pending re-kick——首次搜索撞上首页还在载入时 window 变量会被导航清掉,不 re-kick 只能等超时)+13 条单测,延时注入零值真 async(无 fakeAsync);③原生页 `cifraclub_search_page.dart`:WebView 常驻底层,`IgnorePointer`(不挡则点空白区穿透到隐形站点链接)+`ExcludeSemantics`(不挡则葡语内容全进 a11y 树,读屏可逛到隐形页)双包,原生层整面盖住。全库 519 绿,analyzer 零告警。
- 2026-10-17 (机检): A 输「let it be」→原生中文列表(歌名+艺人,葡语 UI 全隐,a11y 树只剩原生节点);B 点「Beat It / Michael Jackson」→直达导入,ukulele 变体页 10s 未出谱**自动回退原版**(logcat 实证 `/beat-it/ukulele/` → `/beat-it/`),预填文本导入页,校验层正常报 E5/D5 不在库(既有行为);C 搜「zzzqqqxx」→「没有找到…换个歌名试试,或回曲库用文本导入」。logcat 无 E/flutter/FATAL。搜索失败态由单测覆盖(真机断网会断无线 adb,不做)。待用户过目验收后转 done。
- 2026-10-17 (评审落实,双轴): Standards/Spec 两轴评审各抓出三条,同源两处实锤+一处死管线,全部落地:①**页面级 catch 补下家**——重构时 `ref.read(chordLibraryProvider.future)` 留在调用点 try 内、importSong 之外,库加载失败会逃逸成未处理异步异常(旧 17 页有 catch);两页补 `catch → importCatchCopy 横幅`,helper 落 cifraclub_import.dart。②**就地提取恢复**——旧 17 页 `uke==null`(已是 /ukulele/ 或 versao 页)是就地提取,重构版一律先 loadRequest 同一 URL(多余一次导航,违反「删除的守卫要有下家」);importer 恢复就地路径,红验证:新测试「已是 ukulele 页不导航」对修复前实现跑红(loaded 实际含导航)再修绿。superseded 测试随之改写为可达语义(uke 尝试被新导入取代 → 回退原版,回退提取拿原版页新载荷,断言不跨请求串线)。③**hasUkulele 死管线删除**——立票要「是否有 ukulele 版」,真机逆向实证 solr 载荷无此字段(ukulele 存在性由导入时 ukulele-first 探测兜住,列表不标);字段/解码分支删除,决策记录于此。④杂项:FakeDriver/ThrowingDriver 双份并入 test/helpers/cifraclub_fake_driver.dart;FailureBanner 提出独立文件;搜索页共享单个 WebViewDriver;结果链接拼域改 `CifraClubUrls.home.resolve`。终态全库 519 绿,analyzer 零告警;最终版真机复验:zztest 空态、deixe me ir 搜索→1Kilo 导入(回退告知横幅完整可见,预填 Fmaj7/Dm9),logcat 无异常。`_currentUrl!` 的 null 容忍删除:导入钮只在 `_onSongPage`(非 null)时出现,不可达,null 断言安全(原容忍无触发路径,留注释说明)。
- 2026-10-17 (验收): 用户真机过目通过,转 done。
