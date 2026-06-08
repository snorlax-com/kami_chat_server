#!/usr/bin/env python3
"""認証・同意レイヤーの単体検証（mediapipe 不要）。"""
import sys

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routers import consents, health
from app.security.consent_store import accept_session, has_valid_consent

app = FastAPI()
app.include_router(health.router)
app.include_router(consents.router)
client = TestClient(app)

PASS = FAIL = 0


def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  PASS  {name}" + (f" — {detail}" if detail else ""))
    else:
        FAIL += 1
        print(f"  FAIL  {name}" + (f" — {detail}" if detail else ""))


def main():
    print("Aura API security (minimal routes)\n")

    r = client.get("/health")
    check("GET /health", r.status_code == 200, r.json())

    r = client.post("/consents/accept", json={"session_id": "unit-1", "biometric_explicit": True})
    check("POST /consents/accept", r.status_code == 200, str(r.status_code))

    check("has_valid_consent after accept", has_valid_consent("unit-1"))

    r = client.post("/consents/withdraw", params={"session_id": "unit-1"})
    check("POST /consents/withdraw", r.status_code == 200)

    check("has_valid_consent after withdraw", not has_valid_consent("unit-1"))

    huge = b"\x00" * (6 * 1024 * 1024)
    # predict は別途デプロイ環境で検証（import に mediapipe 必要）

    print(f"\nResult: {PASS} passed, {FAIL} failed")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
