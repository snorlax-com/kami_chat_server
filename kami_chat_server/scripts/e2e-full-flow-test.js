#!/usr/bin/env node
/**
 * チャット送信 → (Gmail) → 返信ページ → POST返信 → スレッド取得 までを HTTP で自動検証。
 *
 * BASE_URL=https://xxxx.onrender.com TOKEN_SECRET=（サーバーと同じ） node scripts/e2e-full-flow-test.js
 *
 * STRICT_MAIL=1 を付けると mail が OK でない限り overall も FAIL（本番のメール込み検証用）
 * 省略時はチャット保存・返信・スレッドまで通れば overall SUCCESS（ローカルで Resend なしでも可）
 */

require("dotenv").config({ path: require("path").join(__dirname, "..", ".env") });
const http = require("http");
const https = require("https");
const { generateToken } = require("../token");

const BASE = (process.env.BASE_URL || process.argv[2] || "").replace(/\/$/, "");
const TOKEN_SECRET = process.env.TOKEN_SECRET || "";
const STRICT_MAIL =
  process.env.STRICT_MAIL === "1" || String(process.env.STRICT_MAIL).toLowerCase() === "true";

const USER_MSG = "E2Eテストメッセージ";
const DEV_MSG = "開発者返信テスト";

const result = {
  send: "NG",
  mail: "NG",
  reply: "NG",
  db: "NG",
  fetch: "NG",
  overall: "FAIL",
};

function request(method, urlPath, body = null, contentType = null, timeoutMs = 120000) {
  const url = new URL(urlPath, BASE + "/");
  const isHttps = url.protocol === "https:";
  const lib = isHttps ? https : http;
  const port = url.port || (isHttps ? 443 : 80);
  return new Promise((resolve, reject) => {
    const headers = {};
    if (body != null && contentType) {
      headers["Content-Type"] = contentType;
    }
    const opts = {
      hostname: url.hostname,
      port,
      path: url.pathname + url.search,
      method,
      headers,
    };
    const req = lib.request(opts, (res) => {
      let raw = "";
      res.on("data", (c) => (raw += c));
      res.on("end", () => {
        resolve({ status: res.statusCode, raw, headers: res.headers });
      });
    });
    req.on("error", reject);
    req.setTimeout(timeoutMs, () => {
      req.destroy();
      reject(new Error("timeout"));
    });
    if (body != null) req.write(body);
    req.end();
  });
}

function parseJson(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

/** 送信 API がチャットを受け付けたか（本番レガシー互換） */
function sendWasAccepted(j) {
  if (!j || j.success === false) return false;
  const st = j.status;
  return st === "ok" || st === "received" || st === "saved_but_mail_failed";
}

async function main() {
  const errors = [];
  const warnings = [];

  if (!BASE) {
    console.error("BASE_URL / 引数1 でベースURLを指定してください。例: BASE_URL=https://xxx.onrender.com");
    process.exit(1);
  }
  if (!TOKEN_SECRET) {
    console.error(
      "TOKEN_SECRET が未設定です。Render の Environment と同じ値を環境変数で渡してください（返信リンク検証用）。"
    );
    process.exit(1);
  }

  console.log("BASE_URL:", BASE, STRICT_MAIL ? "(STRICT_MAIL)" : "");
  const chatId = `test_${Date.now()}`;

  // --- Step 1: GET /（プレーン OK またはデプロイ前のレガシー JSON）
  console.log("\n[1] GET /");
  const r0 = await request("GET", "/");
  const raw0 = String(r0.raw || "").trim();
  const legacyRoot = r0.status === 200 && /kami chat server|running/i.test(raw0);
  if (r0.status === 200 && raw0 === "OK") {
    console.log("  OK (plain text)");
  } else if (legacyRoot) {
    warnings.push("GET / がレガシー応答です。最新デプロイでプレーン OK にできます。");
    console.log("  OK (legacy JSON)");
  } else {
    errors.push(`GET / expected 200 + OK or legacy JSON, got ${r0.status} ${raw0.slice(0, 80)}`);
  }

  // --- POST /api/chat/send
  console.log("\n[3] POST /api/chat/send");
  const sendBody = JSON.stringify({
    chatId,
    userId: "test_user",
    message: USER_MSG,
    userName: "E2E",
  });
  const r1 = await request("POST", "/api/chat/send", sendBody, "application/json");
  const j1 = parseJson(r1.raw);
  if (r1.status !== 200 || !sendWasAccepted(j1)) {
    errors.push(`send: status=${r1.status} body=${(r1.raw || "").slice(0, 300)}`);
  } else {
    result.send = "OK";
    console.log("  send OK", { status: j1.status, mailSent: j1.mailSent, mailId: j1.mailId });
  }
  if (j1 && j1.mailSent === true) {
    result.mail = "OK";
    console.log("  mail (API): mailSent=true");
  } else {
    warnings.push(
      "mail: mailSent!=true（Resend 未設定のローカル、または本番の環境変数要確認）"
    );
    console.log("  mail (API): 未送信または失敗");
  }

  // --- トークン
  const { token, expires } = generateToken(chatId);
  const q = `/admin/reply?chatId=${encodeURIComponent(chatId)}&token=${encodeURIComponent(token)}&expires=${encodeURIComponent(String(expires))}`;

  console.log("\n[5] GET /admin/reply (token)");
  const r2 = await request("GET", q);
  const html = r2.raw || "";
  if (r2.status !== 200) {
    errors.push(`GET admin/reply ${r2.status}`);
  } else if (
    !html.includes("チャット履歴") ||
    !html.includes("textarea") ||
    !html.includes("返信送信")
  ) {
    errors.push("admin/reply HTML: 期待する要素が不足");
  } else {
    console.log("  reply page OK");
  }

  console.log("\n[6] POST /admin/reply");
  const form = new URLSearchParams({
    chatId,
    token,
    expires: String(expires),
    message: DEV_MSG,
  }).toString();
  const r3 = await request("POST", "/admin/reply", form, "application/x-www-form-urlencoded");
  const html3 = r3.raw || "";
  if (r3.status !== 200 || !html3.includes("返信しました")) {
    errors.push(`POST admin/reply ${r3.status} ${html3.slice(0, 120)}`);
  } else {
    console.log("  POST OK（返信しました）");
  }

  if (r2.status === 200 && r3.status === 200 && html3.includes("返信しました")) {
    result.reply = "OK";
  }

  console.log("\n[7–8] GET /api/chat/thread");
  const r4 = await request("GET", `/api/chat/thread?chatId=${encodeURIComponent(chatId)}`);
  const j4 = parseJson(r4.raw);
  if (r4.status === 404) {
    errors.push(
      "thread: 404 — Render の Root Directory を kami_chat_server にするか render.yaml で再デプロイ"
    );
  } else if (r4.status !== 200 || !j4 || !Array.isArray(j4.messages)) {
    errors.push(`thread ${r4.status} ${(r4.raw || "").slice(0, 200)}`);
  } else {
    const msgs = j4.messages;
    const okOrder =
      msgs.length >= 2 &&
      msgs[0].role === "user" &&
      msgs[0].text === USER_MSG &&
      msgs[1].role === "dev" &&
      msgs[1].text === DEV_MSG;
    if (!okOrder) {
      errors.push(`thread mismatch: ${JSON.stringify(msgs)}`);
    } else {
      result.db = "OK";
      result.fetch = "OK";
      console.log("  thread OK");
    }
  }

  let overallOk =
    errors.length === 0 &&
    result.send === "OK" &&
    result.reply === "OK" &&
    result.db === "OK" &&
    result.fetch === "OK";

  if (STRICT_MAIL && result.mail !== "OK") {
    overallOk = false;
    errors.push("STRICT_MAIL: mail が OK である必要があります");
  }

  if (overallOk) {
    result.overall = "SUCCESS";
  }

  console.log("\n--- 結果 JSON ---");
  console.log(JSON.stringify(result, null, 2));
  if (warnings.length) {
    console.log("\n--- 警告 ---");
    warnings.forEach((w) => console.log(" -", w));
  }
  if (errors.length) {
    console.log("\n--- エラー ---");
    errors.forEach((e) => console.log(" -", e));
  }

  process.exit(overallOk ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  console.log(JSON.stringify({ ...result, overall: "FAIL", error: String(e.message) }, null, 2));
  process.exit(1);
});
