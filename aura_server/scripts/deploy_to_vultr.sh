#!/usr/bin/env bash
# 診断 API を Vultr へ rsync デプロイ（要 SSH 鍵）
set -euo pipefail

VULTR_HOST="${VULTR_HOST:-45.77.26.42}"
REMOTE_DIR="${REMOTE_DIR:-/root/aura_server}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Deploy aura_server -> root@${VULTR_HOST}:${REMOTE_DIR}"
rsync -avz --delete \
  --exclude venv \
  --exclude __pycache__ \
  --exclude '.env' \
  --exclude 'data/*.sqlite' \
  "${REPO_ROOT}/aura_server/" "root@${VULTR_HOST}:${REMOTE_DIR}/"

echo "Sync face_shape_ai (inference assets)"
ssh "root@${VULTR_HOST}" "mkdir -p /root/kami_face_oracle"
rsync -avz "${REPO_ROOT}/face_shape_ai/" "root@${VULTR_HOST}:/root/kami_face_oracle/face_shape_ai/"

echo "Install deps & restart (adjust if using systemd)"
ssh "root@${VULTR_HOST}" <<EOF
set -e
cd ${REMOTE_DIR}
if [ ! -d venv ]; then python3 -m venv venv; fi
source venv/bin/activate
pip install -q -r requirements.txt
export KAMI_FACE_ORACLE_DIR=/root/kami_face_oracle
pkill -f 'uvicorn app.main:app' 2>/dev/null || true
nohup venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 > /var/log/aura_api.log 2>&1 &
sleep 2
curl -s http://127.0.0.1:8000/health
EOF

echo "Done. Configure Nginx TLS and .env on the server."
