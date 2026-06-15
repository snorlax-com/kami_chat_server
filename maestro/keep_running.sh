#!/usr/bin/env bash
# suite.completed までウォッチドッグを監視・再起動（スリープ抑止付き）
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ -z "${MAESTRO_KEEP_CAFFEINATED:-}" ]]; then
  export MAESTRO_KEEP_CAFFEINATED=1
  exec caffeinate -dims env MAESTRO_KEEP_CAFFEINATED=1 bash "$0" "$@"
fi

RESULT_DIR="$ROOT/test-results/maestro"
PID_FILE="$RESULT_DIR/watchdog.pid"
DONE_FLAG="$RESULT_DIR/suite.completed"
LOG_FILE="$RESULT_DIR/keep_running.log"
POLL_SEC="${MAESTRO_KEEP_POLL_SEC:-90}"

mkdir -p "$RESULT_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

watchdog_alive() {
  [[ -f "$PID_FILE" ]] || return 1
  local p
  p="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null
}

log "===== keep_running start pid=$$ ====="

while [[ ! -f "$DONE_FLAG" ]]; do
  if ! watchdog_alive; then
    log "Watchdog not running; starting..."
    bash "$ROOT/maestro/start_watchdog.sh" >>"$LOG_FILE" 2>&1 || true
  fi
  sleep "$POLL_SEC"
done

log "===== suite.completed detected; keep_running exit ====="
