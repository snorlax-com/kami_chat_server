#!/usr/bin/env bash
# スリープ・画面ロック中も完走までリトライ
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RESULT_DIR="$ROOT/test-results/maestro"
mkdir -p "$RESULT_DIR"

PID_FILE="$RESULT_DIR/watchdog.pid"
LOG_FILE="$RESULT_DIR/watchdog.log"

if [[ -f "$PID_FILE" ]]; then
  old="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old" ]] && kill -0 "$old" 2>/dev/null; then
    echo "Watchdog already running PID=${old}"
    echo "  tail -f ${LOG_FILE}"
    exit 0
  fi
fi

nohup bash "$ROOT/maestro/run_until_complete.sh" >>"$LOG_FILE" 2>&1 &
wpid=$!
disown "$wpid" 2>/dev/null || true
echo "$wpid" >"$PID_FILE"

echo "Maestro watchdog started (sleep-resistant, retries until 11 flows complete)"
echo "  PID: ${wpid} (${PID_FILE})"
echo "  Log: ${LOG_FILE}"
echo "  Summary: ${RESULT_DIR}/summary.txt"
echo "  Done flag: ${RESULT_DIR}/suite.completed"
echo "  Stop: kill \$(cat ${PID_FILE})"
