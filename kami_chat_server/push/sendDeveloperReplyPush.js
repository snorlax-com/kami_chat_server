"use strict";

const idb = require("../identityDb");
const { getFirebaseAdmin, isFirebaseConfigured } = require("../firebaseVerify");
const fcmTokens = require("./fcmTokens");

const TITLE = "AuraFaceから新しい導きが届きました";
const BODY = "創設者（占い師）から返信が届いています。タップして確認してください。";

/**
 * 創設者（占い師）返信時にユーザー端末へ FCM を送信（ユーザー送信には呼ばない）。
 *
 * @param {{ chatId: string, messageId: number|string, role?: string }} params
 */
async function sendDeveloperReplyPush({ chatId, messageId, role, createdAt }) {
  if (role && role !== "dev") {
    return { skipped: true, reason: "not_dev_role" };
  }
  const cid = String(chatId || "").trim();
  const mid = Number(messageId);
  if (!cid || Number.isNaN(mid)) {
    console.warn("[push] skip invalid ids", { chatId: cid, messageId });
    return { skipped: true, reason: "invalid_ids" };
  }

  if (idb.wasPushNotificationSent(cid, mid)) {
    console.log("[push] skip duplicate", { chatId: cid, messageId: mid });
    return { skipped: true, reason: "duplicate" };
  }

  if (!isFirebaseConfigured()) {
    console.warn("[push] Firebase Admin not configured — cannot send", { chatId: cid });
    return { skipped: true, reason: "firebase_not_configured" };
  }

  const admin = getFirebaseAdmin();
  if (!admin) {
    return { skipped: true, reason: "firebase_admin_unavailable" };
  }

  const userId = idb.resolveUserIdForChat(cid);
  if (!userId) {
    console.warn("[push] no userId for chatId", { chatId: cid });
    return { skipped: true, reason: "no_user_for_chat" };
  }

  const tokenRows = await fcmTokens.listTokensForUser(userId);
  const tokens = tokenRows.map((r) => r.token).filter(Boolean);

  if (tokens.length === 0) {
    console.warn("[push] no FCM tokens", { userId, chatId: cid });
    return { skipped: true, reason: "no_tokens", userId };
  }

  const data = {
    type: "dev_reply",
    chatId: cid,
    messageId: String(mid),
  };
  const createdAtMs = Number(createdAt);
  if (!Number.isNaN(createdAtMs) && createdAtMs > 0) {
    data.createdAt = String(createdAtMs);
  }

  let successCount = 0;
  let failureCount = 0;
  const invalidTokens = [];

  try {
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: TITLE, body: BODY },
      data,
      android: {
        priority: "high",
        notification: {
          channelId: "auraface_dev_reply",
          title: TITLE,
          body: BODY,
        },
      },
      apns: {
        payload: {
          aps: {
            alert: { title: TITLE, body: BODY },
            sound: "default",
            badge: 1,
          },
        },
      },
    });

    successCount = res.successCount;
    failureCount = res.failureCount;
    res.responses.forEach((r, i) => {
      if (r.success) return;
      const code = r.error?.code || "";
      const token = tokens[i];
      console.error("[push] send failed", {
        chatId: cid,
        messageId: mid,
        userId,
        tokenSuffix: token ? token.slice(-8) : null,
        code,
        message: r.error?.message,
      });
      if (
        code === "messaging/invalid-registration-token" ||
        code === "messaging/registration-token-not-registered"
      ) {
        invalidTokens.push(token);
      }
    });
  } catch (e) {
    console.error("[push] multicast exception", {
      chatId: cid,
      messageId: mid,
      userId,
      message: e.message,
      stack: e.stack,
    });
    return { ok: false, error: e.message, userId, chatId: cid, messageId: mid };
  }

  for (const t of invalidTokens) {
    await fcmTokens.removeTokenForUser(userId, t);
  }

  if (successCount > 0) {
    idb.markPushNotificationSent(cid, mid);
  }

  console.log("[push] dev_reply sent", {
    chatId: cid,
    messageId: mid,
    userId,
    tokens: tokens.length,
    successCount,
    failureCount,
    invalidRemoved: invalidTokens.length,
  });

  return {
    ok: successCount > 0,
    userId,
    chatId: cid,
    messageId: mid,
    successCount,
    failureCount,
    invalidRemoved: invalidTokens.length,
  };
}

module.exports = { sendDeveloperReplyPush, TITLE, BODY };
