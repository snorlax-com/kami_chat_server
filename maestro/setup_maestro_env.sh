#!/usr/bin/env bash
# Maestro + Android エミュレータ + debug APK の環境を整える
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Maestro は Java が必要（Android Studio 同梱 JBR を優先）
if [[ -z "${JAVA_HOME:-}" ]]; then
  if [[ -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
    export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  elif command -v /usr/libexec/java_home >/dev/null 2>&1; then
    export JAVA_HOME="$(/usr/libexec/java_home 2>/dev/null || true)"
  fi
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${PATH}:${HOME}/.maestro/bin"

ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
EMULATOR="${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator"
APP_ID="com.auraface.kami_face_oracle"
DEVICE="${MAESTRO_DEVICE:-emulator-5554}"
AVD_NAME="${MAESTRO_AVD:-Medium_Phone_API_36.1}"

install_maestro() {
  if command -v maestro >/dev/null 2>&1; then
    echo "Maestro: $(maestro --version 2>/dev/null || true)"
    return 0
  fi
  echo "Maestro をインストールします..."
  curl -Ls "https://get.maestro.mobile.dev" | bash
  export PATH="${PATH}:${HOME}/.maestro/bin"
  maestro --version
}

wait_for_emulator() {
  for _ in $(seq 1 180); do
    if "$ADB" devices 2>/dev/null | grep -q "${DEVICE}[[:space:]]*device"; then
      boot="$("$ADB" -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      if [[ "$boot" == "1" ]]; then
        echo "Emulator ready: ${DEVICE}"
        return 0
      fi
    fi
    sleep 2
  done
  echo "Emulator boot timeout: ${DEVICE}" >&2
  return 1
}

start_emulator_if_needed() {
  if "$ADB" devices 2>/dev/null | grep -q "${DEVICE}[[:space:]]*device"; then
    echo "Emulator already running: ${DEVICE}"
    return 0
  fi
  echo "Starting emulator: ${AVD_NAME}"
  flutter emulators --launch "$AVD_NAME" >/dev/null 2>&1 || {
    nohup "$EMULATOR" -avd "$AVD_NAME" -no-snapshot-save >/tmp/auraface-emulator.log 2>&1 &
  }
  wait_for_emulator
}

build_and_install_debug() {
  echo "debug APK をビルド・インストール（Maestro E2E カメラルート有効）..."
  rm -rf build/app/intermediates/flutter/debug 2>/dev/null || true
  flutter build apk --debug \
    --dart-define=INTEGRATION_TEST_CAMERA_ROUTE=true \
    --dart-define=INTEGRATION_TEST_E2E=true
  "$ADB" -s "$DEVICE" install -r build/app/outputs/flutter-apk/app-debug.apk
  echo "インストール完了: $APP_ID"
}

mkdir -p test-results

install_maestro
start_emulator_if_needed
build_and_install_debug

echo "Maestro environment ready: device=${DEVICE}"
