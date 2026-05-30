#!/usr/bin/env bash
# Render API で本番デプロイをキューに入れる（ダッシュボードの手動 Deploy 相当）
#
# 事前準備:
#   1) Render Dashboard → Account Settings → API Keys でキーを作成
#   2) Web Service → Settings から Service ID（srv-xxxxx）をコピー
#
# 使い方:
#   export RENDER_API_KEY=rnd_xxxxxxxx
#   export RENDER_SERVICE_ID=srv_xxxxxxxx
#   ./scripts/trigger-render-deploy.sh
#
# 参考: https://api-docs.render.com/reference/create-deploy

set -euo pipefail

if [[ -z "${RENDER_API_KEY:-}" ]]; then
  echo "ERROR: RENDER_API_KEY を設定してください（Render → Account → API Keys）"
  exit 1
fi
if [[ -z "${RENDER_SERVICE_ID:-}" ]]; then
  echo "ERROR: RENDER_SERVICE_ID を設定してください（例: srv-xxxx。Service → Settings）"
  exit 1
fi

URL="https://api.render.com/v1/services/${RENDER_SERVICE_ID}/deploys"
echo "POST $URL"

RESP=$(curl -sS -w "\n%{http_code}" -X POST "$URL" \
  -H "Authorization: Bearer ${RENDER_API_KEY}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{}')

# macOS(BSD) の head は `head -n -1` が使えないため、最後の1行を HTTP code として分離する
CODE=$(printf "%s" "$RESP" | awk 'END{print}')
BODY=$(printf "%s" "$RESP" | awk 'NR==1{print; next} {a[NR]=$0} END{for(i=1;i<NR;i++) print a[i]}')

echo "HTTP $CODE"
echo "$BODY" | head -c 2000
echo ""

if [[ "$CODE" -ge 200 && "$CODE" -lt 300 ]]; then
  echo "OK: デプロイがトリガーされました。Render ダッシュボードの Deploys で進捗を確認してください。"
  exit 0
fi
echo "FAILED: API エラー。キーの権限・Service ID・課金状態を確認してください。"
exit 1
