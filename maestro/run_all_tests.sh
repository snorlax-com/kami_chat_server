#!/usr/bin/env bash
# Maestro 全テスト一括実行（JUnit + デバッグ出力を test-results/ に保存）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${PATH}:${HOME}/.maestro/bin"
DEVICE="${MAESTRO_DEVICE:-emulator-5554}"
APP_ID="com.auraface.kami_face_oracle"
RESULT_DIR="$ROOT/test-results/maestro"
DEBUG_DIR="$RESULT_DIR/debug"
JUNIT_DIR="$RESULT_DIR/junit"
LOG_FILE="$RESULT_DIR/run.log"
SUMMARY_FILE="$RESULT_DIR/summary.txt"

mkdir -p "$RESULT_DIR" "$DEBUG_DIR" "$JUNIT_DIR"

if ! command -v maestro >/dev/null 2>&1; then
  echo "Maestro not installed. Run maestro/setup_maestro_env.sh first." >&2
  exit 1
fi

ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
if ! "$ADB" devices 2>/dev/null | grep -q "${DEVICE}[[:space:]]*device"; then
  echo "Device not connected: ${DEVICE}. Run maestro/setup_maestro_env.sh first." >&2
  exit 1
fi

export MAESTRO_DRIVER_STARTUP_TIMEOUT=240000
export MAESTRO_CLI_NO_ANALYTICS=1

TESTS=(
  maestro/00_launch.yaml
  maestro/01_tutorial.yaml
  maestro/02_login.yaml
  maestro/03_free_trial.yaml
  maestro/04_store_subscription.yaml
  maestro/05_ticket_purchase.yaml
  maestro/06_message_send.yaml
  maestro/07_logout_switch_account.yaml
  maestro/08_settings_account_delete.yaml
  maestro/09_chat_scroll.yaml
  maestro/10_error_handling.yaml
)

: >"$SUMMARY_FILE"
RUN_TMP="$RESULT_DIR/last-run.out"

echo "Maestro test suite start device=${DEVICE}" | tee -a "$LOG_FILE"
date | tee -a "$LOG_FILE"
echo "---- RUN all flows (single session) ----" | tee -a "$LOG_FILE"

set +e
maestro --device "$DEVICE" test "${TESTS[@]}" \
  --format junit \
  --output "$JUNIT_DIR/suite.xml" \
  --debug-output "$DEBUG_DIR" \
  2>&1 | tee -a "$LOG_FILE" | tee "$RUN_TMP"
code=${PIPESTATUS[0]}
set -e

FAILED=0
PASSED=0
for test_file in "${TESTS[@]}"; do
  name="$(basename "$test_file" .yaml)"
  if grep -q "\[Passed\] ${name}" "$RUN_TMP" 2>/dev/null; then
    echo "PASS $name" | tee -a "$SUMMARY_FILE"
    PASSED=$((PASSED + 1))
  elif grep -q "\[Failed\] ${name}" "$RUN_TMP" 2>/dev/null; then
    echo "FAIL $name debug=${DEBUG_DIR}" | tee -a "$SUMMARY_FILE"
    FAILED=$((FAILED + 1))
  else
    echo "FAIL $name (no result / suite exit=${code}) debug=${DEBUG_DIR}" | tee -a "$SUMMARY_FILE"
    FAILED=$((FAILED + 1))
  fi
done

echo "" | tee -a "$LOG_FILE"
echo "DONE PASS=${PASSED} FAIL=${FAILED} suite_exit=${code}" | tee -a "$LOG_FILE" "$SUMMARY_FILE"

if [[ "$FAILED" -gt 0 ]] || [[ "$code" -ne 0 ]]; then
  exit 1
fi

echo "All Maestro tests completed"
