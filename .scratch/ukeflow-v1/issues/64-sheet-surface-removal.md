# 64: 曲谱页/识谱源导入面拆除 + imported_solo 表下线

**What to build:** 按 ADR-0013 拆除识别线的 App 消费面:ScoreSheetPage、
score_sheet_view、faithful_score_view、play_hint_bar、dual_track_timeline、
score_source_import_flow/page、score_ir_materializer/exporter、
imported_solo_charts(DAO+表,schema 迁移下线)、LibraryCategory.solo 位。
**保留**:score_ir 类型/score_ir_editor/score_sheet_layout/deriveNumberedNotes
/note_tune_panel(指弹轻改活线共用,已由合成夹具保测试)。

**Blocked by:** None

**Status:** done

- [x] 拆除前依赖复扫(以本票为准,勿信过时 grep)
- [x] 曲谱页消费面 + 导入流删除,独奏谱类型位撤出曲库目录
- [x] imported_solo 表 schema 迁移下线(旧备份含该表行时按未知忽略)
- [x] 全量测试绿 + 真机曲库类目正常

## Comments

- 2026-11-14: 建票(ADR-0013 决策3)。耦合备忘:score_ir 类型与
  score_sheet_layout 被指弹轻改共用不可删;play_hint_bar/dual_track 仅
  曲谱页消费可删;备份服务无 imported_solo 耦合(已核 2026-11-14)。
- 2026-11-14 机检备注:真机 imported_solo 表有 **1 条真实数据**
  (tiankongzhicheng-vector.scoreir,矢量谱时代的天空之城识谱源,OPPO
  PCAM00 独奏谱列表实证)。拆表 = 该行随库下线;它是已搁置矢量线的实验
  数据,与流水谱天空之城重复,预期可弃——执行前与用户确认一句即可。
- 2026-11-14: 执行完毕翻 done。范围比票面更大:轻改全链(score_ir/
  editor/validator/排版/点选缝/note_tune 面板/edit session)一并移除——
  依赖复扫证实唯一消费方是导入独奏,内置指弹谱轻改会话恒空。DB schema
  v10 下线两终止线表(image_charts v9/imported_solo_charts v10),迁移
  测试重写为 v8→v10 双 drop 语义。真机库 1 条天空之城矢量导入行随表下线
  (用户「独奏谱也删除了」即确认)。指弹跟练零改动(仅拆死接线)。曲库
  目录两类:弹唱谱/指弹谱。1093→935 全绿(删的测试随消费方消亡)。
