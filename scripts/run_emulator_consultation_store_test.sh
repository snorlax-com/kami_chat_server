#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-emulator-5554}"

cd "$ROOT"

echo "==> Device: $DEVICE"
adb -s "$DEVICE" wait-for-device

echo "==> Integration test: consultation store redirect"
flutter test integration_test/consultation_store_redirect_test.dart \
  -d "$DEVICE" \
  --dart-define=INTEGRATION_TEST_E2E=true

echo "==> OK"
