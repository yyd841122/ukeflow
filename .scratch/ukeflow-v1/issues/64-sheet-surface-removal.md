# 64: 曲谱页/识谱源导入面拆除 + imported_solo 表下线

**What to build:** 按 ADR-0013 拆除识别线的 App 消费面:ScoreSheetPage、
score_sheet_view、faithful_score_view、play_hint_bar、dual_track_timeline、
score_source_import_flow/page、score_ir_materializer/exporter、
imported_solo_charts(DAO+表,schema 迁移下线)、LibraryCategory.solo 位。
**保留**:score_ir 类型/score_ir_editor/score_sheet_layout/deriveNumberedNotes
/note_tune_panel(指弹轻改活线共用,已由合成夹具保测试)。

**Blocked by:** None

**Status:** ready-for-agent

- [ ] 拆除前依赖复扫(以本票为准,勿信过时 grep)
- [ ] 曲谱页消费面 + 导入流删除,独奏谱类型位撤出曲库目录
- [ ] imported_solo 表 schema 迁移下线(旧备份含该表行时按未知忽略)
- [ ] 全量测试绿 + 真机曲库四类目正常

## Comments

- 2026-11-14: 建票(ADR-0013 决策3)。耦合备忘:score_ir 类型与
  score_sheet_layout 被指弹轻改共用不可删;play_hint_bar/dual_track 仅
  曲谱页消费可删;备份服务无 imported_solo 耦合(已核 2026-11-14)。
- 2026-11-14 机检备注:真机 imported_solo 表有 **1 条真实数据**
  (tiankongzhicheng-vector.scoreir,矢量谱时代的天空之城识谱源,OPPO
  PCAM00 独奏谱列表实证)。拆表 = 该行随库下线;它是已搁置矢量线的实验
  数据,与流水谱天空之城重复,预期可弃——执行前与用户确认一句即可。
