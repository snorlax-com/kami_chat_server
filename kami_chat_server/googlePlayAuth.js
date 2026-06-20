"use strict";

const fs = require("fs");
const path = require("path");

/** @type {null | 'NO_CREDENTIAL_ENV' | 'JSON_PARSE' | 'B64_DECODE'} */
let playInitFailureCode = null;

function readCredentialsFile(p) {
  const abs = path.isAbsolute(p) ? p : path.resolve(process.cwd(), p);
  return fs.readFileSync(abs, "utf8");
}

function sanitizeBase64Input(raw) {
  let s = String(raw).replace(/\s+/g, "").replace(/-/g, "+").replace(/_/g, "/");
  const pad = s.length % 4;
  if (pad === 2) s += "==";
  else if (pad === 3) s += "=";
  else if (pad === 1) return null;
  return s;
}

function parseJsonCredentials(jsonStr) {
  let t = String(jsonStr).trim();
  if (t.charCodeAt(0) === 0xfeff) t = t.slice(1);
  try {
    return JSON.parse(t);
  } catch (e) {
    playInitFailureCode = "JSON_PARSE";
    console.error("[googlePlayAuth] service account JSON parse failed", e.message);
    return null;
  }
}

function loadFromInlineOrB64(jsonEnv, b64Env) {
  const inline = process.env[jsonEnv];
  if (inline != null && String(inline).trim() !== "") {
    return parseJsonCredentials(inline);
  }
  const b64 = process.env[b64Env];
  if (b64 != null && String(b64).trim() !== "") {
    try {
      const clean = sanitizeBase64Input(b64);
      if (!clean) {
        playInitFailureCode = "B64_DECODE";
        return null;
      }
      return parseJsonCredentials(Buffer.from(clean, "base64").toString("utf8"));
    } catch (e) {
      playInitFailureCode = "B64_DECODE";
      console.error(`[googlePlayAuth] ${b64Env} decode failed`, e.message);
      return null;
    }
  }
  return null;
}

/**
 * Play Android Developer API 用サービスアカウント JSON。
 * Render では GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64 または Firebase 用 B64 のフォールバックを使う。
 */
function loadGooglePlayCredentialsJson() {
  playInitFailureCode = null;

  let cred = loadFromInlineOrB64(
    "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
    "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64"
  );
  if (cred) return cred;

  const gac = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (gac != null && String(gac).trim() !== "") {
    try {
      return parseJsonCredentials(readCredentialsFile(String(gac).trim()));
    } catch (e) {
      console.error("[googlePlayAuth] GOOGLE_APPLICATION_CREDENTIALS read failed", e.message);
    }
  }

  cred = loadFromInlineOrB64(
    "FIREBASE_SERVICE_ACCOUNT_JSON",
    "FIREBASE_SERVICE_ACCOUNT_JSON_B64"
  );
  if (cred) return cred;

  playInitFailureCode = "NO_CREDENTIAL_ENV";
  return null;
}

function getGooglePlayPackageName() {
  return (process.env.GOOGLE_PLAY_PACKAGE_NAME || "").trim();
}

function isGooglePlayBillingConfigured() {
  return !!getGooglePlayPackageName() && !!loadGooglePlayCredentialsJson();
}

function getGooglePlayHealthSnapshot() {
  const pkg = getGooglePlayPackageName();
  const hasPlayJson = !!(
    process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON &&
    String(process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON).trim()
  );
  const hasPlayB64 = !!(
    process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64 &&
    String(process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64).trim()
  );
  const hasGac = !!(
    process.env.GOOGLE_APPLICATION_CREDENTIALS &&
    String(process.env.GOOGLE_APPLICATION_CREDENTIALS).trim()
  );
  const hasFirebaseFallback = !!(
    (process.env.FIREBASE_SERVICE_ACCOUNT_JSON &&
      String(process.env.FIREBASE_SERVICE_ACCOUNT_JSON).trim()) ||
    (process.env.FIREBASE_SERVICE_ACCOUNT_JSON_B64 &&
      String(process.env.FIREBASE_SERVICE_ACCOUNT_JSON_B64).trim())
  );
  const cred = loadGooglePlayCredentialsJson();
  return {
    googlePlayPackageName: pkg || null,
    googlePlayCredentials: !!cred,
    googlePlayCredentialEnv: {
      playJson: hasPlayJson,
      playB64: hasPlayB64,
      gac: hasGac,
      firebaseFallback: hasFirebaseFallback && !hasPlayJson && !hasPlayB64 && !hasGac,
    },
    googlePlayInitFailureCode: cred ? null : playInitFailureCode,
    googlePlayBillingReady: !!pkg && !!cred,
  };
}

module.exports = {
  loadGooglePlayCredentialsJson,
  getGooglePlayPackageName,
  isGooglePlayBillingConfigured,
  getGooglePlayHealthSnapshot,
};
