#!/usr/bin/env bash
# Play Console 登録用の値・SHA 指紋・ビルドコマンドを表示する。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PKG="com.auraface.kami_face_oracle"
VERSION_LINE="$(grep -E '^version:' pubspec.yaml | head -1 | tr -d ' ')"

echo "========================================"
echo " AuraFace — Play Console 準備情報"
echo "========================================"
echo ""
echo "パッケージ名:     $PKG"
echo "pubspec:          $VERSION_LINE"
echo ""
echo "--- 登録する商品 ID（完全一致）---"
echo "  定期購入: monthly_subscription_500  (¥500/月)"
echo "  消耗型:   normal_ticket_600         (¥600)"
echo "  消耗型:   urgent_ticket_10000       (¥10,000)"
echo ""
echo "詳細手順: docs/PLAY_CONSOLE_SETUP.md"
echo ""

print_sha() {
  local label="$1"
  local keystore="$2"
  local alias="${3:-androiddebugkey}"
  local storepass="${4:-android}"
  local keypass="${5:-android}"

  if [[ ! -f "$keystore" ]]; then
    echo "[$label] キーストアなし: $keystore"
    return
  fi
  echo "[$label] $keystore (alias=$alias)"
  keytool -list -v -keystore "$keystore" -alias "$alias" \
    -storepass "$storepass" -keypass "$keypass" 2>/dev/null \
    | grep -E 'SHA1:|SHA256:' || echo "  (keytool 失敗)"
  echo ""
}

echo "--- 証明書フィンガープリント（Play Console → アプリの整合性）---"
print_sha "Debug" "${ANDROID_DEBUG_KEYSTORE:-$HOME/.android/debug.keystore}"

RELEASE_KS="${RELEASE_KEYSTORE:-$ROOT/android/app/release.keystore}"
if [[ -f "$RELEASE_KS" ]]; then
  print_sha "Release" "$RELEASE_KS" "${RELEASE_KEY_ALIAS:-upload}" \
    "${RELEASE_STORE_PASSWORD:-}" "${RELEASE_KEY_PASSWORD:-}"
else
  echo "[Release] 未設定。例:"
  echo "  keytool -genkey -v -keystore android/app/release.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000"
  echo "  android/app/build.gradle.kts の signingConfigs.release を設定"
  echo ""
fi

echo "--- AAB ビルド（内部テスト用）---"
echo "  flutter build appbundle --release"
echo "  → build/app/outputs/bundle/release/app-release.aab"
echo ""
echo "--- サーバー（購入検証）---"
echo "  GOOGLE_PLAY_PACKAGE_NAME=$PKG"
echo "  GOOGLE_APPLICATION_CREDENTIALS=./secure/google-service-account.json"
echo "  Play Console: ユーザーと権限 → サービスアカウントを招待"
echo "  Cloud: Google Play Android Developer API を有効化"
echo ""
