# 42: ScoreIR 源模型 + 校验器 + 物化器（金标准往返等值）

**Status:** done

**What to build:** 导入谱的源数据模型及其到既有组合结构的纯函数物化链（ADR-0009）。`lib/core/import/` 下：`score_ir.dart`（schemaVersion 1）、`score_ir_validator.dart`、`score_ir_materializer.dart`。

**IR 内容：** meter/tempoMap/keyMap/measures；声部×2（melody/accompaniment，逐音 beat/durationBeats/string/fret，midi 作冗余校验字段）、rests（beat/beats）、slides（fromBeat/toBeat）、tremolos、strums（kind/beat）、chordAnchors（beat/label/指形）；每事件可带证据（page/bbox/source/confidence，builtin 往返时为 null）；review 状态。拍位约定与仓库一致（double，0.5=八分）。

**校验规则：** 每声部每小节拍长闭合；弦品合法（openMidi+fret==midi，GCEA 高 G）；同弦同刻冲突；音域越界报错；不支持记号（hammer-on/pull-off 等）= 阻塞错误，禁止静默丢。

**物化：** ScoreIr → TabChart（melody）+ TabChart（accompaniment）+ ScoreSheetDef → 复用 `buildScorePlaybackChart`；tie 按既有约定落（旋律层延续音 lyric=null）。

**测试缝（总闸）：** 金标准往返等值——`aiNiBuShiLiangSanTianSolo`（484 音）+ 旋律层（168 音）→ 导出 IR → 物化 → 与原 Dart 常量**逐位相等**（音/拍位/歌词/休止/滑音/扫弦/和弦锚）。等值不过，43 以后全部不接。

**Non-goals:** drift、UI、编辑、导入页。

## Comments

### 2026-10-26 实现(Agent)

`lib/core/import/` 四件套落地,金标准总闸通过,全量 868 绿 + analyzer 净。

**文件:** `score_ir.dart`(模型+JSON,schemaVersion 1)、`score_ir_exporter.dart`(组合定义+双谱 → IR,金标准参考 JSON 也由它出)、`score_ir_validator.dart`(逐条阻塞错误)、`score_ir_materializer.dart`(校验 → 三源直落,坏源抛 ScoreIrMaterializationException)。测试 `test/core/import/`×4 + 夹具 `test/helpers/score_ir_fixtures.dart`,37 项。

**总闸结果:** 独奏 484 音 + 旋律 168 音 导出 → jsonEncode/jsonDecode 字符串域往返 → 物化 → 与原常量逐位相等(音/拍位/歌词/休止/滑音/扫弦/和弦锚/组合定义全字段),`buildScorePlaybackChart` 前后播放谱亦逐位相等。

**实现裁量(票面未定处,评审确认):**
- 票面 IR 字段清单未列 lyric,但总闸明写「歌词」逐位相等——`ScoreIrNote` 增可选 `lyric`(与 TabNote.lyric 1:1,物化零映射;识别端一期恒 null,不违 49 的歌词层 non-goal)。
- 声部休止与显示休止分列:声部休止是拍长闭合簿记(物化不消费),`rests` 顶层表 1:1 落 ScoreSheetDef.rests。
- 内置导出的时值推导:durationBeats = 距下一**不同拍** gap(同拍堆同一时值槽),小节末音收到小节线;音间静默由前一音时值表达(与 deriveNumberedNotes 同规)。
- tempoMap/keyMap 多条 = 阻塞错误(v1 物化单速单调号,放多条必静默丢,与「禁止静默丢」同纪律)。
- 同弦同刻按**声部内**判定:双轨模型跨声部同拍同弦是常态(金标准主轴拍 20 旋律②3 与伴奏 E 堆②4 并存)。
- 小节数 = floor(最晚拍/每小节拍数)+1:拍恰落小节线归入下一小节,不用 ceil(ceil 会丢压线末音)。

**两轴评审消化(code-review,2026-10-26):** 修 = Exception/Error 分域措辞(ScoreIrFormatException 是外部输入故障走 Exception,Broken 兜底要捕)、总闸改真 JSON 串域往返、压线末音丢弃、多条变速静默丢、同拍堆误判重叠(按起点分槽)、校验器同构函数收敛;不修 = ScoreIr copyWith(speculative,轻改走 JSON 源)。评审确认 lyric 裁量成立;校验器超出票面五条的从紧项(升序/骨架界/空白歌词等)系镜像运行时 ScoreSheetDef 字段契约,记录为约定。
