from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from app.security import consent_store as consent_store
from app.security.logging_safe import log_request

router = APIRouter(prefix="/consents", tags=["consents"])


class ConsentAcceptBody(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    session_id: str
    country: Optional[str] = None
    region_group: Optional[str] = None
    biometric_explicit: bool = True


@router.post("/accept")
async def accept_consent(body: ConsentAcceptBody):
    try:
        consent_store.accept_session(body.session_id, body.biometric_explicit)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    log_request("consent_accept", session_len=len(body.session_id))
    return {"status": "ok"}


@router.post("/withdraw")
async def withdraw_consent(session_id: str):
    try:
        consent_store.withdraw_session(session_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    log_request("consent_withdraw", session_len=len(session_id))
    return {"status": "ok"}
