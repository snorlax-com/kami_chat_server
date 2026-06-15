#!/usr/bin/env bash
# 全11本の Maestro テストが完走するまで自動リトライ（インフラ切断時も再開）
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# スリープ抑止で自身を再実行
if [[ -z "${MAESTRO_CAFFEINATED:-}" ]]; then
  export MAESTRO_CAFFEINATED=1
  exec caffeinate -dims env MAESTRO_CAFFEINATED=1 bash "$0" "$@"
fi

if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${PATH}:${HOME}/.maestro/bin"
export MAESTRO_DRIVER_STARTUP_TIMEOUT=240000
export MAESTRO_CLI_NO_ANALYTICS=1

RESULT_DIR="$ROOT/test-results/maestro"
WATCH_LOG="$RESULT_DIR/watchdog.log"
SUMMARY_FILE="$RESULT_DIR/summary.txt"
LATEST_LOG="$RESULT_DIR/latest-run.log"
DONE_FLAG="$RESULT_DIR/suite.completed"
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
DEVICE="${MAESTRO_DEVICE:-emulator-5554}"
AVD="${MAESTRO_AVD:-Medium_Phone_API_36.1}"
MAX_ATTEMPTS="${MAESTRO_MAX_ATTEMPTS:-30}"
RETRY_SLEEP_SEC="${MAESTRO_RETRY_SLEEP_SEC:-45}"

mkdir -p "$RESULT_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$WATCH_LOG"
}

ensure_emulator() {
  if "$ADB" devices 2>/dev/null | grep -q "${DEVICE}[[:space:]]*device"; then
    boot="$("$ADB" -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [[ "$boot" == "1" ]]; then
      log "Emulator ready: ${DEVICE}"
      return 0
    fi
  fi
  log "Starting emulator: ${AVD}"
  flutter emulators --launch "$AVD" >>"$WATCH_LOG" 2>&1 || true
  "$ADB" wait-for-device >>"$WATCH_LOG" 2>&1 || true
  for _ in $(seq 1 120); do
    if "$ADB" devices 2>/dev/null | grep -q "${DEVICE}[[:space:]]*device"; then
      boot="$("$ADB" -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      if [[ "$boot" == "1" ]]; then
        log "Emulator booted: ${DEVICE}"
        return 0
      fi
    fi
    sleep 2
  done
  log "ERROR: Emulator boot failed"
  return 1
}

suite_finished() {
  [[ -f "$SUMMARY_FILE" ]] || return 1
  grep -q "^DONE PASS=" "$SUMMARY_FILE" || return 1
  local passed failed total
  passed=$(grep -c '^PASS ' "$SUMMARY_FILE" 2>/dev/null || true)
  failed=$(grep -c '^FAIL ' "$SUMMARY_FILE" 2>/dev/null || true)
  passed=${passed:-0}
  failed=${failed:-0}
  total=$((passed + failed))
  [[ "$total" -ge 11 ]]
}

attempt=0
log "===== watchdog start pid=$$ max_attempts=${MAX_ATTEMPTS} ====="

while [[ "$attempt" -lt "$MAX_ATTEMPTS" ]]; do
  attempt=$((attempt + 1))
  log "---- attempt ${attempt}/${MAX_ATTEMPTS} ----"

  if ! ensure_emulator; then
    log "Retry in ${RETRY_SLEEP_SEC}s (emulator)"
    sleep "$RETRY_SLEEP_SEC"
    continue
  fi

  "$ADB" -s "$DEVICE" shell settings put system screen_off_timeout 2147483647 2>/dev/null || true
  "$ADB" -s "$DEVICE" shell svc power stayon true 2>/dev/null || true

  bash "$ROOT/maestro/setup_maestro_env.sh" >>"$WATCH_LOG" 2>&1
  setup_code=$?
  if [[ "$setup_code" -ne 0 ]]; then
    log "setup failed exit=${setup_code}; retry in ${RETRY_SLEEP_SEC}s"
    sleep "$RETRY_SLEEP_SEC"
    continue
  fi

  : >"$SUMMARY_FILE"
  bash "$ROOT/maestro/run_all_tests.sh" 2>&1 | tee "$LATEST_LOG" >>"$WATCH_LOG"
  run_code=${PIPESTATUS[0]}

  if suite_finished; then
    log "===== suite finished (exit=${run_code}) ====="
    date >"$DONE_FLAG"
    grep "^DONE PASS=" "$SUMMARY_FILE" >>"$WATCH_LOG" || true
    exit "$run_code"
  fi

  log "Suite incomplete (exit=${run_code}); retry in ${RETRY_SLEEP_SEC}s"
  sleep "$RETRY_SLEEP_SEC"
done

log "ERROR: max attempts reached without full suite completion"
exit 1
