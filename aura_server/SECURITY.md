# 診断サーバー セキュリティ

## 実装済み

| 項目 | 内容 |
|------|------|
| HTTPS | `FORCE_HTTPS=true` 時、`X-Forwarded-Proto` が https でないリクエストを 301 |
| ヘッダー | `X-Content-Type-Options`, `X-Frame-Options`, `HSTS`（本番） |
| CORS | `CORS_ALLOWED_ORIGINS` のみ（開発は localhost 追加） |
| レート制限 | `/predict` 30/分、`/validate_face` 60/分（slowapi） |
| 認証 | `/predict` … Firebase Bearer 必須（本番） |
| 同意 | `/predict` … `X-Consent-Session-ID` + `/consents/accept` 登録必須 |
| 画像 | 5MB 上限、JPEG/PNG/WebP、処理後 `unlink` |
| ログ | メール・画像パス・JWT 本文は出さない |
| 静的公開 | `uploads/` 等の公開なし |

## デプロイ後の確認

```bash
# 未認証 → 401
curl -s -o /dev/null -w "%{http_code}" -X POST https://api.auraface.jp/predict -F "file=@test.jpg"

# 同意なし → 403（認証ヘッダー付きの場合）
# 同意あり + Firebase トークン → 200
```

## 注意

- `/analyze` 等の既存ルートは `legacy_extensions.py` で引き継ぐか、別プロセスで維持してください。
- 本番では必ず Nginx 等で TLS 終端し、`X-Forwarded-Proto: https` を付与してください。
