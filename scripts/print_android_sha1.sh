#!/usr/bin/env bash
set -euo pipefail

echo "== Debug keystore SHA-1 =="
DEBUG_KEYSTORE="${HOME}/.android/debug.keystore"
if [[ ! -f "$DEBUG_KEYSTORE" ]]; then
  echo "NOT FOUND: $DEBUG_KEYSTORE"
  echo "Android Studio/Flutter で一度でも debug ビルドすると生成されます。"
  exit 1
fi

KEYTOOL_BIN="$(command -v keytool || true)"
AS_KEYTOOL="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
if [[ -x "$AS_KEYTOOL" ]]; then
  KEYTOOL_BIN="$AS_KEYTOOL"
fi

if [[ -z "$KEYTOOL_BIN" ]]; then
  echo "ERROR: keytool が見つかりません。"
  exit 1
fi

"$KEYTOOL_BIN" -list -v \
  -keystore "$DEBUG_KEYSTORE" \
  -alias androiddebugkey \
  -storepass android \
  -keypass android 2>&1 | awk '/SHA1:/{print}'

echo ""
echo "ヒント: Firebase Console → Project settings → Your apps (Android) → SHA certificate fingerprints に上の SHA-1 を追加 → google-services.json を再ダウンロード"

