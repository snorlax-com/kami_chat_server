#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${PATH}:${HOME}/.maestro/bin"
export MAESTRO_DRIVER_STARTUP_TIMEOUT=240000
export MAESTRO_CLI_NO_ANALYTICS=1

DEVICE="${MAESTRO_DEVICE:-emulator-5554}"
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"

if ! "$ADB" devices 2>/dev/null | grep -q "${DEVICE}[[:space:]]*device"; then
  echo "Device not connected. Run setup_maestro_env.sh first." >&2
  exit 1
fi

FAILED_TESTS=(
  maestro/02_login.yaml
  maestro/03_free_trial.yaml
  maestro/04_store_subscription.yaml
  maestro/06_message_send.yaml
  maestro/07_logout_switch_account.yaml
  maestro/08_settings_account_delete.yaml
  maestro/09_chat_scroll.yaml
  maestro/10_error_handling.yaml
)

RESULT_DIR="$ROOT/test-results/maestro"
mkdir -p "$RESULT_DIR"

echo "Re-run failed flows on ${DEVICE}"
maestro --device "$DEVICE" test "${FAILED_TESTS[@]}" \
  --debug-output "$RESULT_DIR/debug-retry" \
  2>&1 | tee "$RESULT_DIR/retry-run.log"
