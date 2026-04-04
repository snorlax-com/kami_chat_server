"use strict";

const types = require("../../constants/consultationTypes");
const { escapeHtml, formatReceivedAtJst, messagePreview, gmailPreheader } = require("../utils");

/**
 * @param {{
 *   userName: string,
 *   userId: string,
 *   chatId: string,
 *   messageId: number,
 *   receivedAtMs: number,
 *   message: string,
 *   adminReplyUrl: string,
 * }} p
 */
function build(p) {
  const receivedAtJst = formatReceivedAtJst(p.receivedAtMs);
  const preview = messagePreview(p.message);
  const userLine = (p.userName || "").trim() || p.userId || "（未設定）";

  const text = `AuraFaceで新しい通常相談が届きました。

■ 種別
通常相談

■ consultationType
${types.NORMAL}

■ ユーザー
${userLine}
（userId: ${p.userId || "—"}）

■ 受信日時（日本時間）
${receivedAtJst}

■ チャットID
${p.chatId}

■ メッセージID
${p.messageId}

■ 内容（冒頭）
${preview}

■ 返信ページ
${p.adminReplyUrl}
`;

  const safe = {
    userLine: escapeHtml(userLine),
    userId: escapeHtml(p.userId || ""),
    chatId: escapeHtml(p.chatId),
    preview: escapeHtml(preview).replace(/\n/g, "<br/>"),
    url: p.adminReplyUrl,
    receivedAtJst: escapeHtml(receivedAtJst),
    messageId: escapeHtml(String(p.messageId)),
  };

  const preheader = gmailPreheader(
    "【通常相談】至急ではありません。時間のあるときにご確認ください。"
  );

  const html = `
    <div style="font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;font-size:15px;line-height:1.6;color:#1a1a1a;">
      ${preheader}
      <p>AuraFaceで新しい<strong>通常相談</strong>が届きました。</p>
      <table style="border-collapse:collapse;margin:12px 0;max-width:560px;">
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;white-space:nowrap;">■ 種別</td><td style="padding:6px 0;">通常相談</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ consultationType</td><td style="padding:6px 0;"><code>${types.NORMAL}</code></td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ ユーザー</td><td style="padding:6px 0;">${safe.userLine}<br/><span style="font-size:12px;color:#666;">userId: ${safe.userId || "—"}</span></td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ 受信日時（JST）</td><td style="padding:6px 0;">${safe.receivedAtJst}</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ チャットID</td><td style="padding:6px 0;"><code style="word-break:break-all;">${safe.chatId}</code></td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ メッセージID</td><td style="padding:6px 0;">${safe.messageId}</td></tr>
      </table>
      <p style="margin:16px 0 8px;font-weight:600;">■ 内容（冒頭）</p>
      <div style="white-space:pre-wrap;padding:14px;border:1px solid #e5e7eb;border-radius:10px;background:#fafafa;">${safe.preview}</div>
      <p style="margin-top:20px;">
        <a href="${safe.url}" style="display:inline-block;padding:12px 18px;background:#374151;color:#fff;border-radius:10px;text-decoration:none;font-weight:600;">返信ページを開く</a>
      </p>
      <p style="color:#6b7280;font-size:12px;margin-top:16px;">※リンクは期限付きです。共有しないでください。<br/>返信URL: <a href="${safe.url}" style="color:#4b5563;word-break:break-all;">${escapeHtml(p.adminReplyUrl)}</a></p>
    </div>
  `;

  return { subject: types.SUBJECT_NORMAL, html, text };
}

module.exports = { build };
