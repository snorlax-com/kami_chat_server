"use strict";

const types = require("../constants/consultationTypes");
const { build: buildNormal } = require("./templates/normalConsultation");
const { build: buildPriority } = require("./templates/priorityGuidance");

/**
 * 再通知・別チャネル追加時はここで分岐を増やしやすい構造
 * @param {{
 *   consultationType: string,
 *   userName: string,
 *   userId: string,
 *   chatId: string,
 *   messageId: number,
 *   receivedAtMs: number,
 *   message: string,
 *   adminReplyUrl: string,
 * }} input
 * @returns {{ subject: string, html: string, text: string }}
 */
function buildConsultationNotification(input) {
  const ct = types.normalizeConsultationType(input.consultationType);
  const payload = {
    userName: input.userName || "ユーザー",
    userId: input.userId || "",
    chatId: input.chatId,
    messageId: input.messageId,
    receivedAtMs: input.receivedAtMs,
    message: input.message,
    adminReplyUrl: input.adminReplyUrl,
  };

  if (ct === types.PRIORITY_GUIDANCE) {
    return buildPriority(payload);
  }
  return buildNormal(payload);
}

module.exports = { buildConsultationNotification };
