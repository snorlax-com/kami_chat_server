"use strict";

const types = require("../constants/consultationTypes");

/**
 * EMERGENCY_NOTIFICATION_EMAIL 未設定時の至急追加宛先（要件どおり）。
 * 運用で変えたい場合は環境変数で上書き。
 */
const DEFAULT_EMERGENCY_NOTIFICATION_EMAIL = "emergencyauraface@gmail.com";

/**
 * 種別ごとの「主」送信先。
 * 後方互換: MAIL_TO_PRIORITY / MAIL_TO_NORMAL → DEV_NOTIFICATION_EMAIL → ADMIN_EMAIL
 * @param {string} consultationType
 * @returns {string}
 */
function resolvePrimaryRecipient(consultationType) {
  const dev = (process.env.DEV_NOTIFICATION_EMAIL || "").trim();
  const admin = (process.env.ADMIN_EMAIL || "").trim();
  const fallback = dev || admin;

  const ct = types.normalizeConsultationType(consultationType);
  if (ct === types.PRIORITY_GUIDANCE) {
    const p = (process.env.MAIL_TO_PRIORITY || "").trim();
    return p || fallback;
  }
  const n = (process.env.MAIL_TO_NORMAL || "").trim();
  return n || fallback;
}

/**
 * 至急（priority_guidance）時に主宛先に加える第2宛先。
 * @returns {string}
 */
function resolveEmergencyRecipient() {
  const e = (process.env.EMERGENCY_NOTIFICATION_EMAIL || "").trim();
  return e || DEFAULT_EMERGENCY_NOTIFICATION_EMAIL;
}

/**
 * Resend の `to` に渡す宛先一覧（重複除去済み）。
 * @param {string} consultationType
 * @returns {string[]}
 */
function resolveConsultationNotificationRecipients(consultationType) {
  const ct = types.normalizeConsultationType(consultationType);
  const primary = resolvePrimaryRecipient(ct);
  if (!primary) {
    throw new Error(
      "主通知先が未設定です。DEV_NOTIFICATION_EMAIL または ADMIN_EMAIL を設定してください（MAIL_TO_* 上書き時はそちら）。"
    );
  }

  if (ct === types.PRIORITY_GUIDANCE) {
    const emergency = resolveEmergencyRecipient();
    const combined = [primary, emergency].filter(Boolean);
    return [...new Set(combined)];
  }
  return [primary];
}

module.exports = {
  resolveConsultationNotificationRecipients,
  resolvePrimaryRecipient,
  resolveEmergencyRecipient,
  DEFAULT_EMERGENCY_NOTIFICATION_EMAIL,
};
