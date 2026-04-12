"use strict";

const express = require("express");
const { randomUUID } = require("crypto");
const { createGuestSessionId } = require("./idUtils");
const idb = require("./identityDb");
const { resolveUserFromRequest, isFirebaseConfigured } = require("./firebaseVerify");

const router = express.Router();

function nowIso() {
  return new Date().toISOString();
}

/** POST /api/auth/guest-session */
router.post("/auth/guest-session", (req, res) => {
  try {
    const id = createGuestSessionId();
    const t = nowIso();
    idb.insertGuestSession(id, t);
    return res.json({ guestSessionId: id });
  } catch (e) {
    console.error("[identity] guest-session", e);
    return res.status(500).json({ status: "error", message: String(e.message || e) });
  }
});

/** POST /api/diagnosis/tutorial */
router.post("/diagnosis/tutorial", (req, res) => {
  try {
    const body = req.body || {};
    const guestSessionId = String(body.guestSessionId || "").trim();
    const pillarKey = String(body.pillarKey || "").trim();
    const summaryText = body.summaryText != null ? String(body.summaryText) : null;
    const detailJson = body.detailJson;
    const sourceImageUrl = body.sourceImageUrl != null ? String(body.sourceImageUrl) : null;

    if (!guestSessionId || !pillarKey) {
      return res.status(400).json({ status: "error", message: "guestSessionId and pillarKey required" });
    }
    if (detailJson === undefined || detailJson === null) {
      return res.status(400).json({ status: "error", message: "detailJson required" });
    }

    const t = nowIso();
    let gs = idb.guestSessionExists(guestSessionId);
    if (!gs) {
      idb.insertGuestSession(guestSessionId, t);
    } else if (gs.converted_to_user_id) {
      return res.status(409).json({
        status: "error",
        message: "guest session already converted; cannot save new tutorial diagnosis to it",
      });
    }

    const detailStr = typeof detailJson === "string" ? detailJson : JSON.stringify(detailJson);
    const diagId = `diag_${randomUUID()}`;
    idb.insertTutorialDiagnosis({
      id: diagId,
      user_id: null,
      guest_session_id: guestSessionId,
      pillar_key: pillarKey,
      summary_text: summaryText,
      detail_json: detailStr,
      source_image_url: sourceImageUrl,
      is_unlocked: 0,
      created_at: t,
      updated_at: t,
    });

    return res.json({
      status: "ok",
      diagnosisId: diagId,
      /** 未認証クライアントへ詳細 JSON は返さない */
    });
  } catch (e) {
    console.error("[identity] diagnosis/tutorial", e);
    return res.status(500).json({ status: "error", message: String(e.message || e) });
  }
});

/** POST /api/auth/claim-guest-data */
router.post("/auth/claim-guest-data", async (req, res) => {
  try {
    const identity = await resolveUserFromRequest(req);
    if (!identity) {
      if (!isFirebaseConfigured() && process.env.NODE_ENV === "production") {
        return res.status(503).json({
          status: "error",
          message:
            "Firebase admin not configured (set FIREBASE_SERVICE_ACCOUNT_JSON on the server)",
        });
      }
      return res.status(401).json({ status: "error", message: "unauthorized" });
    }

    const body = req.body || {};
    const guestSessionId = String(body.guestSessionId || "").trim();
    if (!guestSessionId) {
      return res.status(400).json({ status: "error", message: "guestSessionId required" });
    }

    const userId = identity.uid;
    const t = nowIso();
    const authProvider = String(body.authProvider || "firebase").slice(0, 32);

    idb.upsertUser({
      id: userId,
      auth_provider: authProvider,
      provider_user_id: userId,
      email: identity.email,
      email_verified: identity.emailVerified ? 1 : 0,
      display_name: body.displayName != null ? String(body.displayName) : null,
      photo_url: body.photoUrl != null ? String(body.photoUrl) : null,
      created_at: t,
      updated_at: t,
    });

    const result = idb.claimGuestDiagnosisToUser({
      guestSessionId,
      userId,
      authProvider,
      now: t,
    });

    if (!result.ok) {
      const code = result.code === "guest_not_found" ? 404 : 409;
      return res.status(code).json({ status: "error", message: result.message || result.code });
    }

    return res.json({
      status: "ok",
      success: true,
      guestSessionId,
      userId,
      claimedAt: t,
      already: result.already === true,
    });
  } catch (e) {
    console.error("[identity] claim-guest-data", e);
    return res.status(500).json({ status: "error", message: String(e.message || e) });
  }
});

/** GET /api/diagnosis/me */
router.get("/diagnosis/me", async (req, res) => {
  try {
    const identity = await resolveUserFromRequest(req);
    if (!identity) {
      return res.status(401).json({ status: "error", message: "unauthorized" });
    }

    const row = idb.getLatestDiagnosisForUser(identity.uid, { includeDetail: true });
    if (!row) {
      return res.status(404).json({ status: "error", message: "no diagnosis" });
    }

    if (!row.isUnlocked) {
      return res.json({
        status: "ok",
        pillarKey: row.pillarKey,
        summaryText: row.summaryText,
        isUnlocked: false,
      });
    }

    return res.json({
      status: "ok",
      pillarKey: row.pillarKey,
      summaryText: row.summaryText,
      isUnlocked: true,
      detailJson: row.detailJson,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    });
  } catch (e) {
    console.error("[identity] diagnosis/me", e);
    return res.status(500).json({ status: "error", message: String(e.message || e) });
  }
});

/** GET /api/chat/threads/me */
router.get("/chat/threads/me", async (req, res) => {
  try {
    const identity = await resolveUserFromRequest(req);
    if (!identity) {
      return res.status(401).json({ status: "error", message: "unauthorized" });
    }
    const threads = idb.listThreadsForUser(identity.uid);
    return res.json({ status: "ok", threads });
  } catch (e) {
    console.error("[identity] chat/threads/me", e);
    return res.status(500).json({ status: "error", message: String(e.message || e) });
  }
});

module.exports = router;
