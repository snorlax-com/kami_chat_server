#!/usr/bin/env node
/**
 * 本番（Render）の最低限疎通のみ。スレッドAPIの有無を表示する。
 *   node scripts/render-production-smoke.js [BASE_URL]
 */
const https = require("https");

const BASE = process.argv[2] || "https://kami-chat-server.onrender.com";

function get(path) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE);
    const req = https.request(
      { hostname: url.hostname, path: url.pathname + url.search, method: "GET", timeout: 120000 },
      (res) => {
        let d = "";
        res.on("data", (c) => (d += c));
        res.on("end", () => resolve({ status: res.statusCode, body: d }));
      }
    );
    req.on("error", reject);
    req.setTimeout(120000, () => {
      req.destroy();
      reject(new Error("timeout"));
    });
    req.end();
  });
}

function postJson(path, json) {
  const body = JSON.stringify(json);
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE);
    const req = https.request(
      {
        hostname: url.hostname,
        path: url.pathname + url.search,
        method: "POST",
        headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) },
        timeout: 120000,
      },
      (res) => {
        let d = "";
        res.on("data", (c) => (d += c));
        res.on("end", () => resolve({ status: res.statusCode, body: d }));
      }
    );
    req.on("error", reject);
    req.setTimeout(120000, () => {
      req.destroy();
      reject(new Error("timeout"));
    });
    req.write(body);
    req.end();
  });
}

async function main() {
  console.log("BASE:", BASE, "\n");
  const cid = `smoke_${Date.now()}`;

  const r0 = await get("/");
  const rootSnippet = r0.body.slice(0, 120);
  console.log("[GET /] status", r0.status, "body", rootSnippet);
  if (r0.status === 200 && rootSnippet.trim() === "OK") {
    console.log("       (最新: プレーン OK)");
  } else if (r0.status === 200 && /kami chat server/i.test(r0.body)) {
    console.log("       (レガシー JSON — 再デプロイでプレーン OK になります)");
  }

  let health = null;
  try {
    health = await get("/health");
    console.log("[GET /health] status", health.status, "body", health.body.slice(0, 120));
  } catch (e) {
    console.log("[GET /health]", e.message);
  }

  const send = await postJson("/api/chat/send", {
    userId: "smoke",
    chatId: cid,
    message: "render smoke",
  });
  console.log("[POST /api/chat/send] status", send.status, "body", send.body.slice(0, 200));

  const thread = await get(`/api/chat/thread?chatId=${encodeURIComponent(cid)}`);
  console.log("[GET /api/chat/thread] status", thread.status);
  if (thread.status === 404) {
    console.log("\n>>> スレッドAPIが404です。kami_chat_server の最新版（index.js に GET /api/chat/thread）をRenderへ再デプロイしてください。\n");
    process.exit(2);
  }
  console.log("body", thread.body.slice(0, 300));
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
