#!/usr/bin/env bash
# スリープ抑止 + 完走までリトライ（Cursor/ターミナルから起動用）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

RESULT_DIR="$ROOT/test-results/maestro"
mkdir -p "$RESULT_DIR"

if [[ -f "$RESULT_DIR/suite.completed" ]]; then
  echo "Suite already completed: $RESULT_DIR/suite.completed"
  cat "$RESULT_DIR/summary.txt" 2>/dev/null || true
  exit 0
fi

if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
export PATH="${JAVA_HOME:+$JAVA_HOME/bin:}${PATH}:${HOME}/.maestro/bin}"
export MAESTRO_CLI_NO_ANALYTICS=1

flutter emulators --launch "${MAESTRO_AVD:-Medium_Phone_API_36.1}" >/dev/null 2>&1 || true
sleep 20
adb wait-for-device || true
for _ in $(seq 1 90); do
  boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
  [[ "$boot" == "1" ]] && break
  sleep 2
done

echo $$ >"$RESULT_DIR/watchdog.pid"
exec caffeinate -dims bash "$ROOT/maestro/run_until_complete.sh" 2>&1 | tee -a "$RESULT_DIR/watchdog.log"
