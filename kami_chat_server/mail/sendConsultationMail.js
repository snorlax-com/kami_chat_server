"use strict";

const { Resend } = require("resend");
const { generateToken } = require("../token");
const { buildConsultationNotification } = require("./buildConsultationNotification");
const { buildAdminReplyUrl } = require("./buildAdminReplyUrl");
const types = require("../constants/consultationTypes");
const { withDisplayName } = require("./mailFrom");
const { resolveConsultationNotificationRecipients } = require("./resolveConsultationNotificationRecipients");

const RESEND_API_KEY = process.env.RESEND_API_KEY;
const MAIL_FROM = (process.env.MAIL_FROM || "").trim();
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
  const dev = (process.env.DEV_NOTIFICATION_EMAIL || "").trim();
  const admin = (process.env.ADMIN_EMAIL || "").trim();
  if (!dev && !admin) {
    throw new Error(
      "DEV_NOTIFICATION_EMAIL または ADMIN_EMAIL のいずれかを設定してください（開発者通知の主宛先）。"
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
 * @param {{
 *   consultationType?: string,
 *   messageId?: number,
 *   receivedAtMs?: number,
 *   debugSubjectPrefix?: string,
 * }} [meta]
 */
async function sendConsultationMail(chatId, message, userName, userId, meta = {}) {
  ensureMailConfig();
  /** [index.js] で解決済み。ここでは変更しない */
  const consultationType = types.normalizeConsultationType(meta.consultationType);
  const messageId = meta.messageId != null ? Number(meta.messageId) : 0;
  const receivedAtMs = meta.receivedAtMs != null ? Number(meta.receivedAtMs) : Date.now();
  const debugSubjectPrefix = meta.debugSubjectPrefix != null ? String(meta.debugSubjectPrefix) : "";

  let recipients;
  try {
    recipients = resolveConsultationNotificationRecipients(consultationType);
  } catch (e) {
    console.error("[sendConsultationMail] resolve_recipients_failed", {
      consultationType,
      error: e && e.message ? e.message : String(e),
    });
    throw e;
  }

  const { token, expires } = generateToken(chatId);
  const adminReplyUrl = buildAdminReplyUrl(BASE_URL, chatId, token, expires, consultationType);

  const built = buildConsultationNotification({
    consultationType,
    userName: userName || "ユーザー",
    userId: userId || "",
    chatId,
    messageId,
    receivedAtMs,
    message,
    adminReplyUrl,
  });

  /** @type {string} */
  let subjectPrefix;
  /** @type {string} */
  let fromName;
  /** @type {string} */
  let coreSubject;

  switch (consultationType) {
    case types.PRIORITY_GUIDANCE:
      subjectPrefix = "【至急相談】";
      fromName = "AuraFace 至急相談";
      coreSubject = types.SUBJECT_PRIORITY;
      break;
    case types.NORMAL:
    default:
      subjectPrefix = "【通常相談】";
      fromName = "AuraFace 通常相談";
      coreSubject = types.SUBJECT_NORMAL;
      break;
  }

  const subject = `${debugSubjectPrefix}${subjectPrefix} ${coreSubject}`;
  const from = withDisplayName(MAIL_FROM, fromName);
  const html = built.html;
  const text = built.text;

  console.log("[sendConsultationMail] pre_resend_send", {
    consultationType,
    resolvedRecipients: recipients,
    subject,
    fromName,
  });

  const headers =
    consultationType === types.PRIORITY_GUIDANCE
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

  const tags = [
    {
      name: "consultation_type",
      value: consultationType === types.PRIORITY_GUIDANCE ? "priority_guidance" : "normal",
    },
  ];

  const payload = {
    from,
    subject,
    html,
    text,
    headers,
    tags,
  };

  const resend = getResend();
  /** 至急で複数宛先のときは宛先ごとに 1 通ずつ送る（Gmail のスレッド統合・To 複数時の取りこぼし対策） */
  const sendOne = async (toSingle, index, total) => {
    const result = await resend.emails.send({
      ...payload,
      to: [toSingle],
    });
    if (result.error) {
      console.error("[sendConsultationMail] resend_error", {
        consultationType,
        resolvedRecipients: recipients,
        recipientIndex: index,
        recipientTotal: total,
        toThis: toSingle,
        resendError: result.error,
        resendResponse: result,
      });
      throw new Error(
        result.error.message || `Resend error: ${JSON.stringify(result.error)}`
      );
    }
    const mid = result.data && typeof result.data === "object" ? result.data.id : null;
    console.log("[sendConsultationMail] resend_ok", {
      consultationType,
      to: toSingle,
      recipientIndex: index,
      recipientTotal: total,
      mailId: mid,
    });
    return result;
  };

  let result;
  try {
    if (consultationType === types.PRIORITY_GUIDANCE && recipients.length > 1) {
      const mailIds = [];
      for (let i = 0; i < recipients.length; i++) {
        const r = await sendOne(recipients[i], i + 1, recipients.length);
        const id = r.data && typeof r.data === "object" ? r.data.id : null;
        if (id) mailIds.push(id);
        result = r;
      }
      return {
        ...(result.data && typeof result.data === "object" ? result.data : {}),
        id: mailIds[0] ?? result.data?.id,
        /** 至急複数宛のとき Resend が返した ID（順は recipients と一致） */
        debugMailIds: mailIds,
        subject,
        fromDisplay: fromName,
        consultationType,
        mailUrgent: true,
        debugMailTo: recipients,
      };
    }

    result = await resend.emails.send({
      ...payload,
      to: recipients,
    });
  } catch (err) {
    console.error("[sendConsultationMail] resend_exception", {
      consultationType,
      resolvedRecipients: recipients,
      error: err && err.message ? err.message : String(err),
    });
    throw err;
  }

  if (result.error) {
    console.error("[sendConsultationMail] resend_error", {
      consultationType,
      resolvedRecipients: recipients,
      resendError: result.error,
      resendResponse: result,
    });
    throw new Error(
      result.error.message || `Resend error: ${JSON.stringify(result.error)}`
    );
  }

  return {
    ...(result.data && typeof result.data === "object" ? result.data : {}),
    subject,
    fromDisplay: fromName,
    consultationType,
    mailUrgent: consultationType === types.PRIORITY_GUIDANCE,
    debugMailTo: recipients,
  };
}

module.exports = sendConsultationMail;
