"use strict";

/**
 * Firebase ID トークン検証（claim / GET me 用）。
 * FIREBASE_SERVICE_ACCOUNT_JSON にサービスアカウント JSON 文字列を設定。
 * 未設定時は本番では認証付き API は 503。ローカルは IDENTITY_DEV_SECRET でバイパス可。
 */

let admin;
let firebaseReady = false;

function tryInitFirebaseAdmin() {
  if (firebaseReady) return;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!raw || String(raw).trim() === "") return;
  try {
    admin = require("firebase-admin");
    const cred = JSON.parse(String(raw));
    if (!admin.apps.length) {
      admin.initializeApp({ credential: admin.credential.cert(cred) });
    }
    firebaseReady = true;
    console.log("[firebaseVerify] firebase-admin initialized");
  } catch (e) {
    console.error("[firebaseVerify] init failed", e.message);
  }
}

function isFirebaseConfigured() {
  tryInitFirebaseAdmin();
  return firebaseReady;
}

/**
 * @returns {Promise<{ uid: string, email: string | null, emailVerified: boolean } | null>}
 */
async function verifyBearerToken(idToken) {
  tryInitFirebaseAdmin();
  if (!firebaseReady || !idToken) return null;
  const decoded = await admin.auth().verifyIdToken(idToken);
  return {
    uid: decoded.uid,
    email: decoded.email || null,
    emailVerified: !!decoded.email_verified,
  };
}

/**
 * 開発用: Authorization: Bearer <firebase id token> が無い場合のバイパス（本番では無効）
 */
function tryDevIdentity(req) {
  if (process.env.NODE_ENV === "production") return null;
  const secret = process.env.IDENTITY_DEV_SECRET;
  const uid = process.env.IDENTITY_DEV_UID;
  if (!secret || !uid) return null;
  const got = req.get("x-identity-dev-secret");
  if (got !== secret) return null;
  return { uid, email: null, emailVerified: false };
}

/**
 * @returns {Promise<{ uid: string, email: string | null, emailVerified: boolean } | null>}
 */
async function resolveUserFromRequest(req) {
  const dev = tryDevIdentity(req);
  if (dev) return dev;

  const auth = req.headers.authorization || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  const token = m ? m[1].trim() : "";
  if (!token) return null;
  try {
    return await verifyBearerToken(token);
  } catch (e) {
    console.warn("[firebaseVerify] verify failed", e.message);
    return null;
  }
}

module.exports = {
  verifyBearerToken,
  resolveUserFromRequest,
  isFirebaseConfigured,
  tryInitFirebaseAdmin: tryInitFirebaseAdmin,
};
