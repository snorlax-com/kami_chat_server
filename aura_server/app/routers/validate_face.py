"""正面判定（バイナリ JPEG/PNG）。"""

import os
import tempfile
import time
import uuid

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.config import MAX_UPLOAD_BYTES, RATE_LIMIT_VALIDATE, SAVE_DEBUG_IMAGES, UPLOAD_TMP_DIR
from app.security.image_upload import safe_unlink
from app.security.logging_safe import log_request

limiter = Limiter(key_func=get_remote_address)
router = APIRouter(tags=["validate_face"])


@router.post("/validate_face")
@limiter.limit(RATE_LIMIT_VALIDATE)
async def validate_face(request: Request):
    body = await request.body()
    if not body or len(body) < 1000:
        return JSONResponse(status_code=400, content={"ok": False, "error": "empty body"})
    if len(body) > MAX_UPLOAD_BYTES:
        return JSONResponse(status_code=413, content={"ok": False, "error": "too large"})

    request_id = str(uuid.uuid4())
    start = time.time()
    temp_path = None
    debug_dir = "/tmp/face_debug" if SAVE_DEBUG_IMAGES else None

    try:
        from app.debug_image import load_as_rgb, run_face_detection, save_and_sanity_check_image

        UPLOAD_TMP_DIR.mkdir(parents=True, exist_ok=True)
        fd, temp_path = tempfile.mkstemp(prefix="aura_vf_", suffix=".jpg", dir=str(UPLOAD_TMP_DIR))
        os.close(fd)
        with open(temp_path, "wb") as f:
            f.write(body)

        corrected = save_and_sanity_check_image(temp_path, debug_dir or "/tmp")
        rgb = load_as_rgb(corrected, debug_dir or "/tmp")
        count, _ = run_face_detection(rgb, min_conf=0.5)

        is_frontal = count >= 1
        result = {
            "is_frontal": is_frontal,
            "face_count": count,
            "reasons": [] if is_frontal else ["顔が検出できませんでした"],
            "suggestion": "正面を向いて、顔全体が枠に入るように撮影してください。"
            if not is_frontal
            else "",
        }
        log_request(
            "validate_face_ok",
            request_id=request_id,
            nbytes=len(body),
            face_count=count,
            elapsed_ms=int((time.time() - start) * 1000),
        )
        return {"ok": True, "result": result}
    except Exception:
        log_request("validate_face_error", request_id=request_id)
        return JSONResponse(
            status_code=400,
            content={"ok": False, "error": "画像の処理に失敗しました。"},
        )
    finally:
        safe_unlink(temp_path)
