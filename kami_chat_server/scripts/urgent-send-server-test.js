#!/usr/bin/env node
/**
 * ローカル kami_chat_server で至急送信（priority_guidance）が正しく処理されるか検証。
 *   node scripts/urgent-send-server-test.js
 *   node scripts/urgent-send-server-test.js https://kami-chat-server.onrender.com
 *
 * 本番 URL の場合は Firebase 認証が必要なため、ローカル（dev secret）での検証を推奨。
 */
"use strict";

const http = require("http");
const https = require("https");
const { spawn } = require("child_process");
const path = require("path");

const BASE_ARG = process.argv[2];
const DEV_SECRET = process.env.IDENTITY_DEV_SECRET || "urgent_e2e_secret";
const DEV_UID = process.env.IDENTITY_DEV_UID || "urgent_e2e_uid";

function request(base, method, pth, body, headers = {}) {
  const url = new URL(pth, base.endsWith("/") ? base : base + "/");
  const lib = url.protocol === "https:" ? https : http;
  const payload = body != null ? JSON.stringify(body) : "";
  const hdrs = { ...headers };
  if (payload) {
    hdrs["Content-Type"] = "application/json";
    hdrs["Content-Length"] = Buffer.byteLength(payload);
  }
  return new Promise((resolve, reject) => {
    const req = lib.request(
      {
        hostname: url.hostname,
        port: url.port || (url.protocol === "https:" ? 443 : 80),
        path: url.pathname + url.search,
        method,
        headers: hdrs,
        timeout: 120000,
      },
      (res) => {
        let raw = "";
        res.on("data", (c) => (raw += c));
        res.on("end", () => {
          let parsed = null;
          try {
            parsed = raw ? JSON.parse(raw) : null;
          } catch (_) { }
          resolve({ status: res.statusCode, raw, parsed });
        });
      }
    );
    req.on("error", reject);
    req.setTimeout(120000, () => {
      req.destroy();
      reject(new Error("timeout"));
    });
    req.end(payload || undefined);
  });
}

async function waitHealth(base, maxMs = 10000) {
  const t0 = Date.now();
  while (Date.now() - t0 < maxMs) {
    try {
      const r = await request(base, "GET", "/health");
      if (r.status === 200) return;
    } catch (_) { }
    await new Promise((r) => setTimeout(r, 150));
  }
  throw new Error("server health timeout");
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

async function runUrgentSendTest(base, authHeaders) {
  const chatId = `consultation_${DEV_UID}_${Date.now()}`;
  const message =
    "（緊急）サーバーテスト至急\n\n__AURAFACE_SEND_TIER__:priority_guidance__";

  const send = await request(
    base,
    "POST",
    "/api/chat/send",
    {
      userId: DEV_UID,
      chatId,
      message,
      userName: "サーバーテスト",
      consultationType: "priority_guidance",
      urgent: true,
      consultationPriority: 2,
    },
    {
      ...authHeaders,
      "X-AuraFace-Consultation-Type": "priority_guidance",
    }
  );

  console.log("[POST /api/chat/send urgent] status", send.status);
  console.log("[POST /api/chat/send urgent] body", send.raw.slice(0, 500));

  assert(send.status === 200, `send status ${send.status}: ${send.raw.slice(0, 200)}`);
  const j = send.parsed;
  assert(j && j.success !== false, `send not success: ${send.raw.slice(0, 200)}`);
  assert(j.consultationType === "priority_guidance", `consultationType=${j.consultationType}`);
  assert(j.mailUrgent === true, `mailUrgent=${j.mailUrgent}`);
  assert(
    String(j.mailApiBuild || "").includes("r12-emergency-retry"),
    `mailApiBuild=${j.mailApiBuild}`
  );
  assert(
    j.mailSubject == null || String(j.mailSubject).includes("至急"),
    `mailSubject=${j.mailSubject}`
  );

  const thread = await request(base, "GET", `/api/chat/thread?chatId=${encodeURIComponent(chatId)}`, null, authHeaders);
  console.log("[GET /api/chat/thread] status", thread.status);
  assert(thread.status === 200, `thread status ${thread.status}`);
  const msgs = thread.parsed?.messages;
  assert(Array.isArray(msgs) && msgs.length >= 1, "thread messages empty");
  assert(
    msgs[0].consultationType === "priority_guidance",
    `stored consultationType=${msgs[0].consultationType}`
  );

  console.log("urgent-send-server-test: OK", {
    chatId,
    consultationType: j.consultationType,
    mailUrgent: j.mailUrgent,
    mailSent: j.mailSent,
    mailEmergencyDelivered: j.mailEmergencyDelivered,
    mailSubject: j.mailSubject,
    mailApiBuild: j.mailApiBuild,
  });
}

async function main() {
  if (BASE_ARG) {
    console.log("BASE (external):", BASE_ARG);
    console.log("本番は認証必須のため smoke のみ。至急ロジックはローカルテストで検証します。");
    const root = await request(BASE_ARG, "GET", "/");
    console.log("[GET /] status", root.status, root.raw.slice(0, 80));
    const health = await request(BASE_ARG, "GET", "/health");
    console.log("[GET /health] status", health.status, health.raw.slice(0, 200));
    assert(root.status === 200, "GET / failed");
    assert(health.status === 200, "GET /health failed");
    return;
  }

  const baseDir = path.join(__dirname, "..");
  const port = 31850 + Math.floor(Math.random() * 50);
  const base = `http://127.0.0.1:${port}`;
  const child = spawn(process.execPath, ["index.js"], {
    cwd: baseDir,
    env: {
      ...process.env,
      PORT: String(port),
      NODE_ENV: "development",
      IDENTITY_DEV_SECRET: DEV_SECRET,
      IDENTITY_DEV_UID: DEV_UID,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });

  try {
    await waitHealth(base);
    await runUrgentSendTest(base, { "x-identity-dev-secret": DEV_SECRET });
  } finally {
    child.kill("SIGTERM");
    await new Promise((r) => setTimeout(r, 300));
    if (child.exitCode === null) child.kill("SIGKILL");
  }
}

main().catch((e) => {
  console.error("urgent-send-server-test: FAIL", e.message);
  process.exit(1);
});
