#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-emulator-5554}"

cd "$ROOT"

echo "==> Device: $DEVICE"
if ! flutter devices 2>/dev/null | grep -q "$DEVICE"; then
  echo "Device $DEVICE not found. Launch emulator or pass device id."
  exit 1
fi

echo "==> Integration test: urgent consultation first send"
flutter test integration_test/urgent_consultation_send_test.dart \
  -d "$DEVICE" \
  --dart-define=INTEGRATION_TEST_E2E=true \
  --dart-define=INTEGRATION_TEST_CONSULTATION=true

echo "==> Integration test: urgent from normal thread"
flutter test integration_test/urgent_consultation_from_normal_thread_test.dart \
  -d "$DEVICE" \
  --dart-define=INTEGRATION_TEST_E2E=true \
  --dart-define=INTEGRATION_TEST_CONSULTATION=true

echo "==> OK"
