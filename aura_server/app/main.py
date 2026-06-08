"""
AuraFace Personality API（セキュリティ強化版）

- HTTPS リダイレクト（リバースプロキシ経由）
- CORS 制限
- レート制限
- Firebase 認証（/predict）
- 同意セッション（X-Consent-Session-ID）
- 顔画像の一時保存のみ・処理後削除
"""

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.config import CORS_ORIGINS, NODE_ENV
from app.routers import consents, health, predict, validate_face
from app.security.middleware import SecurityHeadersMiddleware

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

limiter = Limiter(key_func=get_remote_address)

app = FastAPI(
    title="AuraFace Personality API",
    description="顔画像から性格診断を行うサーバーサイドAPI（セキュリティ強化）",
    version="1.1.0",
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(SecurityHeadersMiddleware)

allow_origins = CORS_ORIGINS if NODE_ENV == "production" else CORS_ORIGINS + ["http://localhost", "http://127.0.0.1"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allow_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Consent-Session-ID", "X-API-Key", "x-identity-dev-secret"],
)

app.include_router(health.router)
app.include_router(predict.router)
app.include_router(validate_face.router)
app.include_router(consents.router)

# 既存本番の /analyze, /v1/support/send 等は別モジュールからマウント可能
try:
    from app.legacy_extensions import register_legacy_routes  # type: ignore

    register_legacy_routes(app)
except ImportError:
    pass
