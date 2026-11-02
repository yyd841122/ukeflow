# 读取候选限时筛选——换源 / 商业 OMR / dolce 适配(工单58,ADR-0010 退路链第一二环)

日期:2026-11-02 · 范围纪律(票面):筛选≠接入,每条时间盒,超时即记「超时+已知障碍」收;
壹谱网留后手不激活。

## 线① 换源限时检查(≤2h 盒,实际 ~35min):**四曲全线未命中**

任务:gs-aini(爱你不是两三天)+ 规划曲 BBW/MTICS/YOM 找**同编配**的
GP/MusicXML/高清结构化源。判定标准(票面):编配、调弦、段落一致才算命中;
换编配 = 换验收对象,不收。

### 平台核查矩阵

| 平台 | 形态 | 四曲结果 | 判定 |
|---|---|---|---|
| 谱全了 guistudy.com(编配源头) | 服务端 GP 数据,.ibe 强加密 | 官方产出仅「免费下载」渲染 PDF(已持有 gs-aini/gs-bbw);解密路工单37已裁死(绕技术保护不做) | 无合法结构化出口 |
| 弹琴吧 tan8.com(中文 GP 谱平台) | 站方播放器吃 GP | 爱你=仅钢琴谱 1 版(yuepu-104688);BBW=钢琴谱 10+ 版;MTICS/YOM=零结果;**四曲均无吉他/尤克里里谱** | 未命中 |
| Songsterr | GP 衍生交互 tab | BBW:Emilia s183894=单轨 Acoustic Guitar(steel) 原曲转录;MTICS:Leo Sayer 吉他转录 ×6;YOM:Carpenters/Kishibe(知名改编)/Sungha Jung 吉他指弹;爱你:查无(中文流行不收录) | 均非同编配 |
| Ultimate Guitar | 文本和弦谱+Official GP(付费 app 内) | BBW 有 ukulele **弹唱和弦谱**(C/G/F);其余同为弹唱和弦 | 非结构化非同编配 |
| MuseScore | 社区乐谱(MusicXML 可导) | 四曲仅钢琴/吉他/合奏改编;无尤克里里、无同编配 | 未命中 |
| 彼岸吉他 jitatang.com | 中文 GP 档案 | TLS 连接失败(HTTP 000);即便可达,吉他档案编配≠谱全了尤克里里编配 | 不构成候选 |
| 弹唱图片站(ukuleleba/白熊 the-x/91谱) | 图片/文本弹唱谱 | 爱你不是两三天有多版弹唱谱(艺艺萌/白熊等) | 非结构化非同编配 |

### 结构性结论

谱全了的编配是站方私有资产(编谱人小理/Louise 等),无任何外发 GP/MusicXML
渠道;GP/MusicXML 生态对这四曲只存在两种东西——**原曲转录**(吉他,编配不同)
与**弹唱和弦文本**(非结构化)。「同编配结构化源」这个退路环在事实层面不存在,
不是「还没找到」。MTICS/YOM 的权威源路径不变:用户从谱全了打印渲染 PDF
(uomJwTue C调 capo10 / uopjBeT0 D调,工单37 已定位)。

**含义:退路链第一环落空 → 升第二环 = 商业 TAB 引擎(本报告线②)。**

---

## 线② PhotoScore / SmartScore 文档核:**可行值得试用实测,关键能力未文档化**

两家对「四弦 TAB + MusicXML 导出」均有官方声称,但**「杆底符杠系统」
(谱全了 TAB 行下方的节奏梁——节奏所在)的读法两家都没文档化**;且谱全了
版式是「和弦图+TAB+简谱+歌词」四层、TAB 行无符头,TAB 系统与标准记谱
不同页呈现——这恰是试用实测要回答的问题(票面设计如此)。

| 项 | PhotoScore & NotateMe Ultimate **2020** | SmartScore 64(Neusift/Musitek) |
|---|---|---|
| TAB 声称 | **「reads 4- and 6-string guitar tab」**(官方页明写 4 弦;Lite 版仅 6 弦) | 「TAB and Percussion Recognition / Editing」仅 Pro/Songbook/**Guitar** 版;Guitar 版限 2 声部/系统 |
| 输入 | 直开 PDF(官方页明写) | 直开 PDF/TIFF(在线帮助) |
| 导出 | MusicXML / MIDI(官方页明写) | MusicXML / MIDI / ENF / PDF / MP3 |
| 节奏 | 读 128 分音符、附点、连音(对**记谱**;TAB 杆底符杠未提) | 更新日志有「beamed groupings 识别改进」(对记谱;TAB 杆底未提) |
| 试用 | Ultimate **2020 demo** 安装包公开下载(neuratron.com/downloads.asp → downloads2.asp);限制未文档化,装后自见 | Demo 公开下载,**30 天**,Windows 装后不可重置(FAQ);论坛报 trial Guitar 版有 MusicXML 导入异常(导出未见限制报告) |
| 产品状态 | 官网最后改于 2019-12,产品停在 2020 版——老但在售在下载 | SmartScore 64 现行在售 |

### 用户操作单(可行,样张=gs-aini p0)

1. 下载装 PhotoScore Ultimate 2020 demo(neuratron.com/downloads.asp);
   SmartScore 64 可作第二意见(注意 30 天窗与不可重置,先装 PhotoScore)。
2. 打开 `~/ukeflow-sources/gs-aini.pdf`(直开 PDF;或先由 agent 供单页 PNG)。
3. 认 Read 前勾「Read Scans as Printed」→ Read。
4. 逐项记录(专测目标=杆底符杠):
   a. TAB 四线系统**是否被识别为 TAB**(还是被当成五线谱垃圾);
   b. **杆底符杠的时值是否落到音上**(前奏小节2卷弦=八分、小节4三连音、
      主歌八分堆——对表见工单56 评测集 intro 段);
   c. × 记号与品位数字是否区分;
   d. 和弦图/简谱行/歌词行的处置(识别/忽略/乱读);
   e. 导出 MusicXML,把文件交给 agent 走 56 评分器管线(归一→eval-joint)。
5. 判定归还:若 a/b 双过 → 值得购入走导出管线(须 ADR 层新导入决策,
   票面纪律);若 a 过 b 不过 → 只有音位没有节奏,退路链价值减半;
   若 a 不过 → 商业 OMR 环落空,升「混合读取+校对」环。

---

## 线③ dolce 适配验证(0.8.6 整页实测):**旋律层引擎不可当,高价值互证源成立**

10-27 POC 结论承前:人声段简谱读得极好,但无坐标/无拍位/裁条喂入塌;
本线把整页喂入模式 + 非简谱区抑制 + 事件回映射跑通并量化。

**装机**:dolce 原 /tmp 装机(0.8.5)已被清;新 clone 0.8.6,用户放行后
`ONNXRUNTIME_NODE_INSTALL=skip npm install + npm run build:cli` 装机,
离线推理整页 ~1.7s/页(node scripts/omr-cli.mjs,-f 123)。

### 口径修正(本线实质发现,先于运行确立)

1. **「56 评分器复评」对 dolce 的可行形式**:工单56 冻结评测集是 **TAB 层**
   (324 事件中 digit 记号仅 **7** 个,全在 intro;主歌/副歌在 TAB 里是 × 展开,
   旋律只在简谱行)。简谱引擎与该真值无交叠,直接复评是空转。可行形式 =
   **同一配对机制(score_layer + τ=1/32)× App 纯旋律真值**(dump_melody_truth,
   168 音,用户真机听验收过的参照级真值;非冻结闸,报告须标注)。
2. **连线口径**:App 真值把同音连线的延音尾也存成独立音(@beat 无词音);
   dolce 候选默认**照读不并**(连线组内 token 各成一击、拍位照排)与真值
   1:1;`tie_merge=True` 备音乐攻击口径。
3. **音高映射**:App 纯旋律版 = 印张八度点减一 + E→C 平移(工单37 台账),
   故 `midi = C大调度数基音 + 12×(点数−低音点数−1)`;印张调号(K:1=E)不进映射
   (度数是相对量)。
4. **回映射 = 音序对齐**(非 bbox):dolce 输出行序=阅读序,与版面切分
   (工单48 layout)的简谱带序列按序对齐,给每行「系统/小节段」出处;
   对不齐(行数不等)如实报,不伪造坐标——证据链契约不可满足是 49 判其
   不能作识别引擎的根因,本适配不假装解决,只服务「互证源」用法。

### 实测结果(gs-aini 三整页,0.8.6,-f 123)

**抑制/回映射(非简谱区抑制全对,零误杀)**:p0 11 行→存活 2 行(恰为
sys1/sys2 的简谱行,9 行 TAB/和弦垃圾全部判除,真简谱行零误杀);p1 9 行→
存活 3 行(带 w: 歌词行——0.8.6 整页对有词系统照出歌词,10-27 POC 的
`w:` 形态在);p2 7 行→存活 3 行。判据 = X 主导≥50% 或 小节闭合<50% 且
无词,全部计数入报告。

**量化复评(56 配对机制 × App 纯旋律真值 168 音,τ=1/32,照读不并口径)**:

| 页 | 覆盖(印张小节) | 真值音 | 候选 | P | R | **F1** | 对齐方式 |
|---|---|---|---|---|---|---|---|
| p0 | b6-13(主歌一前半) | 57 | 57 | 0.842 | 0.842 | **0.842** | 结构枚举**唯一解**(L5 有 `|:`=主歌起点钉死;系统 5/4/4 小节) |
| p1 | b14-24(主歌一后半+副歌前半) | 86 | 87 | 0.851 | 0.860 | **0.856** | 印张灰字锚显式给(14,18,22)——变拍区布局累计号≠印张号,结构枚举无解 |
| p2 | b25-27+(副歌尾) | 25 | — | — | — | 未计分 | 已知障碍:简谱行被 dolce 跨行续刀(L4 行首 `6_)` 接上行未闭连线)+ 变拍,保序赋值无解,照实报 |

**失败模式定案(10-27 POC 模式3 定量)**:143 真值音中 ~18 音受染
(≈12.6%),**全部是八度点 ±1 翻转**——p0 b8 印张 `1''`(笔=C5)读成
`1'`、`7'`(熟=B4)读成 `7_`(点数少读一);p0 b12 `3' 4'`(E4/F4)读成
`3'' 4''`(E5/F5,点数多读一);p1 同型(牵 D5→D4、是/朋/什/没/有/爱
G4/E4→G5/E5)。**度数、节奏、拍位(τ=1/32 内)几乎全对**——错音不是
读错音,是读错点。另 b8 一处 0.25 拍微移(柔 G4@3.5 读成 @3.75)。

**互证价值实证**:主歌一、二段(b6-9 与 b10-13)同旋律不同词,L10 曾被
误配到 b14-17(结构性歧义)——靠逐拍对照钉回 b10-13;最终 p0 结构解唯一
后无歧义。这段曲折本身就是互证源用法的操作说明:**结构锚定 + 内容核对
双闸**,单靠任何一边都会错位。

### 判定(回答票面问题)

- **作旋律层引擎:不可。** 三条硬伤不变:①无坐标无证据链(49 契约不满足,
  本适配不伪造 bbox);②无拍位骨架输出(拍位靠 App 侧小节累加重建,变拍区
  即失锚);③八度点 ±1 不稳 ≈12.6%,直接落指必错八度,须逐音人工校点。
- **作互证源:成立且高价值。** 度数/节奏/拍位读出质量高(F1 0.84-0.86 且
  失配集中于单一可解释模式),整页模式无裁条塌(10-27 模式1 在 0.8.6 整页
  喂入下未复现),抑制零误杀;与自研草稿/56 候选逐音 diff 的分歧位即校对
  热点,喂工单51 校对台的对照模式。副歌高置段(印张双点区)在 p1 内同样
  可读,无「高置段塌」迹象。
- **对晋级线的关系**:0.84-0.86 < 0.90,但口径不同(旋律真值=参照级,
  ADR 晋级线管 TAB 联合事件)——dolce 不构成 TAB 读取端的候选,本线结论
  不改变退路链走向(线①已证换源落空,升线②商业 OMR)。

### 落地物

- `tools/score_workbench/score_workbench/dolce_poc.py`:123 方言解析
  (语义自 src/abcfamily/dialect123.ts)、垃圾行抑制(计数不静默)、攻击
  事件收集(照读不并/`tie_merge` 双口径)、`melody_score`(56 配对×旋律层)、
  `candidate_assignments`(保序结构枚举,歧义披露)+ `run_eval` 编排。
- CLI:`$PY -m score_workbench.cli dolce-eval <123> --layout <json>
  --score-page 0 --truth <melody-gt> --window 6-13 [--start-bars 14,18,22]`。
- 原始产物(仓库外):`~/ukeflow-sources/dolce-58/page{0,1,2}.123`。
- 真值:`dart run tools/dump_melody_truth.dart > /tmp/gs-aini-melody-gt.json`
  (168 音,melodyAlignBeats=20)。
- pytest 218→**230**(+12:解析/时长/连线双口径/抑制/小节号/音高/复评/对齐)。

## 复现

线①②:本报告平台矩阵逐行可复现(URL 在文内);线③:

```sh
cd /tmp/dolce && ONNXRUNTIME_NODE_INSTALL=skip npm install && npm run build:cli
for p in 0 1 2; do node scripts/omr-cli.mjs \
  ~/ukeflow-sources/vlm-poc-57/page$p.png -f 123 -o ~/ukeflow-sources/dolce-58/page$p.123; done
cd tools/score_workbench
PY=.venv/bin/python
dart run tools/dump_melody_truth.dart > /tmp/gs-aini-melody-gt.json   # 仓库根
$PY -m score_workbench.cli dolce-eval ~/ukeflow-sources/dolce-58/page0.123 \
    --layout ~/ukeflow-sources/vlm-poc-57/layout/layout.json --score-page 0 \
    --truth /tmp/gs-aini-melody-gt.json --window 6-13
$PY -m score_workbench.cli dolce-eval ~/ukeflow-sources/dolce-58/page1.123 \
    --layout ~/ukeflow-sources/vlm-poc-57/layout/layout.json --score-page 1 \
    --truth /tmp/gs-aini-melody-gt.json --window 14-24 --start-bars 14,18,22
```
