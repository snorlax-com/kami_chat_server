"use strict";

/**
 * Render API でサービス環境変数を1件だけ追加・更新（他の変数は触らない）。
 *
 * 事前: Render → Account → API Keys で RENDER_API_KEY を作成。
 *       対象 Web Service → Settings で Service ID（srv_...）をコピー。
 *
 *   export RENDER_API_KEY=rnd_...
 *   export RENDER_SERVICE_ID=srv_...
 *   npm run render:upsert-firebase-b64
 *
 * または:
 *   node scripts/render-upsert-env-from-file.js FIREBASE_SERVICE_ACCOUNT_JSON_B64 ./secrets/render-FIREBASE_SERVICE_ACCOUNT_JSON_B64.txt
 */

const fs = require("fs");
const path = require("path");

require("dotenv").config({ path: path.join(__dirname, "..", ".env") });

const apiKey = process.env.RENDER_API_KEY;
const serviceId = process.env.RENDER_SERVICE_ID;
const envKey = process.argv[2] || "FIREBASE_SERVICE_ACCOUNT_JSON_B64";
const fileArg =
  process.argv[3] || path.join(__dirname, "..", "secrets", "render-FIREBASE_SERVICE_ACCOUNT_JSON_B64.txt");

if (!apiKey || !String(apiKey).trim()) {
  console.error("ERROR: 環境変数 RENDER_API_KEY を設定してください（Render → Account Settings → API Keys）");
  process.exit(1);
}
if (!serviceId || !String(serviceId).trim()) {
  console.error("ERROR: 環境変数 RENDER_SERVICE_ID を設定してください（例: srv-xxxx。Service → Settings）");
  process.exit(1);
}

const abs = path.isAbsolute(fileArg) ? fileArg : path.resolve(process.cwd(), fileArg);
let value;
try {
  value = fs.readFileSync(abs, "utf8").trim();
} catch (e) {
  console.error("ERROR: ファイルを読めません:", abs, e.message);
  process.exit(1);
}
if (!value) {
  console.error("ERROR: 値が空です:", abs);
  process.exit(1);
}

const url = `https://api.render.com/v1/services/${encodeURIComponent(
  String(serviceId).trim()
)}/env-vars/${encodeURIComponent(envKey)}`;

async function main() {
  const res = await fetch(url, {
    method: "PUT",
    headers: {
      Authorization: `Bearer ${String(apiKey).trim()}`,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ value }),
  });
  console.log("HTTP", res.status, url.replace(serviceId, serviceId.slice(0, 8) + "…"));
  if (!res.ok) {
    const text = await res.text();
    let msg = text;
    try {
      const j = JSON.parse(text);
      msg = j && j.message ? String(j.message) : JSON.stringify(j);
    } catch (_) { }
    console.error("FAILED:", String(msg).slice(0, 300));
    console.error("FAILED: API が成功しませんでした。キー・Service ID・権限を確認してください。");
    process.exit(1);
  }
  // Render のレスポンスには value（秘密）が含まれ得るので、成功時も本文は出力しない。
  try {
    await res.text();
  } catch (_) { }
  console.log("OK: 環境変数を保存しました。Render が自動で再デプロイするまで 1〜3 分待ってから /health を確認してください。");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
