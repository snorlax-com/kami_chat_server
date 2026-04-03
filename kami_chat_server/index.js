require("dotenv").config();
const express = require("express");
const cors = require("cors");
const sendMail = require("./mail");
const { verifyToken } = require("./token");

const app = express();
const PORT = process.env.PORT || 3000;

// メモリ保存: chatId -> [{ id, role, text, createdAt }, ...]
const store = new Map();
let nextId = 1;

app.use(cors());
app.use(express.json({ limit: "200kb" }));
app.use(express.urlencoded({ extended: true }));

function escapeHtml(str = "") {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

// 疎通確認用（E2E / 監視ツール向けプレーンテキスト）
app.get("/", (req, res) => {
  res.type("text/plain; charset=utf-8").send("OK");
});

app.get("/health", (req, res) => {
  res.json({ ok: true });
});

// --- POST /api/chat/send（保存 + Resend で開発者Gmail。メール失敗時も 200 + mailSent:false）
app.post("/api/chat/send", async (req, res) => {
  try {
    const { userId, chatId, message, userName } = req.body || {};
    const text = message != null ? String(message).trim() : "";
    const cid = chatId || "default";
    if (!text) {
      return res.status(400).json({ status: "error", message: "message required" });
    }
    if (!store.has(cid)) store.set(cid, []);
    const createdAt = Date.now();
    const id = nextId++;
    store.get(cid).push({ id, role: "user", text, createdAt });
    console.log("[chat/send] received", { userId, chatId: cid, messageId: id, text: text.slice(0, 80) });

    let mailResult = null;
    let mailError = null;
    try {
      mailResult = await sendMail(cid, text, userName || "ユーザー", userId || "");
      console.log("[chat/send] mail_sent resend_ok", {
        messageId: id,
        to: process.env.ADMIN_EMAIL,
        mailId: mailResult?.id,
      });
    } catch (err) {
      mailError = err;
      console.error("[chat/send] mail", err.message);
    }

    // メールまで成功した場合は status: "ok"（E2E 期待値と一致）
    return res.json({
      status: mailError ? "saved_but_mail_failed" : "ok",
      success: true,
      chatId: cid,
      messageId: id,
      saved: true,
      mailSent: !mailError,
      mailId: mailResult?.id ?? null,
      error: mailError ? mailError.message : null,
    });
  } catch (err) {
    console.error("[chat/send] error", err);
    return res.status(500).json({
      success: false,
      status: "error",
      message: "internal server error",
    });
  }
});

app.get("/api/chat/thread", (req, res) => {
  const chatId = req.query.chatId || "default";
  const list = store.get(chatId) || [];
  const since = req.query.since ? Number(req.query.since) : null;
  const messages =
    since != null && !Number.isNaN(since)
      ? list.filter((m) => m.createdAt >= since)
      : [...list];
  messages.sort((a, b) => a.createdAt - b.createdAt);
  res.json({ status: "ok", chatId, messages });
});

// テスト用: 開発者返信を追加
app.post("/api/chat/dev-reply", (req, res) => {
  const { chatId, text } = req.body || {};
  const cid = chatId || "default";
  const msg = text != null ? String(text).trim() : "";
  if (!msg) {
    return res.status(400).json({ status: "error", message: "text required" });
  }
  if (!store.has(cid)) store.set(cid, []);
  const id = nextId++;
  const createdAt = Date.now();
  store.get(cid).push({ id, role: "dev", text: msg, createdAt });
  console.log("[chat/dev-reply]", { chatId: cid, text: msg });
  res.json({ status: "received", chatId: cid, messageId: id });
});

// --- GET /admin/reply（メモリストア + トークン）
app.get("/admin/reply", (req, res) => {
  try {
    const { chatId, token, expires } = req.query;

    if (!verifyToken(chatId, token, expires)) {
      console.warn("[admin/reply GET] token verification failed", { chatId });
      res.setHeader("Content-Type", "text/html; charset=utf-8");
      return res.status(403).send("invalid or expired token");
    }
    console.log("[admin/reply GET] token ok", { chatId });

    const rows = store.get(chatId) || [];
    const sorted = [...rows].sort((a, b) => a.createdAt - b.createdAt);

    let html = `
      <!DOCTYPE html>
      <html>
      <head><meta charset="utf-8" /><title>返信 - AuraFace</title>
      <style>
        body { font-family: sans-serif; max-width: 760px; margin: 24px auto; padding: 0 16px; }
        .msg { border: 1px solid #ddd; border-radius: 8px; padding: 12px; margin-bottom: 10px; }
        .user { background: #f7fbff; }
        .dev { background: #f7fff7; }
        textarea { width: 100%; min-height: 120px; box-sizing: border-box; }
        button { padding: 10px 16px; margin-top: 12px; }
        .meta { color: #666; font-size: 12px; }
      </style>
      </head>
      <body>
        <h2>チャット履歴</h2>
        <p class="meta">chatId: ${escapeHtml(chatId)}</p>
    `;

    for (const r of sorted) {
      const who = r.role === "dev" ? "開発者" : "ユーザー";
      html += `
        <div class="msg ${escapeHtml(r.role)}">
          <div><b>${escapeHtml(who)}</b></div>
          <div style="white-space:pre-wrap;">${escapeHtml(r.text)}</div>
          <div class="meta">${new Date(r.createdAt).toLocaleString("ja-JP")}</div>
        </div>
      `;
    }

    html += `
        <hr />
        <h3>返信する</h3>
        <form method="POST" action="/admin/reply">
          <input type="hidden" name="chatId" value="${escapeHtml(chatId)}" />
          <input type="hidden" name="token" value="${escapeHtml(token)}" />
          <input type="hidden" name="expires" value="${escapeHtml(String(expires))}" />
          <textarea name="message" required placeholder="返信内容"></textarea>
          <br />
          <button type="submit">返信送信</button>
        </form>
      </body>
      </html>
    `;

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    return res.send(html);
  } catch (err) {
    console.error("[admin/reply GET]", err);
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    return res.status(500).send("internal server error");
  }
});

// --- POST /admin/reply
app.post("/admin/reply", (req, res) => {
  try {
    const { chatId, token, expires, message } = req.body || {};

    if (!verifyToken(chatId, token, expires)) {
      res.setHeader("Content-Type", "text/html; charset=utf-8");
      return res.status(403).send("invalid or expired token");
    }

    const text = String(message || "").trim();
    if (!text) {
      res.setHeader("Content-Type", "text/html; charset=utf-8");
      return res.status(400).send("message is required");
    }

    if (!store.has(chatId)) store.set(chatId, []);
    const id = nextId++;
    const createdAt = Date.now();
    store.get(chatId).push({ id, role: "dev", text, createdAt });

    console.log("[admin/reply POST] saved dev message", { chatId, len: text.length });
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    return res.send(`
      <!DOCTYPE html>
      <html><head><meta charset="utf-8" /></head>
      <body>
        <p>返信しました。</p>
        <p>返信を保存しました。</p>
        <p><a href="/admin/reply?chatId=${encodeURIComponent(chatId)}&token=${encodeURIComponent(token)}&expires=${encodeURIComponent(expires)}">履歴に戻る</a></p>
      </body>
      </html>
    `);
  } catch (err) {
    console.error("[admin/reply POST]", err);
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    return res.status(500).send("internal server error");
  }
});

function logMailEnvWarning() {
  const adminEmail = (process.env.ADMIN_EMAIL || "").trim();
  const resendKey = process.env.RESEND_API_KEY;
  const mailFrom = (process.env.MAIL_FROM || "").trim();
  const baseUrl = (process.env.BASE_URL || "").trim();
  if (!adminEmail || !resendKey || String(resendKey).trim() === "" || !mailFrom || !baseUrl) {
    console.warn(
      "[警告] Gmail通知に必要な環境変数が未設定です。POST /api/chat/send は成功しますが mailSent=false になります。\n" +
        "        Render に設定: RESEND_API_KEY, ADMIN_EMAIL, MAIL_FROM, BASE_URL（サービスURL）, TOKEN_SECRET（本番はランダム長文）"
    );
  }
}

app.listen(PORT, () => {
  console.log(`Kami chat server listening on port ${PORT}`);
  logMailEnvWarning();
});
