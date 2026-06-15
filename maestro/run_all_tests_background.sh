#!/usr/bin/env bash
# 画面閉鎖・Macスリープ中も継続: nohup + caffeinate で Maestro 全テストを実行
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RESULT_DIR="$ROOT/test-results/maestro"
mkdir -p "$RESULT_DIR"

PID_FILE="$RESULT_DIR/maestro.pid"
CAFF_PID_FILE="$RESULT_DIR/caffeinate.pid"
LOG_FILE="$RESULT_DIR/background.log"

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "Already running PID=${old_pid}. Log: ${LOG_FILE}" >&2
    exit 1
  fi
fi

# caffeinate: ディスプレイ/システム/ディスクのスリープを抑止して detached 本体を実行
nohup caffeinate -dims bash "$ROOT/maestro/run_all_tests_detached.sh" >>"$LOG_FILE" 2>&1 &
wrapper_pid=$!
echo "$wrapper_pid" >"$PID_FILE"

# caffeinate 子プロセス（あれば記録）
sleep 1
pgrep -P "$wrapper_pid" caffeinate 2>/dev/null | head -1 >"$CAFF_PID_FILE" || true

echo "Maestro detached run started (sleep-resistant)"
echo "  PID: ${wrapper_pid}  (${PID_FILE})"
echo "  Log: ${LOG_FILE}"
echo "  Summary: ${RESULT_DIR}/summary.txt"
echo "  Tail: tail -f ${LOG_FILE}"
echo "  Stop: kill \$(cat ${PID_FILE})"
