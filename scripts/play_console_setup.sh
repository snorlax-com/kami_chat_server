#!/usr/bin/env bash
# Play Console / Render 課金検証の CLI セットアップ（コンソール作業の自動化部分）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SERVER="$ROOT/kami_chat_server"
PKG="com.auraface.kami_face_oracle"

echo "========================================"
echo " Play Console セットアップ（CLI）"
echo "========================================"
echo ""

bash "$ROOT/scripts/play_console_prepare.sh"
echo ""

if [[ -f "$SERVER/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$SERVER/.env" 2>/dev/null || true
  set +a
fi

if [[ -n "${RENDER_API_KEY:-}" && -n "${RENDER_SERVICE_ID:-}" ]]; then
  echo "--- Render: GOOGLE_PLAY_PACKAGE_NAME を設定 ---"
  (cd "$SERVER" && npm run render:upsert-play-package) || echo "WARN: Render package name upsert failed"
  if [[ -f "$SERVER/secrets/render-GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64.txt" ]]; then
    echo "--- Render: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64 を設定 ---"
    (cd "$SERVER" && npm run render:upsert-play-sa-b64) || echo "WARN: Play SA upsert failed"
  else
    echo "SKIP: $SERVER/secrets/render-GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64.txt なし"
    echo "      Firebase SA を Play Console に招待済みなら FIREBASE B64 のフォールバックで可"
    echo "      専用 SA: node kami_chat_server/scripts/play-service-account-to-b64.js <json>"
  fi
  echo ""
else
  echo "SKIP Render API（RENDER_API_KEY / RENDER_SERVICE_ID 未設定）"
  echo ""
fi

echo "--- 内部テスト用 AAB ビルド ---"
flutter build appbundle --release
AAB="$ROOT/build/app/outputs/bundle/release/app-release.aab"
if [[ -f "$AAB" ]]; then
  ls -lh "$AAB"
else
  echo "ERROR: AAB が見つかりません: $AAB" >&2
  exit 1
fi
echo ""

echo "========================================"
echo " 手動（Play Console ブラウザ）"
echo "========================================"
echo "1. https://play.google.com/console"
echo "2. 収益化 → 商品"
echo "   - 定期購入: subscription_monthly_500"
echo "   - 消耗型:   normal_ticket_600, urgent_ticket_10000"
echo "3. 設定 → ライセンステスト → テスター Gmail 追加"
echo "4. テストとリリース → 内部テスト → 新しいリリース"
echo "   AAB: $AAB"
echo "5. テスター → オプトイン URL を端末で開き Play からインストール"
echo ""
echo "本番 health 確認:"
echo "  curl -sS https://kami-chat-server.onrender.com/health | python3 -m json.tool"
echo ""
