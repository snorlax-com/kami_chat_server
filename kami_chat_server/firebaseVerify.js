"use strict";

const fs = require("fs");
const path = require("path");

/**
 * Firebase ID トークン検証（claim / GET me 用）。
 *
 * 認証情報の優先順位（いずれか1つ）:
 * 1. FIREBASE_SERVICE_ACCOUNT_JSON … サービスアカウント JSON 文字列（1行でも可）
 * 2. FIREBASE_SERVICE_ACCOUNT_JSON_B64 … 上記 UTF-8 文字列の Base64（Render 等で改行を避けたいとき）
 * 3. FIREBASE_SERVICE_ACCOUNT_PATH … JSON ファイルのパス（ローカル・ボリュームマウント向け）
 * 4. GOOGLE_APPLICATION_CREDENTIALS … Google 標準の JSON キーファイルパス
 *
 * 未設定時は本番では認証付き API は 503。ローカルは IDENTITY_DEV_SECRET でバイパス可。
 */

let admin;
let firebaseReady = false;

function readCredentialsFile(p) {
  const abs = path.isAbsolute(p) ? p : path.resolve(process.cwd(), p);
  return fs.readFileSync(abs, "utf8");
}

/**
 * @returns {string | null}
 */
function loadServiceAccountJsonString() {
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (inline != null && String(inline).trim() !== "") {
    return String(inline).trim();
  }
  const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_JSON_B64;
  if (b64 != null && String(b64).trim() !== "") {
    try {
      return Buffer.from(String(b64).trim(), "base64").toString("utf8");
    } catch (e) {
      console.error("[firebaseVerify] FIREBASE_SERVICE_ACCOUNT_JSON_B64 decode failed", e.message);
      return null;
    }
  }
  const explicitPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (explicitPath != null && String(explicitPath).trim() !== "") {
    try {
      return readCredentialsFile(String(explicitPath).trim());
    } catch (e) {
      console.error("[firebaseVerify] FIREBASE_SERVICE_ACCOUNT_PATH read failed", e.message);
      return null;
    }
  }
  const gac = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (gac != null && String(gac).trim() !== "") {
    try {
      return readCredentialsFile(String(gac).trim());
    } catch (e) {
      console.error("[firebaseVerify] GOOGLE_APPLICATION_CREDENTIALS read failed", e.message);
      return null;
    }
  }
  return null;
}

function tryInitFirebaseAdmin() {
  if (firebaseReady) return;
  const jsonStr = loadServiceAccountJsonString();
  if (!jsonStr) return;
  try {
    admin = require("firebase-admin");
    const cred = JSON.parse(jsonStr);
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
