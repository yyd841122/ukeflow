# 31: 旧项目歌曲迁移(ukulele-demo / ukulele-glm → 内置曲库)

**What to build:** 把旧实验仓库里的歌曲收进 UkeFlow:①弹唱谱 19 首入库(assets/charts/*.pro + 目录登记);
②指弹谱 8 首入库(builtin_tab_charts.dart 常量 + 目录登记);③全部过既有校验(解析+白名单),测试守护。
来源:
- `github.com/yyd841122/ukulele-demo` flutter_app/lib/models.dart——4 首行内 ChordPro 弹唱 + 10 首指弹曲(槽位制 16 分粒度);
- `github.com/yyd841122/ukulele-glm` src/lib/features/practice/follow_score_page.dart——19 首 PracticeSong(歌词+和弦位+旋律音)。

**Blocked by:** 无

**Status:** done

- [x] 19 首弹唱谱 .pro 资产入库,builtin_charts_asset_test 全清单加载+契约绿
- [x] 8 首指弹曲 Dart 常量入库,builtin_tab_charts_test 数据面抽查绿(拍位自曲头累计、严格递增、1/16 网格)
- [x] 全库 flutter analyze 零告警、flutter test 全绿(673)

## Comments

- 2026-10-18 (本票会话): **迁移完成,待真机听感复核**。转换规则:①demo 弹唱(已是行内 ChordPro)按 Section→`{start_of_*}` 指令直转,emoji 剥离;②glm 弹唱(和弦按字符位悬挂)转行内 `[Chord]` 记号(切片拼接,补偿前插偏移;`带我飞飞过绝望` 和弦位越界一处,贴行尾处理)——glm 无段落结构,整谱自由段;③demo 指弹槽位制→TabNote:弦号 4−s(demo 0=G 起 ↔ UkeFlow 1=A 起),拍位 = 跨小节累计 tick/4(首版转换曾漏跨小节累计,每小节拍位归零,已修+测试锁死「严格递增」),时值 t(16 分粒度)全落在 0.25 倍数录入域;歌词按「字符数=音数」逐音缀字,对不上的小节作器乐音(英文音节不可靠,一概不缀)。
- 2026-10-18 (本票会话): **取舍记录**:①demo《奇异恩典》beatsPerChord=3(3/4),v1 谱面校验显式拒绝非 4/4,**未迁**——要迁需先立「拍号支持」票(demo 已有真机验证的按歌 beatsPerChord 方案,可作参照);②送别/友谊地久天长/茉莉花 glm 与 demo 双版本,取 demo 版(段落结构齐全),glm 版和弦编配略异(送别多 A7/E7)留在旧仓库备查;③demo 指弹小星星/欢乐颂与 UkeFlow 已有同名,**未迁**(UkeFlow 版经过八度审计修音);④glm 19 首各带单音旋律(PracticeNote,16–45 音/首),弹唱谱模型无旋律位,**未迁**——儿歌旋律大多已被指弹曲覆盖(小星星/欢乐颂/两只老虎/铃儿/伦敦桥/划小船),其余旋律数据留在 extracted JSON(转换中间产物,未入库)与旧仓库;⑤童年/隐形的翅膀为示意段落(首段摘句),歌词有版权,与内置 5 首同一立场(纯自用 sideload)——**日后若上架须按 ukulele-demo Step6 姿势清理版权内容**。
- 2026-10-18 (本票会话): 指弹音位**照搬 demo 数据未逐音对照原曲**(demo 自己的纪律也是「装机若个别音不准,用户反馈即改」);铃儿响叮当用到 ①7,绿袖子含 ④1/①1 变音,真机听感复核时重点过这两首。id 约定:与指弹曲同名的弹唱谱 id 加 `-strum` 后缀(小星星/欢乐颂),弹唱+指弹双形态的歌 tab id 加 `-tab`(两只老虎/铃儿响叮当)。
- 2026-10-18 (本票会话): **装机机检记录**(release 覆盖安装,PCAM00 无线 adb,数据原样)。构建 72.8MB,`adb install -r` Success;冷启 493ms(与工单 23 基线一致)。机检走查:启动落调音页正常 → 曲库页弹唱谱区可见迁移谱(送别/友谊地久天长/小星星/生日快乐/粉刷匠逐屏确认)→ 滚动到底,指弹区 8 首迁移卡全部渲染(两只老虎/玛丽/伦敦桥/铃儿响叮当/卡农/绿袖子/划小船/老麦克唐纳,「指弹 · 艺人 · BPM」副标题齐全)→ 图片谱区不受影响。logcat 零 E/flutter、零 FATAL。弹唱谱清单中段(摇篮曲~康康舞曲)未逐屏截到,由 24 首全清单加载测试(boot 拒载坏谱)兜底。待用户真机验收:弹唱谱听感(编配照搬旧仓库)、指弹重点过铃儿响叮当(①7)与绿袖子(④1/①1 变音)。
