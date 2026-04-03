const { Resend } = require("resend");
const { generateToken } = require("./token");

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
      "MAIL_FROM が設定されていません。Resend で検証済みの送信元アドレスを MAIL_FROM に設定してください。"
    );
  }
  if (!BASE_URL) {
    throw new Error(
      "BASE_URL が設定されていません。Render のサービスURL（例: https://kami-chat-server.onrender.com）を BASE_URL に設定してください（返信リンク用）。"
    );
  }
}

function escapeHtml(str = "") {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

async function sendMail(chatId, message, userName = "ユーザー", userId = "") {
  ensureMailConfig();
  const { token, expires } = generateToken(chatId);

  const url =
    `${BASE_URL}/admin/reply` +
    `?chatId=${encodeURIComponent(chatId)}` +
    `&token=${encodeURIComponent(token)}` +
    `&expires=${encodeURIComponent(expires)}`;

  const safeMessage = escapeHtml(message);

  const result = await getResend().emails.send({
    from: MAIL_FROM,
    to: [ADMIN_EMAIL],
    subject: `[AuraFace相談] ${escapeHtml(userName || "ユーザー")} (chatId=${chatId})`,
    html: `
    <div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;">
      <h2>新しい相談が届きました</h2>
      <p><b>ユーザー名:</b> ${escapeHtml(userName || "")}</p>
      <p><b>userId:</b> ${escapeHtml(userId)}</p>
      <p><b>chatId:</b> ${escapeHtml(chatId)}</p>
      <p><b>本文:</b></p>
      <div style="white-space:pre-wrap;padding:12px;border:1px solid #ddd;border-radius:10px;">${safeMessage}</div>
      <p style="margin-top:18px;">
        <a href="${url}" style="display:inline-block;padding:10px 14px;background:#111;color:#fff;border-radius:10px;text-decoration:none;">
          返信ページを開く
        </a>
      </p>
      <p style="color:#777;font-size:12px;">※リンクは期限付きです。共有しないでください。</p>
    </div>
  `,
  });

  if (result.error) {
    throw new Error(
      result.error.message || `Resend error: ${JSON.stringify(result.error)}`
    );
  }

  return result.data;
}

module.exports = sendMail;
