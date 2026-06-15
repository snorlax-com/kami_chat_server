#!/usr/bin/env node
/**
 * 創設者（占い師）返信 + FCM プッシュ送信の検証
 * node scripts/test-dev-reply-push.js [BASE_URL] [userId]
 */
const http = require("http");
const https = require("https");

const BASE = process.argv[2] || "http://127.0.0.1:3001";
const userId = process.argv[3] || "test_push_user";
const chatId = `consultation_${userId}_${Date.now()}`;
const FAKE_FCM = "fake_token_for_flow_test_" + Date.now();

function request(method, path, body) {
  const url = new URL(path, BASE);
  const lib = url.protocol === "https:" ? https : http;
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: url.hostname,
      port: url.port || (url.protocol === "https:" ? 443 : 80),
      path: url.pathname + url.search,
      method,
      headers: body ? { "Content-Type": "application/json" } : {},
    };
    const req = lib.request(opts, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => {
        try {
          resolve({ status: res.statusCode, body: data ? JSON.parse(data) : {} });
        } catch {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });
    req.on("error", reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

(async () => {
  console.log("BASE", BASE, "chatId", chatId, "userId", userId);

  const send = await request("POST", "/api/chat/send", {
    userId,
    chatId,
    message: "push test user message",
    fcmToken: FAKE_FCM,
    fcmPlatform: "android",
  });
  console.log("send", send.status, send.body);

  const dev = await request("POST", "/api/chat/dev-reply", {
    chatId,
    text: "創設者（占い師）テスト返信（通知確認用）",
  });
  console.log("dev-reply", dev.status, dev.body);

  const thread = await request("GET", `/api/chat/thread?chatId=${encodeURIComponent(chatId)}`);
  console.log("thread messages", thread.body?.messages?.length);

  process.exit(dev.body?.push?.ok || dev.body?.push?.skipped ? 0 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
