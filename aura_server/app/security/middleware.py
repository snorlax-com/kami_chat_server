"""HTTPS 強制・セキュリティヘッダー。"""

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import RedirectResponse, Response

from app.config import FORCE_HTTPS, NODE_ENV


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if FORCE_HTTPS:
            proto = request.headers.get("x-forwarded-proto", request.url.scheme)
            if proto != "https" and request.url.path != "/health":
                host = request.headers.get("host") or request.url.netloc
                url = f"https://{host}{request.url.path}"
                if request.url.query:
                    url += f"?{request.url.query}"
                return RedirectResponse(url, status_code=301)

        response: Response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        if NODE_ENV == "production":
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response
