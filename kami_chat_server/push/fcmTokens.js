"use strict";

const crypto = require("crypto");
const idb = require("../identityDb");
const { getFirebaseAdmin } = require("../firebaseVerify");

const COLLECTION = "fcm_tokens";

function tokenDocId(token) {
  return crypto.createHash("sha256").update(String(token)).digest("hex").slice(0, 32);
}

/**
 * @param {string} uid
 * @returns {Promise<Array<{ token: string, platform?: string }>>}
 */
async function listTokensForUser(uid) {
  const userId = String(uid || "").trim();
  if (!userId) return [];

  const seen = new Set();
  const out = [];

  const sqliteRows = idb.listFcmDeviceTokensForUser(userId);
  for (const row of sqliteRows) {
    const token = row?.token ? String(row.token).trim() : "";
    if (!token || seen.has(token)) continue;
    seen.add(token);
    out.push({ token, platform: row.platform });
  }

  const admin = getFirebaseAdmin();
  if (!admin) return out;

  try {
    const snap = await admin
      .firestore()
      .collection("users")
      .doc(userId)
      .collection(COLLECTION)
      .get();
    for (const doc of snap.docs) {
      const token = doc.data()?.token;
      if (!token) continue;
      const t = String(token).trim();
      if (!t || seen.has(t)) continue;
      seen.add(t);
      out.push({ id: doc.id, token: t, platform: doc.data()?.platform });
    }
  } catch (e) {
    console.error("[fcmTokens] firestore list failed", { uid: userId, message: e.message });
  }

  return out;
}

/**
 * @param {string} uid
 * @param {string} token
 * @param {string} platform
 */
async function saveTokenForUser(uid, token, platform) {
  const userId = String(uid || "").trim();
  const t = String(token || "").trim();
  if (!userId || !t) return false;

  try {
    idb.upsertFcmDeviceToken(userId, t, platform);
  } catch (e) {
    console.error("[fcmTokens] sqlite save failed", { userId, message: e.message });
  }

  const admin = getFirebaseAdmin();
  if (!admin) return true;

  const id = tokenDocId(t);
  try {
    await admin
      .firestore()
      .collection("users")
      .doc(userId)
      .collection(COLLECTION)
      .doc(id)
      .set(
        {
          token: t,
          platform: platform || "unknown",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    return true;
  } catch (e) {
    console.error("[fcmTokens] firestore save failed", { userId, message: e.message });
    return true;
  }
}

/**
 * @param {string} uid
 * @param {string} token
 */
async function removeTokenForUser(uid, token) {
  const userId = String(uid || "").trim();
  const t = String(token || "").trim();
  if (!userId || !t) return;

  try {
    idb.removeFcmDeviceToken(userId, t);
  } catch (e) {
    console.error("[fcmTokens] sqlite remove failed", { userId, message: e.message });
  }

  const admin = getFirebaseAdmin();
  if (!admin) return;
  const id = tokenDocId(t);
  try {
    await admin.firestore().collection("users").doc(userId).collection(COLLECTION).doc(id).delete();
  } catch (e) {
    console.error("[fcmTokens] firestore remove failed", { userId, id, message: e.message });
  }
}

module.exports = {
  listTokensForUser,
  saveTokenForUser,
  removeTokenForUser,
  tokenDocId,
};
