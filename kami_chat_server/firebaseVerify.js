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

/** @type {null | 'NO_CREDENTIAL_ENV' | 'JSON_PARSE' | 'B64_DECODE' | 'ADMIN_INIT'} */
let firebaseInitFailureCode = null;

function readCredentialsFile(p) {
  const abs = path.isAbsolute(p) ? p : path.resolve(process.cwd(), p);
  return fs.readFileSync(abs, "utf8");
}

/**
 * Render 貼り付けで混入しやすい空白・改行を除去し、base64url を標準 Base64 に寄せる。
 * @param {string} raw
 */
function sanitizeBase64Input(raw) {
  let s = String(raw).replace(/\s+/g, "").replace(/-/g, "+").replace(/_/g, "/");
  const pad = s.length % 4;
  if (pad === 2) s += "==";
  else if (pad === 3) s += "=";
  else if (pad === 1) return null;
  return s;
}

/**
 * @returns {string | null}
 */
function loadServiceAccountJsonString() {
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (inline != null && String(inline).trim() !== "") {
    let t = String(inline).trim();
    if (t.charCodeAt(0) === 0xfeff) t = t.slice(1);
    return t;
  }
  const b64 = process.env.FIREBASE_SERVICE_ACCOUNT_JSON_B64;
  if (b64 != null && String(b64).trim() !== "") {
    try {
      const clean = sanitizeBase64Input(b64);
      if (!clean) {
        firebaseInitFailureCode = "B64_DECODE";
        console.error("[firebaseVerify] FIREBASE_SERVICE_ACCOUNT_JSON_B64 invalid length/padding");
        return null;
      }
      return Buffer.from(clean, "base64").toString("utf8");
    } catch (e) {
      firebaseInitFailureCode = "B64_DECODE";
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

function stripBomUtf8(s) {
  let t = String(s);
  if (t.charCodeAt(0) === 0xfeff) t = t.slice(1);
  return t;
}

function tryInitFirebaseAdmin() {
  if (firebaseReady) return;
  const jsonStr = loadServiceAccountJsonString();
  if (!jsonStr) {
    if (!firebaseInitFailureCode) firebaseInitFailureCode = "NO_CREDENTIAL_ENV";
    return;
  }
  const forParse = stripBomUtf8(jsonStr);
  try {
    admin = require("firebase-admin");
    let cred;
    try {
      cred = JSON.parse(forParse);
    } catch (e) {
      firebaseInitFailureCode = "JSON_PARSE";
      console.error("[firebaseVerify] service account JSON parse failed", e.message);
      return;
    }
    if (!admin.apps.length) {
      admin.initializeApp({ credential: admin.credential.cert(cred) });
    }
    firebaseReady = true;
    firebaseInitFailureCode = null;
    console.log("[firebaseVerify] firebase-admin initialized");
  } catch (e) {
    firebaseInitFailureCode = "ADMIN_INIT";
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

/**
 * 秘密を返さず、どの環境変数が「空でないか」と初期化失敗コードだけ返す（/health 用）。
 */
function getFirebaseHealthSnapshot() {
  const hasJson = !!(
    process.env.FIREBASE_SERVICE_ACCOUNT_JSON && String(process.env.FIREBASE_SERVICE_ACCOUNT_JSON).trim()
  );
  const hasB64 = !!(
    process.env.FIREBASE_SERVICE_ACCOUNT_JSON_B64 &&
    String(process.env.FIREBASE_SERVICE_ACCOUNT_JSON_B64).trim()
  );
  const hasPath = !!(
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH && String(process.env.FIREBASE_SERVICE_ACCOUNT_PATH).trim()
  );
  const hasGac = !!(process.env.GOOGLE_APPLICATION_CREDENTIALS && String(process.env.GOOGLE_APPLICATION_CREDENTIALS).trim());
  tryInitFirebaseAdmin();
  return {
    firebaseAdmin: firebaseReady,
    firebaseCredentialEnv: { json: hasJson, b64: hasB64, path: hasPath, gac: hasGac },
    firebaseInitFailureCode: firebaseReady ? null : firebaseInitFailureCode,
  };
}

module.exports = {
  verifyBearerToken,
  resolveUserFromRequest,
  isFirebaseConfigured,
  tryInitFirebaseAdmin: tryInitFirebaseAdmin,
  getFirebaseHealthSnapshot,
};
