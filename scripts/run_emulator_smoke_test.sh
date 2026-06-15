#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-}"
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"

wait_for_emulator() {
  for _ in $(seq 1 90); do
    if "$ADB" devices 2>/dev/null | grep -q "emulator-5554[[:space:]]*device"; then
      boot="$("$ADB" -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      if [[ "$boot" == "1" ]]; then
        echo "emulator-5554 ready"
        return 0
      fi
    fi
    sleep 2
  done
  return 1
}

if [[ -z "$DEVICE" ]]; then
  if ! "$ADB" devices 2>/dev/null | grep -q "emulator-5554[[:space:]]*device"; then
    echo "エミュレーターを起動します..."
    flutter emulators --launch Medium_Phone_API_36.1 &
    wait_for_emulator || { echo "エミュレーター起動タイムアウト"; exit 1; }
  fi
  DEVICE="emulator-5554"
fi

echo "Device: $DEVICE"
echo "=== エミュレータースモークテスト開始 ==="
flutter test integration_test/emulator_smoke_test.dart \
  -d "$DEVICE" \
  --dart-define=INTEGRATION_TEST_E2E=true \
  --dart-define=INTEGRATION_TEST_CAMERA_ROUTE=true
echo "=== すべて成功 ==="
