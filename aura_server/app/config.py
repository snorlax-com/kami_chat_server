"""環境変数・パス設定（秘密情報は .env のみ）。"""

import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent.parent
# 推論用 face_shape_ai はリポジトリ直下
KAMI_FACE_ORACLE_DIR = Path(
    os.getenv("KAMI_FACE_ORACLE_DIR", str(BASE_DIR.parent))
)

HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8000"))
NODE_ENV = os.getenv("NODE_ENV", "development")

# 認証
API_KEY = (os.getenv("API_KEY") or "").strip() or None
FIREBASE_SERVICE_ACCOUNT_PATH = (
    os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH") or os.getenv("GOOGLE_APPLICATION_CREDENTIALS") or ""
).strip() or None
IDENTITY_DEV_SECRET = (os.getenv("IDENTITY_DEV_SECRET") or "").strip() or None
IDENTITY_DEV_UID = (os.getenv("IDENTITY_DEV_UID") or "dev-user").strip()

# CORS（カンマ区切り）
_default_cors = "https://auraface.jp,https://admin.auraface.jp"
CORS_ORIGINS = [
    o.strip()
    for o in os.getenv("CORS_ALLOWED_ORIGINS", _default_cors).split(",")
    if o.strip()
]

# アップロード
MAX_UPLOAD_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", str(5 * 1024 * 1024)))
UPLOAD_TMP_DIR = Path(os.getenv("UPLOAD_TMP_DIR", "/tmp/aura_uploads"))
SAVE_DEBUG_IMAGES = os.getenv("SAVE_DEBUG_IMAGES", "false").lower() in (
    "1",
    "true",
    "yes",
)

# 同意 DB
CONSENT_DB_PATH = Path(os.getenv("CONSENT_DB_PATH", str(BASE_DIR / "data" / "consents.sqlite")))

# レート制限
RATE_LIMIT_PREDICT = os.getenv("RATE_LIMIT_PREDICT", "30/minute")
RATE_LIMIT_VALIDATE = os.getenv("RATE_LIMIT_VALIDATE", "60/minute")

# 本番で HTTP を拒否（リバースプロキシの X-Forwarded-Proto 前提）
FORCE_HTTPS = os.getenv("FORCE_HTTPS", "true" if NODE_ENV == "production" else "false").lower() in (
    "1",
    "true",
    "yes",
)
