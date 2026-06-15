# AuraFace 診断 API（セキュリティ強化版）

Vultr `45.77.26.42:8000` 向けの FastAPI サーバーです。  
推論ロジックは `../face_shape_ai` を利用します。

## 新規セキュリティ機能

- HTTPS 強制（Nginx + `X-Forwarded-Proto`）
- CORS 制限
- レート制限（slowapi）
- `/predict` … Firebase `Authorization: Bearer` 必須
- `/predict` … `X-Consent-Session-ID` + `/consents/accept` 必須
- 顔画像は一時ファイルのみ・処理後削除（`SAVE_DEBUG_IMAGES=false`）
- `/validate_face` … 正面判定（バイナリ POST）
- 個人情報を含まないログ

## Vultr へのデプロイ

```bash
# ローカルから（SSH キーは ~/.ssh/vultr_server_key 等）
export VULTR_HOST=45.77.26.42
export REMOTE_DIR=/root/aura_server

rsync -avz --exclude venv --exclude __pycache__ --exclude data \
  ./aura_server/ root@$VULTR_HOST:$REMOTE_DIR/
rsync -avz ./face_shape_ai/ root@$VULTR_HOST:/root/kami_face_oracle/face_shape_ai/

ssh root@$VULTR_HOST <<'EOF'
cd /root/aura_server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# .env を編集: FIREBASE_SERVICE_ACCOUNT_PATH, CORS_ALLOWED_ORIGINS, FORCE_HTTPS=true
mkdir -p /root/secure data
EOF
```

### systemd（例）

```ini
[Unit]
Description=AuraFace Diagnosis API
After=network.target

[Service]
User=root
WorkingDirectory=/root/aura_server
Environment="KAMI_FACE_ORACLE_DIR=/root/kami_face_oracle"
ExecStart=/root/aura_server/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

Nginx は `deploy/nginx-auraface-api.conf.example` を参照。

## ローカル起動

```bash
cd aura_server
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
export KAMI_FACE_ORACLE_DIR="$(cd .. && pwd)"
export IDENTITY_DEV_SECRET=local-dev-secret
export FORCE_HTTPS=false
uvicorn app.main:app --reload --port 8000
```

## アプリ側

```bash
flutter build apk --dart-define=DIAGNOSIS_SERVER_URL=https://api.auraface.jp
# 移行中は
flutter build apk --dart-define=DIAGNOSIS_SERVER_URL=http://45.77.26.42:8000
```

詳細: [SECURITY.md](./SECURITY.md)
