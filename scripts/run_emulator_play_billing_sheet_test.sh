#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-emulator-5554}"

cd "$ROOT"

echo "==> Device: $DEVICE"
adb -s "$DEVICE" wait-for-device

echo "==> Clear logcat"
adb -s "$DEVICE" logcat -c

echo "==> Integration test: Play billing sheet (no sideload test dialog)"
flutter test integration_test/store_play_billing_sheet_test.dart \
  -d "$DEVICE" \
  --dart-define=INTEGRATION_TEST_E2E=true \
  --dart-define=INTEGRATION_TEST_FORCE_PLAY_BILLING=true

echo ""
echo "==> Logcat: billing / Play UI signals"
LOG="$(adb -s "$DEVICE" logcat -d 2>/dev/null || true)"

echo "$LOG" | grep -E '\[BILLING|\[PlayInstallService\]|launchBillingFlow|ProxyBillingActivity|Finsky|BillingClient' | tail -40 || true

PLAY_LAUNCHED=false
if echo "$LOG" | grep -q 'launchBillingFlow.*started=true'; then
  PLAY_LAUNCHED=true
  echo ""
  echo "OK: launchBillingFlow started=true を検出"
fi

UI_HINT=false
if echo "$LOG" | grep -qiE 'ProxyBillingActivity|com\.android\.billingclient|Finsky.*billing'; then
  UI_HINT=true
  echo "OK: Play 課金 UI 関連の logcat を検出"
fi

adb -s "$DEVICE" shell uiautomator dump /sdcard/window_dump.xml >/dev/null 2>&1 || true
DUMP="$(adb -s "$DEVICE" shell cat /sdcard/window_dump.xml 2>/dev/null || true)"
if echo "$DUMP" | grep -qiE 'Google Play|play\.google|購入|定期購入|Subscribe|One-time'; then
  UI_HINT=true
  echo "OK: uiautomator に Play 購入画面らしき文言を検出"
  echo "$DUMP" | grep -oiE '.{0,40}(Google Play|購入|Subscribe|定期購入).{0,40}' | head -5 || true
fi

if ! $PLAY_LAUNCHED; then
  echo ""
  echo "WARN: launchBillingFlow started=true が見つかりません（Billing 未接続・商品未取得の可能性）"
  echo "      Play Console 内部テスト参加・エミュの Google ログインを確認してください"
fi

if ! $UI_HINT && $PLAY_LAUNCHED; then
  echo "NOTE: 課金フローは起動したが UI 文言は logcat/uiautomator で未検出（手動で画面確認推奨）"
fi

echo ""
echo "==> Done"
