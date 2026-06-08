"""Firebase ID トークン / API キー / 開発用バイパス。"""

from typing import Optional

from fastapi import Header, HTTPException, Request

from app.config import API_KEY, FIREBASE_SERVICE_ACCOUNT_PATH, IDENTITY_DEV_SECRET, IDENTITY_DEV_UID, NODE_ENV

_firebase_ready = False
_firebase_admin = None


def _init_firebase():
    global _firebase_ready, _firebase_admin
    if _firebase_ready or not FIREBASE_SERVICE_ACCOUNT_PATH:
        return
    import firebase_admin
    from firebase_admin import credentials

    cred = credentials.Certificate(FIREBASE_SERVICE_ACCOUNT_PATH)
    if not firebase_admin._apps:
        firebase_admin.initialize_app(cred)
    _firebase_admin = firebase_admin
    _firebase_ready = True


async def resolve_user(
    request: Request,
    authorization: Optional[str] = Header(None),
    x_api_key: Optional[str] = Header(None, alias="X-API-Key"),
) -> dict:
    """認証済みユーザー情報 { uid, email }。失敗時は HTTPException。"""
    if NODE_ENV != "production" and IDENTITY_DEV_SECRET:
        got = request.headers.get("x-identity-dev-secret")
        if got == IDENTITY_DEV_SECRET:
            return {"uid": IDENTITY_DEV_UID, "email": None}

    if API_KEY and x_api_key and x_api_key.strip() == API_KEY:
        return {"uid": "api_key", "email": None}

    token = _extract_bearer(authorization)
    if not token:
        raise HTTPException(status_code=401, detail="認証が必要です。")

    if FIREBASE_SERVICE_ACCOUNT_PATH:
        _init_firebase()
        if _firebase_ready:
            from firebase_admin import auth

            try:
                decoded = auth.verify_id_token(token)
                return {
                    "uid": decoded.get("uid") or decoded.get("sub"),
                    "email": decoded.get("email"),
                }
            except Exception:
                raise HTTPException(status_code=401, detail="認証トークンが無効です。")

    if NODE_ENV != "production":
        return {"uid": "dev-bearer", "email": None}

    raise HTTPException(status_code=503, detail="認証が設定されていません。")


def _extract_bearer(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    parts = authorization.split(" ", 1)
    if len(parts) != 2 or parts[0].lower() != "bearer":
        return None
    return parts[1].strip() or None
