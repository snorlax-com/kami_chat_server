#!/usr/bin/env node
/**
 * 送信→受信(開発者返信)→送信 の一連の流れが正しく反映されるかテストする。
 * 1. ユーザー送信
 * 2. スレッド取得（1件: user）
 * 3. 開発者返信（dev-reply）
 * 4. スレッド取得（2件: user, dev）
 * 5. ユーザー再送信
 * 6. スレッド取得（3件: user, dev, user）→ 内容・順序を検証
 *
 * 使用: node scripts/send-receive-send-test.js [BASE_URL]
 * 例:   node scripts/send-receive-send-test.js
 *       node scripts/send-receive-send-test.js https://kami-chat-server.onrender.com
 */

const http = require("http");
const https = require("https");

const BASE = process.argv[2] || "http://127.0.0.1:3000";
const chatId = `test-srs-${Date.now()}`;
const userId = "test-user";

/** JSON オブジェクトのレスポンス body を安全に取り出す（HTML 404 等は {}） */
function jsonBody(res) {
  const b = res.body;
  if (b !== null && typeof b === "object" && !Array.isArray(b)) return b;
  return {};
}

function request(method, path, body = null) {
  const url = new URL(path, BASE);
  const isHttps = url.protocol === "https:";
  const lib = isHttps ? https : http;
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: url.hostname,
      port: url.port || (isHttps ? 443 : 80),
      path: url.pathname + url.search,
      method,
      headers: body ? { "Content-Type": "application/json" } : {},
    };
    const req = lib.request(opts, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => {
        try {
          resolve({
            status: res.statusCode,
            body: data.length ? JSON.parse(data) : data,
          });
        } catch {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });
    req.on("error", reject);
    if (body) req.write(typeof body === "string" ? body : JSON.stringify(body));
    req.end();
  });
}

async function run() {
  let step = 0;
  const fail = (msg) => {
    console.error(`[FAIL] ${msg}`);
    process.exit(1);
  };

  console.log("BASE:", BASE, "chatId:", chatId);

  // 1. ユーザー送信
  step++;
  console.log(`\n--- Step ${step}: POST /api/chat/send (1通目) ---`);
  const send1 = await request("POST", "/api/chat/send", {
    userId,
    chatId,
    message: "1通目ユーザー送信",
  });
  if (send1.status !== 200) fail(`send1 status ${send1.status}: ${JSON.stringify(send1.body)}`);
  // 本番が古い場合は { status: "received" } のみ（success なし）のことがある
  const okStatus1 =
    send1.body.status === "ok" ||
    send1.body.status === "received" ||
    send1.body.status === "saved_but_mail_failed";
  if (!okStatus1) fail(`send1 unexpected status: ${JSON.stringify(send1.body)}`);
  if (send1.body.success === false) fail(`send1 not success: ${JSON.stringify(send1.body)}`);
  console.log("OK:", send1.body);

  // 2. スレッド取得（1件: user）
  step++;
  console.log(`\n--- Step ${step}: GET /api/chat/thread (1件期待) ---`);
  const thread1 = await request("GET", `/api/chat/thread?chatId=${encodeURIComponent(chatId)}`);
  if (thread1.status === 404) {
    fail(
      "thread1: GET /api/chat/thread が404です。Render の Root Directory を「kami_chat_server」に設定するか、リポジトリルートの render.yaml を同期して再デプロイしてください。"
    );
  }
  if (thread1.status !== 200) fail(`thread1 status ${thread1.status}`);
  const msgs1 = jsonBody(thread1).messages || [];
  if (msgs1.length !== 1) fail(`thread1 expected 1 message, got ${msgs1.length}`);
  if (msgs1[0].role !== "user" || msgs1[0].text !== "1通目ユーザー送信")
    fail(`thread1 message mismatch: ${JSON.stringify(msgs1[0])}`);
  console.log("OK: 1 message (user):", msgs1[0].text);

  // 3. 開発者返信
  step++;
  console.log(`\n--- Step ${step}: POST /api/chat/dev-reply (開発者返信) ---`);
  const devReply = await request("POST", "/api/chat/dev-reply", {
    chatId,
    text: "開発者からの返信です",
  });
  if (devReply.status !== 200) fail(`dev-reply status ${devReply.status}: ${JSON.stringify(devReply.body)}`);
  console.log("OK:", devReply.body);

  // 4. スレッド取得（2件: user, dev）
  step++;
  console.log(`\n--- Step ${step}: GET /api/chat/thread (2件期待: user, dev) ---`);
  const thread2 = await request("GET", `/api/chat/thread?chatId=${encodeURIComponent(chatId)}`);
  if (thread2.status !== 200) fail(`thread2 status ${thread2.status}`);
  const msgs2 = jsonBody(thread2).messages || [];
  if (msgs2.length !== 2) fail(`thread2 expected 2 messages, got ${msgs2.length}`);
  if (msgs2[0].role !== "user" || msgs2[0].text !== "1通目ユーザー送信")
    fail(`thread2[0] mismatch: ${JSON.stringify(msgs2[0])}`);
  if (msgs2[1].role !== "dev" || msgs2[1].text !== "開発者からの返信です")
    fail(`thread2[1] mismatch: ${JSON.stringify(msgs2[1])}`);
  console.log("OK: 2 messages (user, dev)");

  // 5. ユーザー再送信
  step++;
  console.log(`\n--- Step ${step}: POST /api/chat/send (2通目) ---`);
  const send2 = await request("POST", "/api/chat/send", {
    userId,
    chatId,
    message: "2通目ユーザー送信",
  });
  if (send2.status !== 200) fail(`send2 status ${send2.status}: ${JSON.stringify(send2.body)}`);
  if (send2.body.success === false) fail(`send2 not success: ${JSON.stringify(send2.body)}`);
  const okStatus2 =
    send2.body.status === "ok" ||
    send2.body.status === "received" ||
    send2.body.status === "saved_but_mail_failed";
  if (!okStatus2) fail(`send2 unexpected status: ${JSON.stringify(send2.body)}`);
  console.log("OK:", send2.body);

  // 6. スレッド取得（3件: user, dev, user）→ 内容・順序検証
  step++;
  console.log(`\n--- Step ${step}: GET /api/chat/thread (3件期待: user, dev, user) ---`);
  const thread3 = await request("GET", `/api/chat/thread?chatId=${encodeURIComponent(chatId)}`);
  if (thread3.status !== 200) fail(`thread3 status ${thread3.status}`);
  const msgs3 = jsonBody(thread3).messages || [];
  if (msgs3.length !== 3) fail(`thread3 expected 3 messages, got ${msgs3.length}`);
  const expected = [
    { role: "user", text: "1通目ユーザー送信" },
    { role: "dev", text: "開発者からの返信です" },
    { role: "user", text: "2通目ユーザー送信" },
  ];
  for (let i = 0; i < 3; i++) {
    if (msgs3[i].role !== expected[i].role || msgs3[i].text !== expected[i].text)
      fail(`thread3[${i}] expected ${JSON.stringify(expected[i])}, got ${JSON.stringify(msgs3[i])}`);
  }
  console.log("OK: 3 messages in order (user, dev, user)");
  console.log("\n--- 送信→受信→送信 テスト完了: すべて成功 ---");
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
