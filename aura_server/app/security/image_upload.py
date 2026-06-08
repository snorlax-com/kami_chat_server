"""画像アップロード検証・一時保存・削除。"""

import os
import tempfile
import uuid
from pathlib import Path
from typing import Optional, Tuple

from fastapi import HTTPException, UploadFile

from app.config import MAX_UPLOAD_BYTES, UPLOAD_TMP_DIR

ALLOWED_CONTENT_TYPES = frozenset(
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp",
        "application/octet-stream",
    }
)


async def read_and_store_upload(file: UploadFile) -> Tuple[str, int]:
    """
    検証後に一時ファイルへ保存。
    Returns: (path, byte_length)
    """
    UPLOAD_TMP_DIR.mkdir(parents=True, exist_ok=True)
    content_type = (file.content_type or "").lower().split(";")[0].strip()
    if content_type and content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(status_code=400, detail="画像形式が不正です。")

    chunks = []
    total = 0
    while True:
        chunk = await file.read(1024 * 64)
        if not chunk:
            break
        total += len(chunk)
        if total > MAX_UPLOAD_BYTES:
            raise HTTPException(status_code=413, detail="画像サイズが大きすぎます（最大5MB）。")
        chunks.append(chunk)

    if total < 1000:
        raise HTTPException(status_code=400, detail="画像データが不正です。")

    suffix = ".jpg"
    if content_type == "image/png":
        suffix = ".png"
    elif content_type == "image/webp":
        suffix = ".webp"

    fd, path = tempfile.mkstemp(prefix="aura_", suffix=suffix, dir=str(UPLOAD_TMP_DIR))
    os.close(fd)
    try:
        with open(path, "wb") as f:
            for c in chunks:
                f.write(c)
    except Exception:
        safe_unlink(path)
        raise
    return path, total


def safe_unlink(path: Optional[str]) -> None:
    if not path:
        return
    try:
        if os.path.exists(path):
            os.unlink(path)
    except OSError:
        pass
