#!/usr/bin/env bash
# Mac スリープ・画面ロック中もテストを継続（caffeinate + nohup 用の実体）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${PATH}:${HOME}/.maestro/bin"
export MAESTRO_DRIVER_STARTUP_TIMEOUT=240000
export MAESTRO_CLI_NO_ANALYTICS=1

RESULT_DIR="$ROOT/test-results/maestro"
mkdir -p "$RESULT_DIR"
LOG_FILE="$RESULT_DIR/background.log"

ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
DEVICE="${MAESTRO_DEVICE:-emulator-5554}"

echo "===== detached run start $(date) pid=$$ =====" >>"$LOG_FILE"

# detached 内でエミュレータ起動まで完結させる
if ! "$ADB" devices 2>/dev/null | grep -q "${DEVICE}[[:space:]]*device"; then
  echo "Launching emulator from detached runner..." >>"$LOG_FILE"
  flutter emulators --launch "${MAESTRO_AVD:-Medium_Phone_API_36.1}" >>"$LOG_FILE" 2>&1 || true
  "$ADB" wait-for-device >>"$LOG_FILE" 2>&1 || true
  for _ in $(seq 1 120); do
    boot="$("$ADB" -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    [[ "$boot" == "1" ]] && break
    sleep 2
  done
fi

bash "$ROOT/maestro/setup_maestro_env.sh" >>"$LOG_FILE" 2>&1

# エミュレータ画面オフを長めに（テスト中の adb 切断防止）
if "$ADB" devices 2>/dev/null | grep -q "${DEVICE}[[:space:]]*device"; then
  "$ADB" -s "$DEVICE" shell settings put system screen_off_timeout 2147483647 2>/dev/null || true
  "$ADB" -s "$DEVICE" shell svc power stayon true 2>/dev/null || true
fi

bash "$ROOT/maestro/run_all_tests.sh" >>"$LOG_FILE" 2>&1
code=$?

echo "===== detached run end $(date) exit=${code} =====" >>"$LOG_FILE"
exit "$code"
