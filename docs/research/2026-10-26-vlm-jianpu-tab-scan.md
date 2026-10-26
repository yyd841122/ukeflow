# VLM 识谱 / 简谱识别 / TAB 新项目补充扫描

日期:2026-10-26
性质:**补充调研,不重复 2026-10-25 普查已覆盖项目**(Audiveris / oemer / homr / Rodan / ScanScore / PDFtoMusic / PlayScore / Klangio / sn0v-OCR-tabber / its-mytabs 见 `docs/research/2026-10-25-omr-tab-survey.md`,本文不重复)。
纪律同昨日:区分 **[官方声称]**(产品页/README/模型卡自述)与 **[实测可靠]**(论文基准或第三方背书;本研究本身未做任何复现);查不到就写「未查到」。

---

## 1. 结论先行

1. **VLM OMR 是 2025-2026 真实爆发点,但与 TAB 无缘。** 专用 VLM OMR(LEGATO 2、腾讯 Youtu-Parsing-Omni)已在五线谱基准上超过 Audiveris 与 Gemini 3.1 Pro;通用 MLLM(GPT-4o/Gemini)在四个新基准上一致偏弱。**所有 VLM OMR 都只做五线谱,TAB 与简谱零覆盖。**
2. **昨日「简谱在 OMR 语境几乎不存在」的判断需修正。** 中文生态存在完整的简谱识别工具链:学术线旋律 F1 0.951(arXiv 2512.14758)、开源线 dolce(MIT、活跃、PaddleOCR 离线)、OrpheusNet(MIT)、MusicalScoreRecognition(67★),商业线壹谱网「易识谱」。**对谱全了的简谱旋律层,存在近现成识别工具,这是本次补充调研最大的新增变量。**
3. **四弦/尤克里里 TAB 位图识别仍是零。** LIU9293/guitar-tab-omr 无更新;新出现的 string-space 证明「Tesseract+几何启发」六弦路线能落地(即昨日 C 档路线的活样本),但 0★4 commits。
4. **Soundslice 价格查实(Plus $5/月),tab-only 致命缺陷坐实:节奏不识别、全落四分音符。** 四弦实测报告未查到。
5. **Dart/Flutter 侧 MusicXML 解析可用**,另有 crisp_notation 家族(纯 Dart、Guitar Pro 导入、tab 渲染、可跑 OMR)是意外高价值参照。
6. **指法求解有多个可参考开源实现**(含 ukulele),但多声部指法分配的成熟开源实现未查到。

**对昨日行动建议的影响:不改路线,反而加固。** 新增动作:① 谱全了的简谱层先拿 dolce 免费试识别(成本≈0);② Soundslice PoC 仍值得免费档一跑,但「全四分音符」已知缺陷应计入预期;③ crisp_notation/flutter_notemus 列入读码清单备将来。

---

## 2. 角度一:多模态大模型识谱(VLM OMR)

### 2.1 专用 VLM OMR 模型(全部五线谱专用)

- **LEGATO 2**(arXiv 2607.05769,2026-07,Univ. of Washington / AI2)★:管线 = YOLOv8-medium 系统切分 → 从头训练的 Llama-3.2-11B-Vision 架构解码器(~113.7M 可训参数)自回归输出 System-Level ABC → 规则合并。自称首个能输出嵌入文字内容(标题/作者/注记)的 OMR 模型。OMR-NED(越低越好):PDMX-Synth 23.5、OpenScore 渲染 17.1、相机 OpenScore 31.6、IMSLP 钢琴 34.2,**全面胜 Legato 1、Audiveris、Gemini 3.1 Pro**;文本 CER 24.8(Gemini 58.1、Audiveris 73.8)。用它作上下文还把 Gemini 3 Flash 在 MusiXQA 的 G-Acc 从 8.4 拉到 25.3。[实测可靠](论文自带基准,非独立复现)——但**代码承诺发表后放出,截至 2026-10-26 未放出,轮子不可得**;无 TAB、无简谱、歌词显式排除。
- **Youtu-Parsing-Omni**(腾讯优图,HuggingFace)★:5B 全模态解析 VLM(文档/图表/几何/音视频→统一 OmniSchema JSON),乐谱识别是其中一项;PDMX-Synth 上 CER 22.73 / SER 26.73 / LER 33.20,CER 胜 LEGATO、GPT-5.6、Gemini-3-Pro;OmniDocBench v1.6 总分 96.96。**License 是自定义「youtu-parsing」,非标准开源协议**;权重 BF16 可下载(月下载 ~2584)。[官方声称](模型卡自报,未见第三方复现);无 TAB/简谱证据。
- GitHub「OMR GPT-4o」仓库搜索:**0 结果**;未查到任何直接包裹 GPT-4o/Claude/Qwen-VL 读谱图输出 MusicXML/ABC 的开源仓库。

### 2.2 通用 MLLM 识谱基准(一致结论:弱)

| 基准 | 出处 | 结论 |
|---|---|---|
| SSMR-Bench | arXiv 2509.04059,2025-09 | 合成可验证识谱题;视觉形态乐谱对所有模型都是短板;RLVR 训练可提升 |
| WildScore | arXiv 2509.04744,EMNLP 2025 main | 首个 in-the-wild 乐谱理解基准;7 个 SOTA MLLM「视觉准确率有提升,符号级细粒度理解持续困难」 |
| MuSP-Bench | arXiv 2608.28212,2026-08 | 490 道人工题;「模型对乐谱与演奏理解存在重大缺口」 |
| MuseBench | OpenReview kDqH5KmRWR | 三模态(乐理文本/谱图/演奏音频),评了 GPT-4o 等 |

社区侧:Reddit 多帖报告 GPT-4o 读乐谱/电路图等符号图表现差(非正式实测)。

### 2.3 简谱 × VLM:有没有人实测?

**未查到任何系统性实测或准确率数据。** 唯一线索:CSDN 2026 文称腾讯 Youtu-VL-4B-Instruct「可识别乐谱图片输出音符并生成 MIDI」——单源转述、无 benchmark,标 [官方声称·未核]。若考虑此路需自测,无现成数据背书。

### 2.4 VLM/LLM 包裹型项目(旁证)

- raulkivi/sheet-music-mcp(MIT,1★,132 commits):六个 MCP server,读谱仍用 oemer/Audiveris 专用引擎,Claude 只在 ABC 文本层编排——2026 年实践者也不拿 VLM 直接读谱图,是旁证。
- luma-keys、omr-lab 等 topic 新仓:AI 成分是「本地 llama-cpp 伴侣」而非 VLM 读谱,无增量。

---

## 3. 角度二:简谱识别专门项目 ★(修正昨日结论)

### 3.1 学术线

- **Bu et al., arXiv 2512.14758(2025-12-15)**:印刷体中文简谱(含歌词)→ MusicXML/MIDI。模块化专家系统管线(经典 CV:乐句相关/骨架分析 + 无监督深度特征),强调可解释、不需大标注集。自建《中国民歌集成》语料:旋律 5000+ 首(>30 万音符)、带词 1400+ 首(>10 万字符)。**旋律音符 F1 0.951,歌词字符 F1 0.931**。[实测可靠](论文数据,未复现)。代码是否放出:未查到。另见专利 CN117197821A「一种 OCR 识别乐谱的方法与装置」。

### 3.2 开源项目

| 项目 | 干什么 | 方法 | License / 活跃度 |
|---|---|---|---|
| **lodebar2026/dolce(悦谱)** ★★ | 简谱+五线谱编辑/排版/播放/**离线 OMR**;简谱照片/截图/扫描 PDF→自家 123 格式(ABC 方言),五线谱图→MusicXML;读番茄简谱/.pu/.jps/.jpwabc/jianpu-ly/.jcx/ABC/MusicXML;出 MIDI(带歌词)/PDF/PNG/PPTX/MusicXML;浏览器 + Tauri 2 桌面;「图片不上传」;带 omr-cli.mjs 与歌本 PDF 切分 | PaddleOCR(Apache-2.0 模型)跑 onnxruntime-web + 版面启发 | **MIT**;66★,1595 commits,**2026-10-25 当天仍在提交**;无 TAB |
| Akane0721/OrpheusNet | 简谱图→MIDI(Flask web);四段管线:超分(SRCNN)→投影切分→UpNet/MiddleNet/DownNet/MetaNet 四 CNN→语法编码→music21;可经 MuseScore 转 staff | 经典 CV+CNN;自报清晰图 ~99% SA、模糊图+超分 98%(自报,未核) | **MIT**;40★,**仅 2 commits,无维护** |
| MAraragi/MusicalScoreRecognition | 简谱图→MIDI;带人工修正文本步 | 模板匹配 + KD-tree(纯 OpenCV/NumPy) | **无 license**;67★,7 commits,~2024-01 后无更新 |
| timecodeecho/jianpu-recognizer | 简谱图→MusicXML(music21),去水印 | OpenCV 几何(八度点/符梁/小节线)+ PaddleOCR(数字/拍号/调号) | **MIT**;4★,1 commit |
| Sylvia455/jianpu-recognizer | 「AI 简谱拍照识别」 | README 无模型细节(扣子 CLI 脚手架的 Next.js WIP) | 无 license;1★ |
| e-fity/jianpu-full / madderscientist/JianPuTrans / guhanyu051221/score_reader / ourhome-macro/sunoscribe | 简谱图→键位谱 / 移调 / 拍照识别 / 音频→简谱 | 各类,均玩具级 | 0-8★ |
| starpacker/music_translator | **反向**:五线谱 PDF→简谱 PDF(整页或原位贴行) | homr/Audiveris→MusicXML→music21→jianpu-ly/LilyPond;单旋律 | AGPL-3.0;2★,37 commits |

### 3.3 中文商业/社区

- **壹谱网 ziipoo.cn「易识谱」**[官方声称]:简谱图片→可编辑、可播放简谱的商业识别系统;易谱打谱软件商业授权 30 天 ¥99 / 365 天 ¥300(识别服务单价在 /buy,未逐页核)。**版式与谱全了最接近的中文商业识别,值得实测。**
- 知乎生态:推荐流以 PlayScore 2(简谱支持有限)、ABBYY 手工整理、作曲大师/EOP 简谱大师(重录入非识别)为主。搜索摘要出现「oGenMusic(优越者简谱)」但**独立信源未查到,存疑不作数**。
- B 站/博客系统性简谱识别实测:**未查到**。

### 3.4 NoteLite 点名查证(Lucas0623z/NoteLite)

Audiveris 的增强分叉(Java,JDK 21):保留 Audiveris 桌面编辑器 + 新增浏览器跟练模式(MIDI/麦克风实时评分,OpenSheetMusicDisplay 渲染,Pitchy 测音)。~1.1k★、168 forks、118 commits、活跃开发中(iOS/iPadOS/macOS 客户端 dev/test 阶段)。**License 混合:根 MIT,但 Audiveris 派生代码保留 AGPL-3.0-or-later,README 明说「不应当纯 MIT 用」**。只认五线谱,无简谱、无 TAB。对 UkeFlow 价值:产品形态参照(Audiveris 系识别+跟练闭环)。

---

## 4. 角度三:TAB 识别 2025-10 之后的新项目

- **LIU9293/guitar-tab-omr:无更新。** 3 个 commit 全部停在 2026-05-23(「Publish Guitar Tab OMR training artifacts」等),与昨日普查所见一致;license 仍未标注。
- **clark970417-eng/string-space** ★(0★,4 commits,2026-10 活跃):繁中界面、本地优先的吉他练习 web app(React/TS)。**TAB 位图识别在浏览器内 = Tesseract.js OCR + 谱面几何启发**(符杆/符梁/休止/附点/三连音至六连音/ties/反复),MusicXML(.musicxml/.mxl)导入,JPG/PNG/PDF(≤8 页)识别,chroma+子序列 DTW 音频对齐;Audiveris 5.11 只作可选 sidecar 管五线谱。**无 ukulele/4 弦;项目自身代码未标 license**(依赖 alphaTab MPL-2.0)。成熟度极早(0★4 commits)但带单测+Playwright e2e。**技术路线正是昨日 C 档的活样本。**
- 其余:「tablature recognition」检索只有 Ujexa/StringTabs(音频→tab,非图像)、arb7/tabrecognition(2020 课程作业);「ukulele tab」全 GitHub 79 仓库无一是识别/OCR;optical-music-recognition topic 按 updated 扫到的其余新仓全是 Audiveris/oemer 封装(PDF2Muse 20★、audiveris-py、lilyscan、Pdf2Score、staffreader 等)与五线谱实验仓。
- **结论:四弦/尤克里里 TAB 识别仍然为零,昨日结论维持。**

---

## 5. 角度四:Soundslice 扫描器现状

- **价格(官方 plans 页,[官方声称])**:Free $0(2 次扫描/月,单次 1 页 32 小节);**Plus $5/月 或 $50/年**(100 页/月,单次 25 页);Teacher $20/月;Licensing $100/月。昨日「月费金额待查」已结。
- **tab-only 关键缺陷坐实**(官方博客 2022-11-17「New: Support for importing tab-only music via PDF」):**tab-only 导入时节奏不识别,所有音符一律落为四分音符**(ML 尚不能从无符杆 TAB 读时值)。对以节奏为生命的弹唱谱是硬伤——即使音高全对,校对工作量依然大。**这条把 Soundslice 的预期价值进一步压低,但不影响「免费档跑一次样张」的决定。**
- 弦数:扫描页只写「检测 tablature,无论有无配套五线谱」,无 4 弦承诺;官方无限定字样也无官方确认。
- **四弦/尤克里里 TAB 扫描的第三方公开实测报告:未查到**(soundslice.com 站内 ukulele 命中全是商店曲集;Ukulele Underground 论坛只谈打谱软件,无扫描实测)。

---

## 6. 角度五:Dart/Flutter 侧 MusicXML 解析库

pub.dev「musicxml」检索快照(2026-10-26,共 72 结果):

| 包 | 干什么 | 版本/时间 | License | 备注 |
|---|---|---|---|---|
| **music_xml** | MusicXML 4.0 解析+序列化,xml/mxl 双支持;notes/chords/lyrics/ties/key/time/clef 全模型 | 2.10.0,2 个月前;verified publisher demen.org | BSD-3 | 15 likes、下载量很小;README 未提 string/fret,**TAB 元素解析未确认**(待读码) |
| **songbird_musicxml** | 读写 MusicXML 4.0 + .mxl,typed model | 0.1.1,42 天前 | 页面未核 | 早期 |
| **flutter_notemus** | Flutter 原生 CMN 排版引擎(SMuFL/Bravura、跨谱表符梁、圣咏),MusicXML/MEI/JSON/GABC 导入,MusicXML/MIDI 导出,MIDI 播放 | 2.8.1,48 天前 | Apache-2.0 | **TAB 只解析不渲染**(issue #45,README 自认早前 overclaim);无简谱;native audio 仅 Android |
| **crisp_notation_cli / crisp_notation_core** ★★ | 纯 Dart 格式枢纽:MusicXML/mxl、MEI、**kern**、MuseScore .mscx/.mscz、**Guitar Pro .gp3-.gp8/GPIF**、ABC、LilyPond、GABC、纯文本 tab 互转;SVG/PNG 渲染(**含 tablature**);**可跑 OMR**(FFI libcrispembed:Sheet Music Transformer / Polyphonic-TrOMR / Flova,HF 自动下模型);LilyPond/盲谱导出 | 0.13.0,**6 天前**;verified publisher crispstro.be | MIT | OMR 需原生库,其余纯 Dart;对 UkeFlow 是高价值参照(GP 导入 + tab 渲染的 Dart 实现) |
| verovio_flutter | Verovio FFI 渲染(Android/iOS/Web/WASM) | 0.3.3,3 个月前 | 页面未核 | 渲染向 |
| musicxml_score / fl_music_xml_parser | 早期解析器 | 14 个月 / 2 年未动 | — | 陈旧 |

结论:**解析选 music_xml 或 songbird_musicxml 即可满足「MusicXML 只做对外交换」的定位**;flutter_notemus 与 crisp_notation 列为将来「app 内渲染外部谱源」的读码候选。

---

## 7. 角度六:弦乐器指法求解开源实现

| 仓库 | 干什么 | 算法 | License / 星 / 活跃 |
|---|---|---|---|
| jgollub1/guitar_dp | 单声部 MIDI 旋律→指板路径(弦/品/指),Flask 演示 | 相邻音符对 DP,四指转移代价累加,代价函数开放定制(guitar_util.py) | **MIT**;6★,30 commits;明确不支持和弦/多声部 |
| kblcuk/chordcraft ★ | 和弦名↔指法双向转换 + 和弦进行转换优化(`chordcraft progression "Cmaj7 Am7 …"`);吉他/尤克里里/贝斯/曼陀林;--position/--capo | 文档提 beam search(替代贪心)、DP 列为计划;细节在 CLAUDE.md(未逐条核) | **AGPL-3.0**;1★,165 commits;Rust+WASM,web demo chordcraft.rocks |
| hyvyys/chord-fingering ★ | 和弦符号→所有可按压位(position 串、barre 检测、难度分);为 Chordline app 所写 | 半音数学匹配+穷举打分;**任意弦数任意调弦**(ukulele 走通用 findFingerings 路径) | **GPL-3.0**;21★;JS/npm |
| eliot-christon/optimal-musical-fingering | 和弦与整曲(MIDI 输入)指法优化,吉他/尤克里里/贝斯/班卓;web 前端+Python 后端 | 枚举+难度/易奏/工效打分(README 未写 DP/beam);过渡优化在路线图 | **Apache-2.0**;1★,192 commits,2026-09 活跃,早期可用 |
| zimolzak/ukulele | 尤克里里全指法枚举→和弦名(lotsachords.txt) | 暴力枚举+乐理反解 | **MIT**;15★,2016 年老仓 |

- **多声部指法分配(旋律+和弦同按、DP/beam search 全局最优)的成熟开源实现:未查到。** 学术侧:Bontempi et al. 2024《From MIDI to Rich Tablatures》(SMC 2024,arXiv 2407.09052,含首席吉他手指法与风格选择)——公开代码未查到;TART 2025(arXiv 2510.02597,音频→含指法 tab)同;RL-Chord(Tayjsl97/RL-Chord,TNNLS)是 RL 和弦进行非指法;经典 DP 文献(Radisavljevic & Driessen path difference learning;DiVA《An Algorithm for Optimal Guitar Fingering》)有文无码。
- 对 UkeFlow 参考序:hyvyys(轻、任意调弦)→ chordcraft(双向+进行优化,Rust 可 FFI,注意 AGPL)→ guitar_dp(单声部 DP 骨架);「melody+chord 多声部分配」仍需自研。

---

## 8. 引用清单

**VLM OMR**
- LEGATO 2:https://arxiv.org/abs/2607.05769 (html: https://arxiv.org/html/2607.05769v1)
- Youtu-Parsing-Omni:https://huggingface.co/tencent/Youtu-Parsing-Omni
- SSMR-Bench:https://arxiv.org/abs/2509.04059
- WildScore:https://arxiv.org/abs/2509.04744 ;数据 https://huggingface.co/datasets/GM77/WildScore ;代码 https://github.com/GaganVM/WildScore ;ACL https://aclanthology.org/2025.emnlp-main.853.pdf
- MuSP-Bench:https://www.alphaxiv.org/abs/2608.28212
- MuseBench / MuseAgent:https://openreview.net/forum?id=kDqH5KmRWR
- sheet-music-mcp:https://github.com/raulkivi/sheet-music-mcp
- 「Music I Care About」:https://arxiv.org/abs/2607.06015

**简谱识别**
- Bu et al. 简谱识别论文:https://arxiv.org/abs/2512.14758
- dolce(悦谱):https://github.com/lodebar2026/dolce
- OrpheusNet:https://github.com/Akane0721/OrpheusNet
- OrpheusNet-jianpu(fork,OCR-first):https://github.com/yymmm9/OrpheusNet-jianpu
- MAraragi/MusicalScoreRecognition:https://github.com/MAraragi/MusicalScoreRecognition
- timecodeecho/jianpu-recognizer:https://github.com/timecodeecho/jianpu-recognizer
- Sylvia455/jianpu-recognizer:https://github.com/Sylvia455/jianpu-recognizer
- starpacker/music_translator:https://github.com/starpacker/music_translator
- NoteLite:https://github.com/Lucas0623z/NoteLite
- 壹谱网易识谱:https://www.ziipoo.cn/ocr ;商店 https://www.ziipoo.cn
- 专利 CN117197821A:公开检索可见(细节未展开)

**TAB 新项目**
- LIU9293/guitar-tab-omr commits:https://github.com/LIU9293/guitar-tab-omr/commits/main
- string-space:https://github.com/clark970417-eng/string-space
- optical-music-recognition topic:https://github.com/topics/optical-music-recognition
- PDF2Muse:https://github.com/thedivergentai/PDF2Muse(名称以仓库实际为准)

**Soundslice**
- 扫描器页:https://www.soundslice.com/sheet-music-scanner/
- 价格页:https://www.soundslice.com/plans/
- tab-only 公告(全四分音符缺陷):https://www.soundslice.com/blog/229/new-support-for-importing-tab-only-music-via-pdf

**Dart/Flutter**
- music_xml:https://pub.dev/packages/music_xml
- songbird_musicxml:https://pub.dev/packages/songbird_musicxml
- flutter_notemus:https://pub.dev/packages/flutter_notemus
- crisp_notation_cli:https://pub.dev/packages/crisp_notation_cli ;crisp_notation_core:https://pub.dev/packages/crisp_notation_core
- verovio_flutter:https://pub.dev/packages/verovio_flutter

**指法求解**
- guitar_dp:https://github.com/jgollub1/guitar_dp
- chordcraft:https://github.com/kblcuk/chordcraft
- chord-fingering:https://github.com/hyvyys/chord-fingering
- optimal-musical-fingering:https://github.com/eliot-christon/optimal-musical-fingering
- zimolzak/ukulele:https://github.com/zimolzak/ukulele
- Bontempi et al. 2024:https://arxiv.org/abs/2407.09052 ;TART 2025:https://arxiv.org/pdf/2510.02597 ;DiVA 最优指法论文:https://www.diva-portal.org/smash/get/diva2:668903/fulltext01.pdf

---

## 9. 未查到 / 待验证汇总

- 简谱 × VLM 的系统性实测与准确率:**未查到**
- GPT-4o/Claude/Qwen-VL 直接读谱→MusicXML 的开源包裹仓库:**未查到**(GitHub「OMR GPT-4o」0 结果)
- 四弦/尤克里里 TAB 识别的新项目:**仍是零**
- Soundslice 四弦 TAB 第三方实测报告:**未查到**
- LEGATO 2 代码:承诺「发表后放出」,截至 2026-10-26 **未放出**
- Youtu-Parsing-Omni 自定义 license 条款细节(未逐条读,商用/嵌入前需过一遍)
- music_xml 对 MusicXML `<string>/<fret>` 等 TAB 元素的解析支持(README 未提,需读码验证)
- oGenMusic(优越者简谱)是否真实存在:仅单源搜索摘要,**未查到独立信源,不作数**
- 壹谱网「易识谱」识别服务单价(/buy 页未逐页核)
- 声明:本文所有准确率数字均为论文/模型卡/README 自报,本研究未做任何复现;昨日遗留的 PhotoScore 售价、SmartScore Guitar 版 4 弦覆盖、Rodan license 三项本次未重查,仍以昨日「待验证」为准。
