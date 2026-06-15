#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
  if ! flutter devices --machine 2>/dev/null | python3 -c "
import json,sys
for d in json.load(sys.stdin):
    if d.get('emulator') and d.get('platform')=='android':
        print(d['id']); break
" 2>/dev/null | grep -q .; then
    echo "エミュレーターを起動します..."
    flutter emulators --launch Medium_Phone_API_36.1 &
    for i in $(seq 1 60); do
      DEVICE="$(flutter devices --machine 2>/dev/null | python3 -c "
import json,sys
for d in json.load(sys.stdin):
    if d.get('emulator') and d.get('platform')=='android':
        print(d['id']); break
" 2>/dev/null || true)"
      [[ -n "$DEVICE" ]] && break
      sleep 2
    done
  else
    DEVICE="$(flutter devices --machine | python3 -c "
import json,sys
for d in json.load(sys.stdin):
    if d.get('emulator') and d.get('platform')=='android':
        print(d['id']); break
" 2>/dev/null || true)"
  fi
fi
if [[ -z "$DEVICE" ]]; then
  echo "Android エミュレーターが見つかりません。"
  exit 1
fi

echo "Device: $DEVICE"
flutter test integration_test/guest_login_back_cancel_test.dart \
  -d "$DEVICE" \
  --dart-define=INTEGRATION_TEST_E2E=true \
  --dart-define=INTEGRATION_TEST_CAMERA_ROUTE=true
