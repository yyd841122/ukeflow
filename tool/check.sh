#!/usr/bin/env bash
# UkeFlow 检查入口。
#   tool/check.sh quick  → fakeAsync 假绿检查 + flutter analyze（pre-commit 用，~5s）
#   tool/check.sh full   → quick + 全量测试（工单收尾用）
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
# fakeAsync 体必须同步：async 闭包在首个 await 停摆、后续断言不执行，
# 测试整组空转假绿（工单 10 评审教训，机械模式即拦）。
if grep -rInE 'fakeAsync\(\s*\([^)]*\)\s*async\b' test/; then
  echo '✗ fakeAsync 闭包不得是 async——await 后的断言不会执行（假绿）。'
  echo '  同步体；准备工作（如 warmup）放 fake zone 之外的真实 zone。'
  exit 1
fi
flutter analyze
[ "${1:-full}" = quick ] && exit 0
flutter test
