# 21: 备份导出/导入

**What to build:** 全量数据(自建曲谱、打卡、设置)导出为单个 JSON 文件(系统分享/保存),导入恢复;冲突策略取简单明确的一种(导入即覆盖,导出文件带版本号为将来格式演进留门)。

**Blocked by:** 14 练习路径+每日任务+打卡, 15 曲库页

**Status:** done

- [ ] 导出→清数据→导入→状态完整还原
- [ ] 导入坏文件给可读错误,不崩溃
- [ ] 导出文件含格式版本号
- [ ] 导出/导入为纯数据变换,有单元测试

## Comments

- 2026-10-17 (工单21 会话): **实现完毕,全库 619 测试绿、analyzer 零告警,提交 f89510f**。结构三层:core/backup/backup_doc 纯编解码(零 drift 依赖,version=1 格式契约,坏文件全族可读中文)→ data/backup_service(collectJson 事务内一致快照;restoreDoc 单事务「清四表+插回」,自建谱/图片谱原 id 保留=曲库入库序不变;restoreJson 串入口解析先行 fail-closed)→ features/settings/backup_flow 平台缝(picker/share 注入,同工单 18 image_pick_flow 模式)。设置页加「备份与恢复」卡:导出走系统分享面板(文件名 ukeflow-backup-日期.json),导入走系统文件选择器(不限类型,坏内容编解码层拦,不赌厂商 MIME 标注)+ 确认对话框(明示覆盖不可撤销)+ 恢复后 AppSettingsController.reload() 刷新行内值。新依赖 share_plus 13.3.1 / file_selector 1.1.0(权限姿态同工单 18:全程不申请存储权限)。
- 2026-10-17 (工单21 会话,双轴评审处置): Standards 轴零硬违规;Spec 轴四条可疑全部处置——①分享面板 dismissed 独立结果(BackupShareResult 三态),用户取消不再冒充「备份已生成」;②全空文档(如 `{"version":1}`)拒导——导入即覆盖语义下放行等于一键清库,真机导出至少有设置行,四段全空只可能是挑错文件;③导出四读包进事务(撕裂快照,结构上免费);④版本号非正数拒导。「合法空文档可还原」旧契约被评审推翻,对应测试改为守卫。Standards 软项:restoreJson 双入口报备保留(串版 fail-closed 契约的测试口);GLOSSARY 收「备份/导入即覆盖」、architecture.md 模块树补 core/backup 与 image_charts。**已知 partial**:票面「系统分享/保存」只走分享面板单通道,无 SAF 直存——真机验收时确认 OPPO 分享面板有「保存到文件」类目标,若没有再立小票补。
- 2026-10-17 (工单21 会话): **待真机验收清单**:①导出:设置页「导出备份」→ 分享面板出现 → 保存/发送得 JSON 文件;②导入回环:清 App 数据(或换机模拟)→「导入备份」选刚才的文件 → 确认覆盖 → 曲谱/打卡/设置全部还原,曲库顺序不变;③坏文件:选一个非备份文件 → 可读中文错误、不崩溃、数据不动;④用户取消分享 → 无「已生成」提示(静默);⑤含图片谱的数据导出导入后图片谱可看。验收过转 done。
- 2026-10-18 (机检记录,release 装机): 覆盖安装成功(10:14,数据保留,含今日打卡),冷启+logcat 干净(无 E/flutter/FATAL)。已验:①设置页备份卡渲染完整;②导出→系统分享面板拉起,文件名 `ukeflow-backup-2026-10-18.json` 正确上板;③面板 BACK 取消→无「已生成」假提示,静默回 App(dismissed 结果路径真机证实);④导入→系统文件选择器(documentsui)拉起,选择器取消返回 App 无恙。**机检受限**:ColorOS documentsui 网格卡对 adb 注入点按全盲(怪癖已记忆),坏文件/选文件的真手指操作并入用户验收(坏文件路径有 15 编解码单测+5 UI 测试锁底)。**发现待议**:OPPO 分享面板无「保存到文件」类目标(云盘/互传/邮件/蓝牙/自由收藏五选一)——评审预告的 partial 实锤,用户验收时选顺手的通道完成存取,若都不顺手再立 SAF 小票。
- 2026-10-18 (工单21 会话,补保存通道): 用户验收时证实 OPPO 分享面板无「保存到文件」目标,当场上补**「保存到本地」通道**——票面「系统分享/保存」的保存半边。Dart 侧 BackupFlow 第三注入缝 save + exportToLocal(独立 BackupSaveOutcome 族:Saved/Cancelled/Failed);生产走 MethodChannel ukeflow/save_file → MainActivity 的 ACTION_CREATE_DOCUMENT(SAF,免存储权限,同权限姿态;FlutterActivity 非 ComponentActivity,用经典 startActivityForResult/onActivityResult)。UI 备份卡改三钮:导出备份|保存到本地 一行,导入备份 独占整行(error 色强化危险感)。测试 625 绿(新增 flow 3 + UI 3);机检:保存框真机拉起、取消静默返回、logcat 干净。真机验收:保存框里选 Download → 文件落地 → 导入回环。
- 2026-10-18 (用户决策,导出通道定型): 用户定——**导出只留「保存到本地」一条通道,升格为「导出备份」;分享面板通道整个撤除**(OPPO 面板无「保存到文件」目标,分享路径对备份场景是绕路)。share_plus 依赖移除;BackupFlow 撤 share 缝与分享结果族,export() 即保存框落盘,文件名/失败文案不变;备份卡回到两钮(导出备份|导入备份,导入保持 error 色)。GLOSSARY 备份词条同步。620 测试绿;机检:导出钮→保存框拉起、建议文件名预填、取消返回、logcat 干净。用户真机验收清单不变:保存框选 Download 落盘→导入回环→坏文件。
- 2026-10-18 (用户真机验收): 导出(保存框落盘)→导入回环通过,转 done。
