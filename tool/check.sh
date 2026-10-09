#!/usr/bin/env bash
# UkeFlow 检查入口。
#   tool/check.sh quick  → flutter analyze（pre-commit 用，~5s）
#   tool/check.sh full   → analyze + 全量测试（工单收尾用）
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
flutter analyze
[ "${1:-full}" = quick ] && exit 0
flutter test
