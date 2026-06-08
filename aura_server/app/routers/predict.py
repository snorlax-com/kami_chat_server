"""性格診断 /predict — 画像は処理後に即削除。"""

import os
import time
import uuid

from fastapi import APIRouter, Depends, File, Header, Request, UploadFile
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.config import RATE_LIMIT_PREDICT, SAVE_DEBUG_IMAGES
from app.debug_image import load_as_rgb, run_face_detection, save_and_sanity_check_image, upscale_if_needed
from app.inference import run_prediction
from app.security.auth import resolve_user
from app.security.consent_store import has_valid_consent
from app.security.image_upload import read_and_store_upload, safe_unlink
from app.security.logging_safe import log_request

limiter = Limiter(key_func=get_remote_address)
router = APIRouter(tags=["predict"])


@router.post("/predict")
@limiter.limit(RATE_LIMIT_PREDICT)
async def predict(
    request: Request,
    file: UploadFile = File(...),
    user: dict = Depends(resolve_user),
    x_consent_session_id: str | None = Header(None, alias="X-Consent-Session-ID"),
):
    request_id = str(uuid.uuid4())
    start = time.time()
    temp_path = None
    corrected_path = None
    debug_dir = "/tmp/face_debug" if SAVE_DEBUG_IMAGES else None

    if not has_valid_consent(x_consent_session_id):
        log_request("predict_denied_consent", request_id=request_id, uid=user.get("uid"))
        return JSONResponse(
            status_code=403,
            content={
                "error": "consent required",
                "request_id": request_id,
                "server_inference": False,
            },
        )

    try:
        temp_path, nbytes = await read_and_store_upload(file)
        corrected_path = save_and_sanity_check_image(temp_path, debug_dir or "/tmp")
        rgb = load_as_rgb(corrected_path, debug_dir or "/tmp")

        try:
            detections_before, _ = run_face_detection(rgb, min_conf=0.5)
        except Exception as e:
            log_request("predict_face_detect_error", request_id=request_id, error_type=type(e).__name__)
            return JSONResponse(
                status_code=500,
                content={
                    "error": "顔検出処理でエラーが発生しました。",
                    "request_id": request_id,
                    "server_inference": False,
                },
            )

        rgb, was_upscaled = upscale_if_needed(rgb, min_size=512)
        if was_upscaled:
            try:
                run_face_detection(rgb, min_conf=0.5)
            except Exception:
                pass

        import cv2

        img_bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        result = run_prediction(img_bgr)

        if result is None:
            log_request(
                "predict_no_face",
                request_id=request_id,
                uid=user.get("uid"),
                nbytes=nbytes,
                detections=detections_before,
            )
            return JSONResponse(
                status_code=400,
                content={
                    "error": "顔が検出されませんでした。",
                    "request_id": request_id,
                    "server_inference": False,
                },
            )

        elapsed_sec = time.time() - start
        result["request_id"] = request_id
        result["server_inference"] = True
        result["elapsed_sec"] = round(elapsed_sec, 3)

        log_request(
            "predict_ok",
            request_id=request_id,
            uid=user.get("uid"),
            nbytes=nbytes,
            personality_type=result.get("personality_type"),
            elapsed_ms=int(elapsed_sec * 1000),
        )
        return JSONResponse(content=result)

    except Exception as e:
        elapsed_sec = time.time() - start
        log_request(
            "predict_error",
            request_id=request_id,
            uid=user.get("uid"),
            error_type=type(e).__name__,
            elapsed_ms=int(elapsed_sec * 1000),
        )
        return JSONResponse(
            status_code=500,
            content={
                "error": "診断に失敗しました。",
                "request_id": request_id,
                "server_inference": False,
            },
        )
    finally:
        safe_unlink(temp_path)
        if corrected_path and corrected_path != temp_path:
            safe_unlink(corrected_path)
