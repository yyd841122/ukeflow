# CLAUDE.md

UkeFlow — 纯自用尤克里里弹唱学习 App(Flutter,Android 先行)。
架构见 `docs/architecture.md`,方向决策见 `docs/adr/0001~0006`。

## Agent skills

### Dev-only Python 工具

识谱/像素考古相关工作先看 `tools/`(score_workbench 体检/判别/版面切分、pdf_census):各自 README 有 venv 搭建与用法,pytest 在各自目录跑。

### Issue tracker

工单以本地 markdown 文件存放在 `.scratch/<feature>/` 下。See `docs/agents/issue-tracker.md`.

### Triage labels

使用五个默认 triage 角色标签(标签名 = 角色名)。See `docs/agents/triage-labels.md`.

### Domain docs

Single-context:根 `GLOSSARY.md` + `docs/adr/`。See `docs/agents/domain.md`.
