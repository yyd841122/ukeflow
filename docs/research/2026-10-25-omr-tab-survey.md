# OMR 对「四线谱 TAB 位图 PDF」识别能力调研

日期:2026-10-25
问题:公开 OMR 项目里,有没有能识别「谱全了」式位图 PDF(993×1404,纯嵌入位图无矢量无文本层;每系统 4 弦 TAB + 和弦图 + 简谱旋律 + 歌词,带出版社自家记号:卷弦波浪线、滑音斜线、震音椭圆框、实心点休止)的?

纪律:下文所有「支持 TAB」类论断均区分 **[官方声称]**(产品页/README 写了)与 **[实测可靠]**(有第三方或我们实测背书)。本调研没有条件装机实测商业工具,故 **全部结论停留在官方声称层**,除非另行标注。查不到就写「未查到」。

---

## 1. 结论先行(三档)

### A. 可直接用 —— 有轮子,但只有商业闭源工具在「官方层面」支持,且必须实测

**没有任何开源项目能开箱识别四弦 TAB 位图。** 商业工具里有两家在官方页明确声称支持 4 弦 TAB 位图:

| 工具 | 为什么值得花一小时实测 |
|---|---|
| **Soundslice 扫描器**(在线,专有) | 官方 FAQ 明确:「检测 tablature,无论是否带配套五线谱」(tab-only 2022-09 起支持)、「检测和弦图(fretboard grids)」、明确「PDF 是矢量还是实为照片均可」、可导出 MusicXML。免费档 2 次/月(1 页 32 小节),够做一轮 PoC。 |
| **PhotoScore & NotateMe Ultimate**(桌面,专有) | 官方页明文:「recognizes **4 and 6 line guitar tablature**」、识别和弦图、可开 PDF、存 MusicXML/MIDI。这是唯一官方声称 4 弦的传统桌面 OMR。 |

外加一个低价候选:SmartScore 64 **Guitar Edition**($99,官方称含 tablature 识别 + 定制 TAB 调弦库)。

**预期警告(不是泼冷水,是定预期)**:「官方声称支持 4 弦 TAB」≠「对谱全了这种 993×1404 屏幕级分辨率位图可靠」。商业 OMR 的设计输入是 300dpi 扫描件(宽通常 2000px+);谱全了 PDF 每系统弦距只有约 14px(scale3 实测,见仓库既有像素考古结论),这个输入质量处于所有 OMR 工具舒适区之外。而且即使音符识别对了,出版社记号(卷弦波浪/震音椭圆/实心点休止)在 MusicXML 里没有对应元素,必然静默丢失。**实测前别指望「免核对」,只指望「把逐小节手抄降级成逐小节校对」。**

### B. 需改造 —— 开源世界有「TAB OMR」的唯一模型先例,可当蓝图

- **Tabbox / LIU9293/guitar-tab-omr**(GitHub,8 star,3 commits):这是调研中找到的**唯一一个真正的开源 TAB 位图→token 的 OMR 模型**。单系统裁剪图 → 自家 OMR token 序列,224×1200 输入,256 维 hidden、3 层 decoder 的小 transformer;自建 ~1200 样本训练集(从 PDF 生成,HuggingFace 有 kk9293/tabbox-guitar-omr-1200-v1,数据卡需登录未能核验),200 张留出集上 76.5% 整句精确匹配、99.5% 可解析、token 编辑相似度 ~97.6%。**是 6 弦、单系统、纯 TAB 轨,不含和弦图/简谱/歌词,license 未标注**。它证明了一件事:小模型 + 几百到千级自造样本就能到「大半可解析」的水平,这条路对 4 弦重训完全开放。
- **Audiveris**(AGPL-3.0,Java):官方 issue 确认,4/6 弦 TAB 打开开关后只是**「检测出来然后丢弃」**(导出的 MusicXML 里 TAB 谱表填哑休止);2024-10 维护者论坛原话是 TAB「各出版社差异大」,考虑用单次检测(SSD)重做,但**无时间表、要先看样例图**。对谱全了的用途是零,最多借它的位图前处理/五线谱版面代码(改造不值)。
- **oemer / homr**(端到端深度学习 OMR):训练集是 CvcMuscima-Distortions + DeepScores-extended,**只有五线谱记谱**,README 自己警告不适用于其他记谱类型。TAB 不适用。
- **Rodan**(DDMAL/SIMSSA 的云 workflow,挂 Audiveris job):Audiveris 的限制原样继承,TAB 丢弃。只是部署形态不同(web、K8s)。

### C. 无轮子 —— 最省力半自动路线(推荐认真考虑)

谱全了 PDF 的版式是**固定网格**(固定页宽 993×1404、每系统 4 弦、和弦图位置规则),这恰恰是「深度 OMR」最不必要、规则化方法最快解的形态:

1. **版面切分**:按既有像素考古结论(tabLineGap=14px@scale3 等)做条带/小节定位——这层 UkeFlow 已经有通道。
2. **TAB 数字识别**:fret 数字是 0–9 十个字的印刷体,用现成 OCR(PaddleOCR/Tesseract 级)或自标几百个样本训个小分类器,准确率应当远高于通用 OMR 对整谱的识别。
3. **自家记号**:模板匹配(震音椭圆框、实心点、波浪线都是形状特异的封闭模板),比训练通用模型便宜得多。
4. **人工核对**:识别结果落成 UkeFlow 内部谱面数据结构(而不是 MusicXML),沿用现有「逐位对照」工作流。

这条路没有现成轮子,但每一段都是「小时级」工作量,且输出直接是应用内格式,不经 MusicXML 语义损耗。学术侧的合成数据先例(PrIMuS 用 Verovio 渲染、Transcoda 2026 全合成训练)证明了「自绘渲染器造训练谱」是 OMR 领域成熟做法——若将来要上序列模型,渲染器可以复用 UkeFlow 自己的谱面渲染器。

---

## 2. 候选项目逐个核证

判据:① 支持 4 弦 TAB?② 吃位图扫描件?③ 可本地部署/可微调?④ 输出格式?⑤ License?⑥ 对谱全了自家记号(卷弦波浪/滑音斜线/震音椭圆/休止点)的覆盖?

### 2.1 Audiveris —— 开源 OMR 旗舰,但 TAB 是「检测后丢弃」

| 判据 | 结论 |
|---|---|
| ① 4 弦 TAB | **否(识别层面)**。Book 参数里有「4-line bass tablatures」「6-line guitar tablatures」两个开关;打开后维护者原话:会把这些谱表「detect as tablatures and will simply **ignore** the corresponding areas」,再次确认「**detected and discarded, not transcribed**」,导出 MusicXML 里 TAB 谱表填哑休止。曾因 TAB 触发 NPE(“A tablature has no notion of pitch”),已修(commit 12e1bde)。 |
| ② 位图输入 | **是,这正是它的主场**:定位是「score image → symbolic」,面向 IMSLP 类扫描件;手册列输入格式 PDF/TIFF/JPG/PNG/BMP(PDF/TIFF 支持多页)。谱全了的纯位图 PDF 在格式层面直接可喂。 |
| ③ 本地部署/微调 | 本地桌面(Java,Win/Linux/macOS,5.5 起安装包带 JRE);不可微调(非学习式管线,内置浅网络)。 |
| ④ 输出 | MusicXML 4.0 子集(另有 .omr 工程 XML、PDF、zip 导出)。 |
| ⑤ License | AGPL-3.0(仓库 Resources 区明示)。 |
| ⑥ 自家记号 | 零。且和弦图官方承认「yet no reliable means to discard them」,会误识别成连线/点等伪迹,需手动删。 |

TAB 现状细节:2024-10 讨论 #754 中维护者 hbitteur 解释不做 TAB 的原因是「各出版社记法差异大」,OCR 不适合识别孤立数字(「meant to detect lines of words, not isolated numbers」),设想将来用 SSD(类人脸检测)识别品位数字;但**明确无排期**,并索要样例图评估。维护者还提到自己试过深度学习 patch 分类器,能work但一页要跑几天,弃用。

结论:**对「识别四弦 TAB」为零贡献;AGPL 对嵌入自用 app 也有传染性注意点。**唯一价值是「位图→版面元素」这套前处理代码可读可借鉴(Java)。

### 2.2 oemer(及 meteo-team fork、homr)—— 端到端深度 OMR,五线谱专用

| 判据 | 结论 |
|---|---|
| ① 4 弦 TAB | 否。README 明确警告不适用于手写体和其他记谱类型;训练集 CvcMuscima-Distortions + DeepScores-extended 全是五线谱。 |
| ② 位图输入 | 是,主打手机拍摄/倾斜照片。输入是图片(PDF 未提及,先转图即可)。 |
| ③ 本地/微调 | 本地 Python;模型可跑,但重训需重造训练集(五线谱数据集对 TAB 无用)。 |
| ④ 输出 | MusicXML。 |
| ⑤ License | MIT。818 star。 |
| ⑥ 自家记号 | 零。 |

生态:BreezeWhite/oemer 原仓库 README 推荐功能更稳的 fork **liebharc/homr**(相机照片→MusicXML);另有 meteo-team/oemer fork 默认改用 Onnxruntime 推理。结论:**架构可参考(分段 UNet + 序列识别),对 TAB 本身无用。**

### 2.3 Rodan —— Audiveris 的云 workflow 封装

DDMAL(麦吉尔 SIMSSA 项目)的 web-based workflow 引擎,生产实例 rodan2.simssa.ca(现 rodan2),把 Audiveris 等 OMR 工具作为 job 串进流程(官方 e2e-omr 文档如此介绍)。部署 repo(DDMAL/Rodan,46 star,活跃 CI,K8s 部署)页面未标 license(待验证,需看主 repo)。**TAB 限制与 Audiveris 完全一致(检测后丢弃),对本研究无增益**;它的价值在「多阶段 OMR 流水线 + 人工交互校对」的工程形态可借鉴。

### 2.4 Tabbox / LIU9293/guitar-tab-omr —— 唯一开源「TAB 位图 OMR 模型」先例 ★

| 判据 | 结论 |
|---|---|
| ① 4 弦 TAB | **否,6 弦**(模型与数据集名均为 guitar tab);但网络结构对弦数不敏感(输入图 + token 序列),4 弦重训在架构上无障碍。 |
| ② 位图输入 | 是,单系统裁剪的 TAB 图(224×1200 归一化)。 |
| ③ 本地/微调 | 是。训练/评测代码在 GitHub,权重在 HuggingFace(kk9293/guitar-tab-omr);小型 transformer(hidden 256、3 层 decoder、4 头、FFN 1024、max_seq 384、bf16、25 epochs)。 |
| ④ 输出 | 自家「Tabbox OMR token」序列(标准 TAB token),可解析率 99.5%,整句精确匹配 76.5%(留出 200 样本)。token 词表未在 repo 文档化。 |
| ⑤ License | **未标注**(repo 与页面均未见;待验证/需联系作者)。8 star、3 commits,个人复现性质,tabbox.io 有在线 demo(页面为 JS 应用,细节抓不到)。 |
| ⑥ 自家记号 | 零(6 弦通用记法,无卷弦波浪/震音椭圆概念)。 |

**这是本次调研对「需改造」档最有价值的一条**:它验证了「PDF 造数据 + 千级样本 + 小 transformer → TAB 图到 token」的最小可行路线;改造点为 4 弦词表、谱全了记号 token、多谱层(和弦图/简谱)分离。风险:项目极小众(3 commits),数据集细节(HF 卡 401 需登录)与 license 均未核实。

### 2.5 GitHub 定向搜索:tablature OCR / guitar tab recognition / TAB OMR / ukulele OCR

| 项目 | 状态 | 能干什么 |
|---|---|---|
| LIU9293/guitar-tab-omr(见 2.4) | 8 star,3 commits | 唯一真 TAB-OMR 模型。 |
| sn0v/OCR-tabber | 6 star,22 commits,Apache-2.0,带近期 AI 辅助开发痕迹(AGENTS.md 等) | Tesseract 扫 TAB 图 → ASCII tab,附带 512 和弦库识别。玩具级、面向 ASCII 排版的谱,对印刷位图 PDF 不适用。 |
| louislam/its-mytabs | 开源自托管 | Songsterr 式 TAB 播放器(吉他/贝斯),**纯查看器,无识别**。 |
| meteo-team/oemer、liebharc/homr | 活跃 fork | 见 2.2。 |
| ilDeffo/Guitar-Fingering-Chords-Recognition | 2021 课程级项目(搜索结果提及,未直接核验) | 和弦按法 CV 识别,非谱面识别。 |
| 「ukulele OCR」 | **未查到任何相关项目**。GitHub ukulele topic 下只有泰国某「尤克里里考级答题卡 OCR 打分」项目,与 TAB 识别无关。 | — |

**结论:GitHub 上不存在四弦/尤克里里 TAB 识别的可用项目;六弦向也只有一个未竟的小模型先例。**

### 2.6 Soundslice 扫描器 —— 商业在线,官方声称支持 tab-only 与和弦图 ★

| 判据 | 结论 |
|---|---|
| ① 4 弦 TAB | **[官方声称]未限定弦数**:「Yes. We detect tablature, whether or not it has an attached standard-notation stave」(tab-only 2022-09 起官方支持,「Caveats apply for tab-only music」)。4 弦是否在实测覆盖内未验证。 |
| ② 位图 | **是,官方明文**:「It doesn't matter whether your PDF uses vectors ... or is effectively a photograph」。输入 JPG/PNG/GIF/BMP/PDF/HEIC/TIFF/WEBP。 |
| ③ 本地/微调 | 否,闭源在线服务。 |
| ④ 输出 | 官方 FAQ:「You can export as MusicXML」+ MIDI。 |
| ⑤ License | 专有。价格:免费档 2 次/月(限 1 页、32 小节);Plus 100 页/月、单次 25 页(月费金额页面摘要未给出,待查)。处理速度自称约 1 分钟/页。 |
| ⑥ 自家记号 | 无声称。和弦图官方称检测;卷弦波浪/震音椭圆/实心点休止必然不在,落 MusicXML 时丢失。 |

**它是 A 档里 PoC 成本最低的(免费档即可试谱全了样张),建议第一轮实测对象。**

### 2.7 PhotoScore & NotateMe Ultimate —— 官方明文「4 and 6 line guitar tablature」★

| 判据 | 结论 |
|---|---|
| ① 4 弦 TAB | **[官方声称]是**:产品页原话「picks out virtually every detail and even recognizes **4 and 6 line guitar tablature**, 1, 2 and 3 line percussion staves」;版本对比表里 Ultimate 读「4- and 6-string guitar tab」(Lite 仅 6 弦)。更新日志提到读 TAB 的品位数字与叉号、自动推算时值并插入休止。 |
| ② 位图 | 是:可开 PDF 文件,支持扫描仪自动进纸识别(传统 OMR 定位)。 |
| ③ 本地/微调 | 本地桌面;不可微调。 |
| ④ 输出 | 直送 Sibelius;存 MusicXML、MIDI、PhotoScore 格式;Ultimate 可存 WAV/AIFF。 |
| ⑤ License | 专有;页面未标价(需进 Ordering 页,未查到具体数字,待验证)。 |
| ⑥ 自家记号 | 无声称。和弦图官方对比表标 yes(读),但谱全了式记号无对应输出。 |

注意:neuratron.com 页面内容停留在「PhotoScore & NotateMe Ultimate 2020」(页面日期 2021-05);现由 Avid 渠道分销。**四个判据层面它是传统桌面 OMR 里对本研究最友好的,但「官方声称」与谱全了实测之间隔着分辨率与记号两道坎。**

### 2.8 SmartScore 64(Musitek)—— Guitar 版 $99,官方称 TAB 识别

- 现产品线无「Ultimate」名(那是 SmartScore X2 时代捆绑名,未查到现行对应);现行版次:Professional NE / Songbook NE / **Guitar** / MIDI。
- **Guitar Edition($99)**[官方声称]:「Includes tablature recognition」「customized TAB tunings library」「Notation-TAB-Notation conversion」;未写弦数(4 弦待验证)。可升级到 Songbook/Professional。
- Songbook NE[官方声称]:含 Professional 全功能 + 「TAB and percussion recognition/editing」,但限每系统 3 个谱表(对钢琴声乐谱;对我们单 TAB 无影响),含 PDF 识别。
- 输出 MIDI/MusicXML;专有。
- ⑥ 自家记号:零。
- 结论:**A 档里价格最低的本地候选;4 弦是否被 Guitar 版覆盖官方页未写,买前需实测 demo 版。**

### 2.9 ScanScore —— 未发现 TAB 支持

官方站只讲五线谱识别与 MusicXML/MIDI 导出;其 ScanScore 3 手册(67 页 PDF,已全文提取检索)**「tab」仅命中 UI 标签页含义,零 tablature 内容**。结论:**无 TAB 支持(以官方手册检索为准),淘汰。**

### 2.10 PDFtoMusic Pro(Myriad)—— 只吃矢量 PDF,直接出局

官方页原话:「**Therefore, scanned sheet music cannot be managed by PDFtoMusic Pro.**」它读取乐谱程序导出的矢量/文本数据重建乐谱,输出 MusicXML/MIDI/Myr/WAV/AIFF。谱全了是纯位图 PDF,**直接不符合输入前提。**

### 2.11 PlayScore 2 —— 官方明确不支持 TAB

官方 FAQ:「**PlayScore does not support guitar tab. Tab music will not play at all in PlayScore**」,五线谱+TAB 合排的谱只按五线谱部分处理。淘汰(它与 Klangio 同为「音频/演奏向」或五线谱向)。

### 2.12 Klangio(Guitar2Tabs 等)—— 音频方向,非图像,确认出局

官方页:Guitar2Tabs「transcribe **Audio, Music and YouTube** into Tabs, Sheet Music, MIDI and GuitarPro」;产品线 Piano2Notes、Transcription Studio、录音插件,输入全是音频/视频。**无图像 OMR 能力(未声称)**,不符合本研究输入形态。免费试用 + 订阅制。

### 2.13 学术与模型

- **端到端 OMR 可微调模型**:oemer(UNet+SVM+序列,MIT)与 homr(fork)是开源代表;**Transcoda**(arXiv 2605.10835,2026-05,Dratschuk & Swoboda)是当前「全合成数据训练端到端 OMR」的极端案例:59M 参数、单卡 6 小时、合成 **kern**+语法解码,合成基准 OMR-NED 18.46%(次优 Legato 43.91%),但历史波兰扫描件上错误率仍有 63.97%——**印证「合成→真实」落差仍是硬骨头**。
- **TAB 专属论文**:Wiggins & Kim《Guitar Tablature Estimation with a Convolutional Neural Network》(ISMIR 2019,~81 引)是 TAB 直接估计的代表作,但输入是 **GuitarSet 音频**(audio→tab),不是图像——「TAB OMR」的学术文献几乎空白(未查到以图像为输入、同行评审的 TAB 识别论文;另有数篇视频/音频向硕士论文,如 Polytechnique Montréal 2022,均非位图谱面)。
- **TAB 图像数据集**:未查到公开数据集(Tabbox 自建 1200 样本未公开源 PDF/图,HF 卡需登录)。
- **自绘渲染器合成训练谱的先例**:成熟做法。**PrIMuS / Camera-PrIMuS**(Calvo-Zaragoza & Rizo,Alicia 大学 GRFIA):RISM 信库 incipits 经 **Verovio** 渲染(Leipzig/Bravura/Gootville 三字体)成图,Camera-PrIMuS 加拍摄畸变,87,678 张单声部图像 + agnostic/semantic 双编码,是端到端 OMR 的标准训练集。Transcoda 2026 则完全靠合成管线。**对谱全了的启示:用 UkeFlow 自己的谱面渲染器按印张版式反向渲染 4 弦 TAB,即可自造训练集,无需人工标注像素。**

### 2.14 MusicXML 4.0 与 TAB 渲染库(落地格式)

- **MusicXML 4.0 对 TAB 的编码能力**(官方 spec 已核):
  - TAB 谱表:`<staff-details><staff-lines>6</staff-lines>` + 每弦 `<staff-tuning line="N">`(tuning-step/octave),谱号 `<sign>TAB</sign>`;弦数写几就是几,**4 弦天然合法**(1 弦=最高音)。
  - 音位:`<note><notations>…<technical><string>3</string><fret>5</fret></technical>`;隐藏节奏仍需编码(hidden key/time、print-object="no")。
  - 技巧:`<hammer-on>`/`<pull-off>`(type start/stop,配 `<slur>`)、`<slide>`、`<bend>`、`<harmonic>`、`<tremolo>`、和弦图 `<frame>/<frame-note>/<barre>` 等元素在 4.0 参考索引里全部存在。官方教程明确警告 `<harmonic>` 与 `<bend>`「only sporadic software support」——**写了元素 ≠ 各软件认**。
  - 对谱全了记号的映射建议(约定,非标准):滑音斜线→`<slide>`;震音椭圆框→`<tremolo>`(unmeasured)勉强近似;卷弦波浪线→`<tremolo>` 波线近似或 `other-technical`/`other-notation` 扩展位(未逐页核验其细节);实心点休止→`<rest>` 加自定义 display。**即: MusicXML 能装下「音符+品位」的绝大部分,装不下出版社记号的语义,只能近似或私扩。**
- **开源 TAB 渲染/播放库**(作「识别结果落地格式」参考):
  - **alphaTab**(coderline,MPL-2.0,1.9k star,活跃):JS/.NET/Android;导入 Guitar Pro 3–8 + **MusicXML** + Capella + alphaTex;渲染吉他/贝斯 TAB + 鼓谱 + slash + **简谱(numbered notation)**——对 UkeFlow 的「简谱+TAB 同页」需求意外契合,可作为数据交换/对照渲染的参考实现。
  - **VexFlow**(0xfe/vexflow,MIT,~4.4k star):「rendering music notation and guitar tablature」,Canvas/SVG;低层绘图引擎,无文件导入。VexFlow 5 开发在 vexflow/vexflow 新仓库。
  - 结论:MusicXML(含 4 弦 staff-tuning)→ alphaTab/VexFlow 渲染管线是通的;**但落地格式建议仍是 UkeFlow 内部结构,MusicXML 只做对外交换**。

---

## 3. 最后一公里缺口(为什么「支持 TAB」不等于「能用」)

1. **分辨率鸿沟**:谱全了页宽 993px(屏幕级),弦距 ~14px@scale3;商业 OMR 按 300dpi 扫描(2000px+)调优。放大/超分后识别率如何,**没有任何一方给出数据,只能实测**。
2. **4 弦支持面极窄**:官方声称支持 4 弦的只有 PhotoScore 一家(桌面)+ Soundslice(在线,未限弦数);SmartScore Guitar 版弦数未写;开源侧零。
3. **多谱层版式无人见过**:TAB + 和弦图 + 简谱旋律 + 歌词同系统的中文流行歌谱版式,在所有国外 OMR 的训练/设计分布之外;简谱(numbered notation)在 OMR 语境里几乎不存在(仅 alphaTab 把它当渲染目标)。
4. **出版社记号零覆盖**:卷弦波浪线、震音椭圆框、实心点休止在所有工具的输出里必然静默丢失;MusicXML 无对应语义元素,只能近似或私扩,且「other-*」扩展下游软件不认。
5. **「识别出来」≠「免核对」**:即便最好的候选(Tabbox 先例)整句精确匹配也只有 76.5%,且那还是单系统纯 TAB、自造测试集上的数字。落到谱全了,预期是「转录工作量从 100% 降到 30–50% 的校对」,而不是自动化。

**给 UkeFlow 的行动建议(按性价比排序)**:① 用 Soundslice 免费档跑一张谱全了样张(成本≈0,验证商业上限);② 用 PhotoScore/SmartScore 试用版跑同一张(验证桌面上限);③ 两者都不行(大概率),走 C 档:规则化切分 + 数字 OCR + 模板匹配记号 + 自渲染器造数据备用,沿用现有「逐位对照」工作流把单首工作轮压缩到「校对半轮」。

---

## 4. 引用清单

**开源 OMR**
- Audiveris 仓库(AGPL-3.0、MusicXML 4.0 导出、image→symbolic 定位):https://github.com/Audiveris/audiveris
- Audiveris issue #634「Status of guitar tablatures and guitar chord drawings」(检测后丢弃、和弦图无法丢弃、NPE 修复):https://github.com/Audiveris/audiveris/issues/634
- Audiveris discussion #754「Tabulature reading」(维护者谈 TAB 难点与 SSD 设想、无排期):https://github.com/Audiveris/audiveris/discussions/754
- Audiveris 手册(输入 PDF/TIFF/JPG/PNG/BMP):https://audiveris.github.io/audiveris/ 及 https://github.com/Audiveris/audiveris-eg/blob/master/data/www/docs/manual/handbook.html
- oemer(训练集、五线谱限定、MIT、推荐 homr):https://github.com/BreezeWhite/oemer
- meteo-team/oemer(Onnxruntime fork):https://github.com/meteo-team/oemer
- liebharc/homr:https://github.com/liebharc/homr
- Rodan(Deployment repo,K8s,rodan2.simssa.ca):https://github.com/DDMAL/Rodan;Rodan 与 OMR job 说明:https://ddmal.ca/e2e-omr-documentation/overview/rodan.html
- LIU9293/guitar-tab-omr(Tabbox,模型细节与指标):https://github.com/LIU9293/guitar-tab-omr;权重 https://huggingface.co/kk9293/guitar-tab-omr;数据集 https://huggingface.co/datasets/kk9293/tabbox-guitar-omr-1200-v1(401,未核验);demo https://tabbox.io
- sn0v/OCR-tabber:https://github.com/sn0v/OCR-tabber
- louislam/its-mytabs(查看器,非 OCR):https://github.com/louislam/its-mytabs

**商业工具**
- Soundslice 扫描器 FAQ(tab-only、和弦图、矢量/照片 PDF、MusicXML 导出、免费档):https://www.soundslice.com/sheet-music-scanner/ ;tab-only 更新公告:https://www.soundslice.com/blog/music-scanning
- PhotoScore & NotateMe Ultimate(4/6 line tablature 原文、和弦图、PDF、MusicXML/MIDI):https://www.neuratron.com/photoscore.htm
- SmartScore 64 Guitar Edition($99、tablature recognition、TAB 调弦库、Notation-TAB-Notation):https://www.musitek.com/store/SS64Guitar.html ;Songbook NE 功能(TAB & percussion recognition/editing):https://www.musitek.com/smartscore-online-help/songbook/getting_started/welcome_to_smartscore.php
- ScanScore 3 手册(全文检索无 tablature):https://scan-score.com/files/support/manual.pdf ;官网 https://scan-score.com/en
- PDFtoMusic Pro(scanned sheet music cannot be managed 原文):https://www.myriad-online.com/en/products/pdftomusicpro.htm
- PlayScore 2 FAQ(不支持 TAB 原文):https://www.playscore.co/blog/faq-items/guitar-tab ;官网 https://www.playscore.co/
- Klangio Guitar2Tabs(音频输入):https://klang.io/guitar2tabs

**学术与数据**
- Transcoda(全合成训练端到端 OMR,arXiv 2605.10835):https://arxiv.org/abs/2605.10835
- PrIMuS / Camera-PrIMuS(Verovio 渲染合成、87,678 张):https://grfia.dlsi.ua.es/primus/
- Wiggins & Kim, Guitar Tablature Estimation with a CNN(ISMIR 2019,音频向):https://archives.ismir.net/ismir2019/paper/000033.pdf ;代码/数据 https://zenodo.org/records/3527800
- OMR-Datasets 总目录:https://apacha.github.io/OMR-Datasets

**MusicXML 与渲染库**
- MusicXML 4.0 总页:https://www.w3.org/2021/06/musicxml40 ;TAB 教程(staff-tunings/TAB 谱号/string/fret/hammer-on/pull-off/harmonic/bend 支持度警告):https://www.w3.org/2021/06/musicxml40/tutorial/tablature
- `<hammer-on>` 元素参考:https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/hammer-on ;元素总索引(fret/string/slide/bend/tremolo/frame 等均在):https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/
- alphaTab(MPL-2.0,Guitar Pro/MusicXML/alphaTex 导入,TAB+简谱渲染):https://github.com/coderline/alphaTab ;https://www.alphatab.net/docs/introduction
- VexFlow(MIT,TAB 渲染):https://github.com/0xfe/vexflow

**未查到/待验证汇总**:4 弦或尤克里里 TAB 的开源识别项目(未查到);TAB 图像公开数据集(未查到);Tabbox 数据集细节与 license(未核验,HF 需登录);PhotoScore 具体售价与现行版本(页面未标,待查);SmartScore Guitar 版 4 弦覆盖(官方页未写,待验证);Rodan license(部署 repo 未标,待验证);Soundslice 月费具体金额(待查);商业工具对谱全了样张的实测表现(全部未实测)。
