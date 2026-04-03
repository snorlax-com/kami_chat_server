#!/usr/bin/env bash
# ローカルでサーバー起動 → 送受信テスト → E2E を連続実行
#   cd kami_chat_server && chmod +x scripts/run-local-e2e.sh && ./scripts/run-local-e2e.sh
set -euo pipefail

PORT="${PORT:-3040}"
export TOKEN_SECRET="${TOKEN_SECRET:-local_dev_token_secret_change_me}"
cd "$(dirname "$0")/.."

npm install --silent 2>/dev/null || npm install

PORT="$PORT" TOKEN_SECRET="$TOKEN_SECRET" node index.js &
PID=$!
cleanup() { kill "$PID" 2>/dev/null || true; }
trap cleanup EXIT

echo "Waiting for http://127.0.0.1:${PORT}/health ..."
for _ in $(seq 1 40); do
  if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

echo ""
echo "=== send-receive-send-test ==="
node scripts/send-receive-send-test.js "http://127.0.0.1:${PORT}"

echo ""
echo "=== e2e-full-flow-test ==="
BASE_URL="http://127.0.0.1:${PORT}" TOKEN_SECRET="$TOKEN_SECRET" node scripts/e2e-full-flow-test.js

echo ""
echo "=== 完了 ==="
