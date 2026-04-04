"use strict";

const { Resend } = require("resend");
const { generateToken } = require("../token");
const { buildConsultationNotification } = require("./buildConsultationNotification");
const { buildAdminReplyUrl } = require("./buildAdminReplyUrl");
const types = require("../constants/consultationTypes");
const { withDisplayName } = require("./mailFrom");

const RESEND_API_KEY = process.env.RESEND_API_KEY;
const MAIL_FROM = (process.env.MAIL_FROM || "").trim();
const ADMIN_EMAIL = (process.env.ADMIN_EMAIL || "").trim();
const BASE_URL = (process.env.BASE_URL || "").replace(/\/$/, "");

function getResend() {
  return new Resend(RESEND_API_KEY);
}

function ensureMailConfig() {
  if (!RESEND_API_KEY || String(RESEND_API_KEY).trim() === "") {
    throw new Error(
      "RESEND_API_KEY が設定されていません。Render の Environment に RESEND_API_KEY を設定してください。"
    );
  }
  if (!ADMIN_EMAIL) {
    throw new Error(
      "ADMIN_EMAIL が設定されていません。Render に ADMIN_EMAIL（開発者Gmail）を設定してください。"
    );
  }
  if (!MAIL_FROM) {
    throw new Error(
      "MAIL_FROM が設定されていません。Resend で検証済みの送信元を MAIL_FROM に設定してください。"
    );
  }
  if (!BASE_URL) {
    throw new Error(
      "BASE_URL が設定されていません。返信リンク用にサービスURLを設定してください。"
    );
  }
}

/**
 * @param {string} chatId
 * @param {string} message
 * @param {string} [userName]
 * @param {string} [userId]
 * @param {{ consultationType?: string, messageId?: number, receivedAtMs?: number }} [meta]
 */
async function sendConsultationMail(chatId, message, userName, userId, meta = {}) {
  ensureMailConfig();
  const consultationType = types.normalizeConsultationType(meta.consultationType);
  const messageId = meta.messageId != null ? Number(meta.messageId) : 0;
  const receivedAtMs = meta.receivedAtMs != null ? Number(meta.receivedAtMs) : Date.now();

  const { token, expires } = generateToken(chatId);
  const adminReplyUrl = buildAdminReplyUrl(BASE_URL, chatId, token, expires, consultationType);

  const { subject, html, text } = buildConsultationNotification({
    consultationType,
    userName: userName || "ユーザー",
    userId: userId || "",
    chatId,
    messageId,
    receivedAtMs,
    message,
    adminReplyUrl,
  });

  const isPriority = consultationType === types.PRIORITY_GUIDANCE;
  const fromDisplay = isPriority ? types.FROM_DISPLAY_PRIORITY : types.FROM_DISPLAY_NORMAL;
  const from = withDisplayName(MAIL_FROM, fromDisplay);

  if (isPriority) {
    console.log("[sendConsultationMail][URGENT]", { subject, fromDisplay, consultationType });
  } else {
    console.log("[sendConsultationMail][NORMAL]", { subject, fromDisplay, consultationType });
  }

  /**
   * Gmail の自動「重要」は送信側では保証できないが、一覧・通知・フィルタで差を付けやすいヘッダーを付与。
   * List-Id は Gmail 検索 `list:…` やフィルタ条件に使える。
   */
  const headers = isPriority
    ? {
        Importance: "high",
        Priority: "urgent",
        "X-Priority": "1",
        "X-MSMail-Priority": "High",
        "List-Id": "<fortune-urgent.consultations.auraface>",
        "X-AuraFace-Consultation": "priority_guidance",
        "X-AuraFace-Urgency": "fortune-consultation-urgent",
      }
    : {
        Importance: "normal",
        Priority: "non-urgent",
        "X-Priority": "3",
        "X-MSMail-Priority": "Normal",
        "List-Id": "<normal.consultations.auraface>",
        "X-AuraFace-Consultation": "normal",
      };

  const result = await getResend().emails.send({
    from,
    to: [ADMIN_EMAIL],
    subject,
    html,
    text,
    headers,
    tags: [{ name: "consultation_type", value: isPriority ? "priority_guidance" : "normal" }],
  });

  if (result.error) {
    throw new Error(
      result.error.message || `Resend error: ${JSON.stringify(result.error)}`
    );
  }

  return {
    ...(result.data && typeof result.data === "object" ? result.data : {}),
    subject,
    fromDisplay,
    consultationType,
    mailUrgent: isPriority,
  };
}

module.exports = sendConsultationMail;
