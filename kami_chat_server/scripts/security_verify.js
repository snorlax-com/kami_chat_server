#!/usr/bin/env node
/**
 * kami_chat_server セキュリティ検証
 * 使用: IDENTITY_DEV_SECRET=xxx IDENTITY_DEV_UID=test-user node scripts/security_verify.js [BASE_URL]
 */
"use strict";

const http = require("http");
const https = require("https");

const BASE = (process.argv[2] || process.env.BASE_URL || "http://127.0.0.1:3000").replace(/\/$/, "");
const DEV_SECRET = process.env.IDENTITY_DEV_SECRET || "sec-test";
const DEV_UID = process.env.IDENTITY_DEV_UID || "test-user";

let pass = 0;
let fail = 0;

function check(name, ok, detail = "") {
  if (ok) {
    pass++;
    console.log(`  PASS  ${name}${detail ? ` — ${detail}` : ""}`);
  } else {
    fail++;
    console.log(`  FAIL  ${name}${detail ? ` — ${detail}` : ""}`);
  }
}

function request(method, path, body = null, headers = {}) {
  const url = new URL(path, BASE);
  const lib = url.protocol === "https:" ? https : http;
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: url.hostname,
      port: url.port || (url.protocol === "https:" ? 443 : 80),
      path: url.pathname + url.search,
      method,
      headers: { ...headers, ...(body ? { "Content-Type": "application/json" } : {}) },
    };
    const req = lib.request(opts, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => resolve({ status: res.statusCode, body: data }));
    });
    req.on("error", reject);
    if (body) req.write(typeof body === "string" ? body : JSON.stringify(body));
    req.end();
  });
}

async function main() {
  console.log(`Chat server security verify: ${BASE}\n`);

  const health = await request("GET", "/health");
  check("GET /health", health.status === 200, `status=${health.status}`);

  const sendNoAuth = await request("POST", "/api/chat/send", {
    userId: "evil",
    chatId: `consultation_evil_${Date.now()}`,
    message: "test",
  });
  check("POST /api/chat/send without auth → 401", sendNoAuth.status === 401, `status=${sendNoAuth.status}`);

  const threadNoAuth = await request("GET", "/api/chat/thread?chatId=consultation_other_1");
  check("GET /api/chat/thread without auth → 401", threadNoAuth.status === 401, `status=${threadNoAuth.status}`);

  const devHeaders = { "x-identity-dev-secret": DEV_SECRET };
  const chatId = `consultation_${DEV_UID}_${Date.now()}`;
  const sendOk = await request(
    "POST",
    "/api/chat/send",
    { userId: DEV_UID, chatId, message: "security test" },
    devHeaders
  );
  check("POST /api/chat/send with dev auth → 200", sendOk.status === 200, `status=${sendOk.status}`);

  const threadWrong = await request(
    "GET",
    `/api/chat/thread?chatId=consultation_other_user_999`,
    null,
    devHeaders
  );
  check("GET /api/chat/thread other user → 403", threadWrong.status === 403, `status=${threadWrong.status}`);

  const threadOwn = await request("GET", `/api/chat/thread?chatId=${encodeURIComponent(chatId)}`, null, devHeaders);
  check("GET /api/chat/thread own chatId → 200", threadOwn.status === 200, `status=${threadOwn.status}`);

  const adminLogin = await request("POST", "/admin/login", { email: "wrong@test.com", password: "wrong" });
  check(
    "POST /admin/login wrong/missing config → 401 or 400/503",
    adminLogin.status === 401 || adminLogin.status === 400 || adminLogin.status === 503,
    `status=${adminLogin.status}`
  );

  const billingNoAuth = await request("POST", "/api/billing/verify", {
    productId: "normal_ticket_600",
    purchaseToken: "fake",
    productType: "inapp",
  });
  check("POST /api/billing/verify without auth → 401", billingNoAuth.status === 401, `status=${billingNoAuth.status}`);

  console.log(`\nResult: ${pass} passed, ${fail} failed`);
  process.exit(fail > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
