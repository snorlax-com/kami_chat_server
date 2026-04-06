import "dotenv/config";
import express from "express";
import cors from "cors";
import rateLimit from "express-rate-limit";
import { readFileSync } from "fs";
import { z } from "zod";
import { Resend } from "resend";
import { initDb, upsertThread, insertMessage, getThreadMessages, updateMessageEmailStatus } from "./db.js";
import { signToken, verifyToken } from "./token.js";

function requireEnv(name) {
  const v = process.env[name];
  if (!v || !String(v).trim()) {
    throw new Error(`Missing required env: ${name}`);
  }
  return String(v).trim();
}

const app = express();
app.use(express.json({ limit: "200kb" }));

initDb();

const PORT = Number(process.env.PORT || 3000);
/** メールの「返信ページを開く」リンクのベース。.base-url があれば優先（ngrok 用） */
function getBaseUrl() {
  try {
    const u = readFileSync(".base-url", "utf8").trim();
    if (u) return u.replace(/\/$/, "");
  } catch (_) {}
  return process.env.BASE_URL || `http://127.0.0.1:${PORT}`;
}

function getBaseUrlSafe() {
  try {
    return getBaseUrl();
  } catch (_) {
    return null;
  }
}

const RESEND_API_KEY = requireEnv("RESEND_API_KEY");
const DEV_EMAIL = requireEnv("DEV_EMAIL");
const SIGNING_SECRET = requireEnv("SIGNING_SECRET");
requireEnv("BASE_URL");
const MAIL_FROM =
  process.env.MAIL_FROM && String(process.env.MAIL_FROM).trim()
    ? String(process.env.MAIL_FROM).trim()
    : "no-reply@mail.jyujyu-life.com";
if (!process.env.MAIL_FROM || !String(process.env.MAIL_FROM).trim()) {
  console.warn("MAIL_FROM not set in env, using default. Set MAIL_FROM for production.");
}

const resend = new Resend(RESEND_API_KEY);

const allowed = (process.env.ALLOWED_ORIGINS || "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

app.use(
  cors({
    origin: function (origin, cb) {
      if (!origin) return cb(null, true);
      if (allowed.length === 0) return cb(new Error("CORS blocked (no ALLOWED_ORIGINS set)"));
      if (allowed.includes(origin)) return cb(null, true);
      return cb(new Error("CORS blocked"));
    },
  })
);

app.use(
  rateLimit({
    windowMs: 60_000,
    limit: process.env.RATE_LIMIT_MAX ? Number(process.env.RATE_LIMIT_MAX) : 20,
    standardHeaders: true,
    legacyHeaders: false,
  })
);

function escapeHtml(str) {
  return String(str)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function renderReplyPage({ chatId, messages, token, userName }) {
  const items = messages
    .map((m) => {
      const who = m.role === "dev" ? "開発者" : userName || "ユーザー";
      return `
      <div style="margin:8px 0;padding:10px;border:1px solid #ddd;border-radius:8px;">
        <div style="font-size:12px;color:#666;">${escapeHtml(who)} / ${new Date(m.createdAt).toLocaleString()}</div>
        <div style="white-space:pre-wrap;margin-top:6px;">${escapeHtml(m.text)}</div>
      </div>
    `;
    })
    .join("");

  return `
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>AuraFace 返信</title>
</head>
<body style="font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:860px;margin:0 auto;padding:16px;">
  <h2>返信ページ</h2>
  <div style="color:#666;margin-bottom:10px;">chatId: ${escapeHtml(chatId)}</div>

  <h3>スレッド</h3>
  <div>${items || "<div style='color:#888'>メッセージがありません</div>"}</div>

  <h3>返信</h3>
  <form method="POST" action="/admin/reply">
    <input type="hidden" name="token" value="${escapeHtml(token)}"/>
    <textarea name="replyText" rows="6" style="width:100%;padding:10px;border-radius:8px;border:1px solid #ccc;" placeholder="ここに返信を入力"></textarea>
    <div style="margin-top:10px;">
      <button type="submit" style="padding:10px 14px;border-radius:10px;border:0;background:#111;color:#fff;cursor:pointer;">送信</button>
    </div>
  </form>

  <div style="margin-top:18px;color:#888;font-size:12px;">
    ※このページURLは期限付きです。共有しないでください。
  </div>
</body>
</html>`;
}

app.use(express.urlencoded({ extended: true }));

app.get("/health", (req, res) => res.json({ ok: true }));

app.get("/health/details", (req, res) => {
  res.json({
    ok: true,
    env: {
      hasResendApiKey: Boolean(process.env.RESEND_API_KEY),
      hasDevEmail: Boolean(process.env.DEV_EMAIL),
      hasSigningSecret: Boolean(process.env.SIGNING_SECRET),
      hasBaseUrl: Boolean(getBaseUrlSafe()),
      hasMailFrom: Boolean(process.env.MAIL_FROM),
    },
    baseUrl: getBaseUrlSafe(),
    now: Date.now(),
  });
});

const SendSchema = z.object({
  userId: z.string().min(1).max(100),
  chatId: z.string().min(1).max(200),
  userEmail: z.string().email().optional().or(z.literal("")),
  userName: z.string().min(1).max(100).optional().or(z.literal("")),
  message: z.string().min(1).max(5000),
  consultationType: z.string().max(80).optional(),
  consultation_type: z.string().max(80).optional(),
  urgent: z.union([z.boolean(), z.number(), z.string()]).optional(),
  consultationPriority: z.union([z.number(), z.string()]).optional(),
  consultation_priority: z.union([z.number(), z.string()]).optional(),
});

const SUBJECT_PRIORITY =
  "【至急占い・緊急】2時間以内要対応｜優先導き｜AuraFace [PRIORITY_GUIDANCE]";
const FROM_DISPLAY_PRIORITY = "至急占い相談｜AuraFace【優先導き】";
const FROM_DISPLAY_NORMAL = "AuraFace｜通常相談";

const EMBEDDED_TIER_RE = /\r?\n\r?\n__AURAFACE_SEND_TIER__:(priority_guidance|normal)__\s*$/;

function extractEmbeddedConsultationTier(raw) {
  const s = raw != null ? String(raw) : "";
  const m = s.match(EMBEDDED_TIER_RE);
  if (!m) return { cleanText: s, embeddedTierRaw: null };
  return { cleanText: s.replace(EMBEDDED_TIER_RE, "").trimEnd(), embeddedTierRaw: m[1] };
}

function withDisplayName(mailFrom, displayName) {
  const s = String(mailFrom).trim();
  const open = s.lastIndexOf("<");
  const close = s.lastIndexOf(">");
  if (open >= 0 && close > open) {
    const addr = s.slice(open + 1, close).trim();
    return `${displayName} <${addr}>`;
  }
  if (/^[^\s<>]+@[^\s<>]+$/.test(s)) {
    return `${displayName} <${s}>`;
  }
  return s;
}

/** @returns {"priority_guidance"|"normal"} */
function resolveConsultationType(parsed, headerCtRaw, embeddedTierRaw) {
  const fromBody = parsed.consultationType ?? parsed.consultation_type;
  if (fromBody != null && String(fromBody).trim() !== "") {
    const s = String(fromBody).trim().toLowerCase().replace(/-/g, "_");
    if (
      s === "priority_guidance" ||
      s === "priorityguidance" ||
      s === "urgent" ||
      s === "emergency" ||
      s === "priority"
    ) {
      return "priority_guidance";
    }
    return "normal";
  }
  if (embeddedTierRaw != null && String(embeddedTierRaw).trim() !== "") {
    const e = String(embeddedTierRaw).trim().toLowerCase();
    if (e === "priority_guidance") return "priority_guidance";
    if (e === "normal") return "normal";
  }
  const h = headerCtRaw != null ? String(headerCtRaw).trim() : "";
  if (h) {
    const s = h.toLowerCase().replace(/-/g, "_");
    if (
      s === "priority_guidance" ||
      s === "priorityguidance" ||
      s === "urgent" ||
      s === "emergency" ||
      s === "priority"
    ) {
      return "priority_guidance";
    }
    if (s === "normal") return "normal";
  }
  const tier = parsed.consultationPriority ?? parsed.consultation_priority;
  if (tier === 2 || tier === "2") return "priority_guidance";
  const u = parsed.urgent;
  if (u === true || u === 1 || u === "1") return "priority_guidance";
  if (typeof u === "string" && ["true", "yes"].includes(u.trim().toLowerCase())) {
    return "priority_guidance";
  }
  return "normal";
}

app.post("/api/chat/send", async (req, res) => {
  try {
    const body = SendSchema.parse(req.body);
    const { cleanText: messageClean, embeddedTierRaw } = extractEmbeddedConsultationTier(body.message);
    const headerCt = String(
      req.get("x-auraface-consultation-type") || req.get("X-AuraFace-Consultation-Type") || ""
    ).trim();
    const consultationType = resolveConsultationType(body, headerCt || null, embeddedTierRaw);
    const isPriority = consultationType === "priority_guidance";
    const messageForStore = messageClean.trim() === "" ? "(本文なし)" : messageClean;

    console.log(JSON.stringify({
      event: "chat_send_request",
      chatId: body.chatId,
      userId: body.userId,
      hasUserEmail: Boolean(body.userEmail),
      consultationType,
      embeddedTier: embeddedTierRaw,
      headerConsultationType: headerCt || null,
      at: new Date().toISOString(),
    }));

    await upsertThread({
      chatId: body.chatId,
      userId: body.userId,
      userEmail: body.userEmail || null,
      userName: body.userName || null,
    });

    const msg = await insertMessage({
      chatId: body.chatId,
      role: "user",
      text: messageForStore,
    });

    const exp = Date.now() + 7 * 24 * 60 * 60 * 1000;
    const token = signToken({ chatId: body.chatId, exp }, SIGNING_SECRET);

    const baseUrl = getBaseUrl();
    const replyUrl = `${baseUrl}/admin/reply?token=${encodeURIComponent(token)}`;

    const subject = isPriority
      ? SUBJECT_PRIORITY
      : `[AuraFace相談] ${body.userName || "ユーザー"} (chatId=${body.chatId})`;
    const priorityBanner = isPriority
      ? `<div style="margin-bottom:14px;padding:12px 14px;background:#fff3e0;border:2px solid #e65100;border-radius:10px;font-weight:600;color:#bf360c;">【至急・優先導き】2時間以内対応の相談です（consultationType: priority_guidance）</div>`
      : "";
    const html = `
      <div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;">
        ${priorityBanner}
        <h2>新しい相談が届きました</h2>
        <p><b>種別:</b> ${escapeHtml(consultationType)}</p>
        <p><b>ユーザー名:</b> ${escapeHtml(body.userName || "")}</p>
        <p><b>userId:</b> ${escapeHtml(body.userId)}</p>
        <p><b>chatId:</b> ${escapeHtml(body.chatId)}</p>
        <p><b>本文:</b></p>
        <div style="white-space:pre-wrap;padding:12px;border:1px solid #ddd;border-radius:10px;">${escapeHtml(messageForStore)}</div>
        <p style="margin-top:18px;">
          <a href="${replyUrl}" style="display:inline-block;padding:10px 14px;background:#111;color:#fff;border-radius:10px;text-decoration:none;">
            返信ページを開く
          </a>
        </p>
        <p style="color:#777;font-size:12px;">※リンクは期限付きです。共有しないでください。</p>
      </div>
    `;

    const from = withDisplayName(MAIL_FROM, isPriority ? FROM_DISPLAY_PRIORITY : FROM_DISPLAY_NORMAL);
    const headers = isPriority
      ? {
          Importance: "high",
          Priority: "urgent",
          "X-Priority": "1",
          "List-Id": "<fortune-urgent.consultations.auraface>",
          "X-AuraFace-Consultation": "priority_guidance",
        }
      : {
          Importance: "normal",
          Priority: "non-urgent",
          "X-Priority": "3",
          "List-Id": "<normal.consultations.auraface>",
          "X-AuraFace-Consultation": "normal",
        };

    let result;
    try {
      result = await resend.emails.send({
        from,
        to: [DEV_EMAIL],
        subject,
        html,
        headers,
      });
    } catch (sendErr) {
      const errMsg = sendErr?.message || String(sendErr);
      await updateMessageEmailStatus(msg.id, "failed", errMsg, null);
      console.error(JSON.stringify({
        event: "email_send_failed",
        chatId: body.chatId,
        messageId: msg.id,
        error: errMsg,
        at: new Date().toISOString(),
      }));
      return res.status(502).json({
        success: false,
        code: "EMAIL_SEND_FAILED",
        message: errMsg,
        chatId: body.chatId,
        messageId: msg.id,
      });
    }

    if (result.error) {
      const errMsg = result.error.message || String(result.error);
      await updateMessageEmailStatus(msg.id, "failed", errMsg, null);
      console.error(JSON.stringify({
        event: "email_send_failed",
        chatId: body.chatId,
        messageId: msg.id,
        error: errMsg,
        at: new Date().toISOString(),
      }));
      return res.status(502).json({
        success: false,
        code: "EMAIL_SEND_FAILED",
        message: errMsg,
        chatId: body.chatId,
        messageId: msg.id,
      });
    }

    const emailId = result.data?.id ?? null;
    await updateMessageEmailStatus(msg.id, "sent", null, emailId);
    console.log(JSON.stringify({
      event: "email_sent",
      chatId: body.chatId,
      messageId: msg.id,
      emailId,
      at: new Date().toISOString(),
    }));

    return res.json({
      status: "ok",
      success: true,
      chatId: body.chatId,
      messageId: msg.id,
      emailId,
      saved: true,
      mailSent: true,
      consultationType,
      mailUrgent: isPriority,
      mailSubject: subject,
      mailFromDisplay: isPriority ? FROM_DISPLAY_PRIORITY : FROM_DISPLAY_NORMAL,
      mailApiBuild: "v2-consultation-tier-legacy-bridge-r2-embedded-tier",
    });
  } catch (e) {
    if (e?.code === "VALIDATION_ERROR" || e?.name === "ZodError") {
      return res.status(400).json({ error: e?.message || "Bad request" });
    }
    console.error("[chat/send] fatal", e);
    return res.status(500).json({
      success: false,
      code: "INTERNAL_ERROR",
      message: e instanceof Error ? e.message : "unknown error",
    });
  }
});

app.get("/api/chat/thread", async (req, res) => {
  try {
    const chatId = String(req.query.chatId || "");
    const since = req.query.since ? Number(req.query.since) : undefined;
    if (!chatId) return res.status(400).json({ error: "chatId required" });

    const messages = await getThreadMessages({ chatId, since, limit: 500 });
    res.json({ chatId, messages });
  } catch (e) {
    res.status(500).json({ error: e?.message || "Server error" });
  }
});

app.get("/admin/reply", async (req, res) => {
  try {
    const token = String(req.query.token || "");
    const payload = verifyToken(token, SIGNING_SECRET);
    const chatId = payload.chatId;

    const messages = await getThreadMessages({ chatId, limit: 50 });
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.send(renderReplyPage({ chatId, messages, token, userName: "" }));
  } catch (e) {
    res.status(403).send(`Forbidden: ${escapeHtml(e?.message || "invalid token")}`);
  }
});

app.post("/admin/reply", async (req, res) => {
  try {
    const token = String(req.body.token || "");
    const replyText = String(req.body.replyText || "").trim();
    if (!replyText) return res.status(400).send("replyText required");

    const payload = verifyToken(token, SIGNING_SECRET);
    const chatId = payload.chatId;

    await insertMessage({ chatId, role: "dev", text: replyText });

    res.redirect(`/admin/reply?token=${encodeURIComponent(token)}`);
  } catch (e) {
    res.status(403).send(`Forbidden: ${escapeHtml(e?.message || "invalid token")}`);
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Server listening on 0.0.0.0:${PORT} (LAN from device: http://<PCのIP>:${PORT})`);
  console.log(`BASE_URL=${getBaseUrl()}`);
});
