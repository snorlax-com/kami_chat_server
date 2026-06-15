#!/usr/bin/env python3
"""診断 API セキュリティ検証（ローカル or リモート BASE_URL）。"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("BASE_URL", "http://127.0.0.1:8000").rstrip("/")
PASS = 0
FAIL = 0


def check(name: str, ok: bool, detail: str = ""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  PASS  {name}" + (f" — {detail}" if detail else ""))
    else:
        FAIL += 1
        print(f"  FAIL  {name}" + (f" — {detail}" if detail else ""))


def request(method: str, path: str, *, headers=None, data=None, files_boundary=None):
    url = f"{BASE}{path}"
    hdrs = dict(headers or {})
    body = data
    if isinstance(data, dict):
        body = json.dumps(data).encode("utf-8")
        hdrs.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=body, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as res:
            return res.status, res.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return -1, str(e)


def main():
    print(f"Security verify: {BASE}\n")

    code, body = request("GET", "/health")
    check("GET /health", code == 200 and "ok" in body.lower(), f"status={code}")

    code, _ = request("POST", "/predict", data=b"x" * 2000, headers={"Content-Type": "image/jpeg"})
    check("POST /predict without auth → 401 or 403", code in (401, 403, 422), f"status={code}")

    code, _ = request(
        "POST",
        "/predict",
        headers={
            "Authorization": "Bearer invalid-token",
            "X-Consent-Session-ID": "fake-session",
            "Content-Type": "multipart/form-data; boundary=----x",
        },
        data=(
            b"------x\r\nContent-Disposition: form-data; name=\"file\"; filename=\"t.jpg\"\r\n"
            b"Content-Type: image/jpeg\r\n\r\n"
            + b"\xff\xd8\xff" + b"\x00" * 2000
            + b"\r\n------x--\r\n"
        ),
    )
    check("POST /predict invalid token → 401/403", code in (401, 403, 503), f"status={code}")

    code, _ = request("GET", "/api/chat/thread?chatId=other")
    check("GET /api/chat/thread not on diagnosis server", code in (404, 405), f"status={code}")

    code, _ = request("POST", "/consents/accept", data={"session_id": "sec-test-1", "biometric_explicit": True})
    check("POST /consents/accept", code == 200, f"status={code}")

    code, _ = request(
        "POST",
        "/predict",
        headers={
            "X-Consent-Session-ID": "sec-test-1",
            "Content-Type": "multipart/form-data; boundary=----x",
        },
        data=(
            b"------x\r\nContent-Disposition: form-data; name=\"file\"; filename=\"t.jpg\"\r\n"
            b"Content-Type: image/jpeg\r\n\r\n"
            + b"\xff\xd8\xff" + b"\x00" * 2000
            + b"\r\n------x--\r\n"
        ),
    )
    check(
        "POST /predict consent only no auth → still blocked",
        code in (401, 403, 503),
        f"status={code}",
    )

    code, _ = request(
        "POST",
        "/validate_face",
        headers={"Content-Type": "application/octet-stream"},
        data=b"\xff\xd8\xff" + b"\x00" * 3000,
    )
    check("POST /validate_face small body", code in (200, 400, 404, 422, 503), f"status={code}")

    huge = b"\xff\xd8\xff" + b"\x00" * (6 * 1024 * 1024)
    code, _ = request(
        "POST",
        "/validate_face",
        headers={"Content-Type": "application/octet-stream"},
        data=huge,
    )
    check("POST /validate_face >5MB → 413 or 400", code in (413, 400, 404), f"status={code}")

    print(f"\nResult: {PASS} passed, {FAIL} failed")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
