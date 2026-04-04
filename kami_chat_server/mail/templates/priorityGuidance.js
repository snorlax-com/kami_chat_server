"use strict";

const types = require("../../constants/consultationTypes");
const { escapeHtml, formatReceivedAtJst, messagePreview } = require("../utils");

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
  const tag = types.TAG_PRIORITY;

  const text = `【優先導き】
2時間以内対応の対象相談が届きました。
優先して確認してください。

■ 種別
優先導き

■ consultationType
${types.PRIORITY_GUIDANCE}

■ 対応目安
2時間以内（受付時刻: ${receivedAtJst} を基準に運用してください）

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

■ 識別子
${tag}
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

  const html = `
    <div style="font-family:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;font-size:15px;line-height:1.6;color:#1a1a1a;">
      <div style="background:linear-gradient(135deg,#fef3c7 0%,#fde68a 100%);border:1px solid #f59e0b;border-radius:12px;padding:16px 18px;margin-bottom:18px;">
        <p style="margin:0 0 8px;font-size:18px;font-weight:700;color:#92400e;">【優先導き】</p>
        <p style="margin:0;font-size:16px;font-weight:600;color:#b45309;">2時間以内対応の対象相談です。優先して確認してください。</p>
      </div>
      <table style="border-collapse:collapse;margin:12px 0;max-width:560px;">
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;white-space:nowrap;">■ 種別</td><td style="padding:6px 0;"><strong>優先導き</strong></td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ consultationType</td><td style="padding:6px 0;"><code>${types.PRIORITY_GUIDANCE}</code></td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ 対応目安</td><td style="padding:6px 0;"><strong>2時間以内</strong>（受付: ${safe.receivedAtJst} JST）</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ ユーザー</td><td style="padding:6px 0;">${safe.userLine}<br/><span style="font-size:12px;color:#666;">userId: ${safe.userId || "—"}</span></td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ 受信日時（JST）</td><td style="padding:6px 0;">${safe.receivedAtJst}</td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ チャットID</td><td style="padding:6px 0;"><code style="word-break:break-all;">${safe.chatId}</code></td></tr>
        <tr><td style="padding:6px 12px 6px 0;color:#555;vertical-align:top;">■ メッセージID</td><td style="padding:6px 0;">${safe.messageId}</td></tr>
      </table>
      <p style="margin:16px 0 8px;font-weight:600;">■ 内容（冒頭）</p>
      <div style="white-space:pre-wrap;padding:14px;border:1px solid #fcd34d;border-radius:10px;background:#fffbeb;">${safe.preview}</div>
      <p style="margin-top:20px;">
        <a href="${safe.url}" style="display:inline-block;padding:12px 20px;background:#b45309;color:#fff;border-radius:10px;text-decoration:none;font-weight:700;">返信ページを開く（優先）</a>
      </p>
      <p style="margin-top:16px;font-size:13px;color:#92400e;"><strong>■ 識別子</strong> <code>${tag}</code></p>
      <p style="color:#6b7280;font-size:12px;margin-top:16px;">※リンクは期限付きです。共有しないでください。<br/>返信URL: <a href="${safe.url}" style="color:#4b5563;word-break:break-all;">${escapeHtml(p.adminReplyUrl)}</a></p>
    </div>
  `;

  return { subject: types.SUBJECT_PRIORITY, html, text };
}

module.exports = { build };
