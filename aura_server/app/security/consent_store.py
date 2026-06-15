"""生体データ同意セッション（SQLite）。"""

import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from app.config import CONSENT_DB_PATH


def _connect():
    CONSENT_DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(CONSENT_DB_PATH), check_same_thread=False)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS consent_sessions (
            session_id TEXT PRIMARY KEY,
            biometric_explicit INTEGER NOT NULL DEFAULT 0,
            accepted_at TEXT NOT NULL,
            withdrawn_at TEXT
        )
        """
    )
    conn.commit()
    return conn


def accept_session(session_id: str, biometric_explicit: bool) -> None:
    sid = (session_id or "").strip()
    if not sid:
        raise ValueError("session_id required")
    now = datetime.now(timezone.utc).isoformat()
    conn = _connect()
    try:
        conn.execute(
            """
            INSERT INTO consent_sessions (session_id, biometric_explicit, accepted_at, withdrawn_at)
            VALUES (?, ?, ?, NULL)
            ON CONFLICT(session_id) DO UPDATE SET
              biometric_explicit = excluded.biometric_explicit,
              accepted_at = excluded.accepted_at,
              withdrawn_at = NULL
            """,
            (sid, 1 if biometric_explicit else 0, now),
        )
        conn.commit()
    finally:
        conn.close()


def withdraw_session(session_id: str) -> None:
    sid = (session_id or "").strip()
    if not sid:
        raise ValueError("session_id required")
    now = datetime.now(timezone.utc).isoformat()
    conn = _connect()
    try:
        conn.execute(
            "UPDATE consent_sessions SET withdrawn_at = ? WHERE session_id = ?",
            (now, sid),
        )
        conn.commit()
    finally:
        conn.close()


def has_valid_consent(session_id: Optional[str]) -> bool:
    sid = (session_id or "").strip()
    if not sid:
        return False
    conn = _connect()
    try:
        row = conn.execute(
            """
            SELECT biometric_explicit, withdrawn_at FROM consent_sessions
            WHERE session_id = ?
            """,
            (sid,),
        ).fetchone()
        if not row:
            return False
        biometric, withdrawn = row
        if withdrawn:
            return False
        return bool(biometric)
    finally:
        conn.close()
