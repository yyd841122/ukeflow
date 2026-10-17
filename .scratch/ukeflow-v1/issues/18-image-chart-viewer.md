# 18: 图片谱只读查看器

**What to build:** 图片谱入库(内置资产/相册选图)+查看器页(photo_view 缩放平移);曲库中明确标识"图片谱·只读",不提供跟练入口(ADR-0002:图片谱不能跟练是 v1 物理边界)。

**Blocked by:** 15 曲库页

**Status:** ready-for-agent

- [ ] 图片谱可入库、浏览、缩放平移流畅
- [ ] 曲库标识"只读",点击不出现跟练入口
- [ ] 相册选图的权限流程正确(拒绝授权有引导态)

## Comments

- 2026-10-17 (本票会话): **落地,待真机验收**。①数据面:新 drift 表 image_charts(曲名+图片字节 BLOB,schemaVersion 4→5,幂等 createAll;字节入库让票 21 单 JSON 备份天然携带)+ImageChartsDao(add/getAll/watchAll,同 custom_charts 形)+读出流 imageChartsProvider,曲库 libraryProvider 并入第四区(票 15 预留位)。②内置资产:assets/image_charts/big-big-world.png——与内置弹唱谱同曲同内容的真实排版图片谱(tool/gen_builtin_image_chart.py 从 big-big-world.pro 生成,可复现),目录常量 builtinImageChartCatalog 入列;「同曲文本谱可跟练、图片谱只读」对照最直观。③选图+查看器:image_picker 走系统照片选择器(Android 13+ photo picker,更旧版本 ACTION_GET_CONTENT)按次授权,**App 全程不申请存储权限**(manifest 零新增)——验收③「权限流程正确」的落地即结构性不产生「拒绝授权」;失败路(选择器异常/坏图/落库失败)各有可读引导 snackbar,取消静默。入库前 validateImageBytes 引擎级解码验真(不信任输入,同自建谱读出闸姿态);查看器 photo_view(0.5×–8× 缩放平移,黑底),AppBar「只读」徽标+全页无跟练发起件;曲库卡片逐张「图片谱 · 只读」副标。TDD 六缝红→绿:入库验真/DAO(内存库+流)/选图流程(picker 注入:取消/坏图/好图/平台异常)/曲库区(只读标识/自动入列/点开无跟练)/查看器(渲染+坏图报错)/全链路 UI(打桩选图→命名对话框→落库→出卡)。测试 563→583,analyzer 零告警。
- 2026-10-17 (本票会话): **双轴评审(/code-review Standards+Spec)结果与处置**。Standards 零硬违规;修七处:PNG/文本测试素材三处手拼归 helpers、store() 中间人删除(UI 直调 DAO,同 text_import 形)、落库失败补 try/catch+可读引导、CustomImageChartEntry→UserImageChartEntry(cardKey custom-image-→user-image-,不借「自建谱(Custom Chart)」英文,GLOSSARY 补「用户图片谱」词条)、命名对话框控制器归 State 管(whenComplete 收早了,退场动画期 used-after-disposed,测试抓出)、注释漂移两处(三类→四类/「归工单 18」已落地)、viewer errorBuilder 补 debugPrint(缺陷可见姿态)。Spec 轴修两处:失败文案删「若弹出过权限拒绝请去系统设置」(与永不申请权限的结构事实自相矛盾,指引不可能之事)、ImagePicked.size 死载荷摘除。保留两项:sealed ImageChartEntry(与 CustomStrumEntry 同族惯例,零成本);相册图片同名重复静默保留(照片天然重名如 IMG_xxxx,无覆盖语义,与文本谱同名处置弹窗不同路,是有意差异)。
- 2026-10-17 (本票会话): **刻意范围**:①「缩放平移流畅」无自动化覆盖——手势体验归真机验收(下条机检),自动化只锁渲染就绪/只读徽标/无跟练入口/坏图可读报错;②测试环境三连坑已沉淀记忆(FakeAsync 区引擎级图片解码不出帧、图片缓存跨测试串场假绿、真平台通道挂死非异常——fakeasync-image-decode-and-channel-tests);③LibraryContent 常驻整块图片字节,v1 量级可容忍,多图大图时再议改按需读 BLOB。
