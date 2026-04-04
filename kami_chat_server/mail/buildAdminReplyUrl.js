"use strict";

const { normalizeConsultationType } = require("../constants/consultationTypes");

/**
 * 既存の署名付きURLに、認証に不要な consultationType のみクエリ追加（verifyToken は変更なし）
 * @param {string} baseUrl 末尾スラッシュなし
 */
function buildAdminReplyUrl(baseUrl, chatId, token, expires, consultationTypeRaw) {
  const ct = normalizeConsultationType(consultationTypeRaw);
  const u = new URL(`${baseUrl.replace(/\/$/, "")}/admin/reply`);
  u.searchParams.set("chatId", chatId);
  u.searchParams.set("token", token);
  u.searchParams.set("expires", String(expires));
  u.searchParams.set("consultationType", ct);
  return u.toString();
}

module.exports = { buildAdminReplyUrl };
