#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE="$(flutter devices --machine | python3 -c "
import json,sys
for d in json.load(sys.stdin):
    if d.get('emulator') and d.get('platform')=='android':
        print(d['id']); break
" 2>/dev/null || true)"
fi
if [[ -z "$DEVICE" ]]; then
  echo "Android エミュレーターが見つかりません。先に flutter emulators --launch Medium_Phone_API_36.1"
  exit 1
fi

echo "Device: $DEVICE"
flutter test integration_test/tutorial_reveal_flow_test.dart \
  -d "$DEVICE" \
  --dart-define=INTEGRATION_TEST_E2E=true \
  --dart-define=INTEGRATION_TEST_CAMERA_ROUTE=true
