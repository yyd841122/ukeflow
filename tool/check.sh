#!/usr/bin/env bash
# UkeFlow 检查入口。
#   tool/check.sh quick  → fakeAsync 假绿检查 + flutter analyze（pre-commit 用，~5s）
#   tool/check.sh full   → quick + 全量测试 + score_workbench pytest（工单收尾用）
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# fakeAsync 体必须同步：async 闭包在首个 await 停摆、后续断言不执行，
# 测试整组空转假绿（工单 10 评审教训，机械模式即拦）。
if grep -rInE 'fakeAsync\(\s*\([^)]*\)\s*async\b' test/; then
  echo '✗ fakeAsync 闭包不得是 async——await 后的断言不会执行（假绿）。'
  echo '  同步体；准备工作（如 warmup）放 fake zone 之外的真实 zone。'
  exit 1
fi
# 工单49 retro:大二进制不入库(26MB onnx 曾因 .gitignore 写错被误暂存)。
bad=$(git diff --cached --name-only -z 2>/dev/null | xargs -0 -r stat -c '%s' 2>/dev/null \
  | awk '$1 > 5242880 {c++} END {print c+0}')
if [ "$bad" -gt 0 ]; then
  echo "✗ 暂存含 $bad 个 >5MB 文件(二进制不入库,进 .gitignore):"
  git diff --cached --name-only | head -5
  exit 1
fi
flutter analyze
if [ "${1:-full}" = quick ]; then exit 0; fi
flutter test
# Python 工具侧（工单 48 retro：整票交付全在 tools/，commit 时零 guardrail）。
# venv 在 /tmp 易失，不在则跳过并提示重建（README 两行）；语料测试自身 skipif。
if [ -x /tmp/swwenv/bin/python ]; then
  (cd tools/score_workbench && /tmp/swwenv/bin/python -m pytest tests/ -q)
else
  echo '— score_workbench venv 不在(/tmp/swwenv),跳过 pytest;要跑按其 README 重建'
fi
# 工单49 retro:真值 fixture 漂移闸(Dart 常量 ↔ pytest fixture 单源,
# 陈了会让对账闸以「莫名 diff」报错而非「fixture 过期」)。
dart run tools/dump_melody_truth.dart > /tmp/ukeflow-gt-check.json
python3 - <<'PYEOF'
import json
gt = json.load(open('/tmp/ukeflow-gt-check.json'))
fx = json.load(open('tools/score_workbench/tests/fixtures/gs-aini-melody-gt.json'))
fx.pop('_comment', None)
if gt != fx:
    print('✗ 真值 fixture 与 Dart 常量漂移:重跑 dart run tools/dump_melody_truth.dart')
    print('  > tools/score_workbench/tests/fixtures/gs-aini-melody-gt.json(补 _comment 键)')
    raise SystemExit(1)
PYEOF
# 工单50 retro:配对守卫——tests/fixtures/*-gt.json 每个真值 fixture 必须
# 被本文件引用(接了漂移闸);「新增真值源忘接闸」直接红在这里。
for fx in tools/score_workbench/tests/fixtures/*-gt.json; do
  grep -q "$(basename "$fx")" "$0" || {
    echo "✗ 真值 fixture 未接漂移闸:$fx(check.sh 无引用;新真值源同 commit 接闸)"
    exit 1
  }
done
# 工单50 retro:同款漂移闸接 TAB 真值(工单49 闸只护旋律,tab fixture 陈了
# 会让 test_canary_real_vs_truth_mechanism 以莫名 diff 报错)。
dart run tools/dump_tab_truth.dart > /tmp/ukeflow-tab-gt-check.json
python3 - <<'PYEOF'
import json
gt = json.load(open('/tmp/ukeflow-tab-gt-check.json'))
fx = json.load(open('tools/score_workbench/tests/fixtures/gs-aini-tab-gt.json'))
if gt != fx:
    print('✗ TAB 真值 fixture 与 Dart 常量漂移:重跑 dart run tools/dump_tab_truth.dart')
    print('  > tools/score_workbench/tests/fixtures/gs-aini-tab-gt.json')
    raise SystemExit(1)
PYEOF
