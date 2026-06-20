"use strict";

/**
 * Play Console 用サービスアカウント JSON → GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64
 *
 *   node scripts/play-service-account-to-b64.js ./secure/google-play-service-account.json
 *   node scripts/play-service-account-to-b64.js ./secrets/firebase-adminsdk.json
 */

const fs = require("fs");
const path = require("path");

const input = process.argv[2];
if (!input) {
  console.error("Usage: node scripts/play-service-account-to-b64.js <service-account.json>");
  process.exit(1);
}

const abs = path.isAbsolute(input) ? input : path.resolve(process.cwd(), input);
const raw = fs.readFileSync(abs, "utf8").trim();
JSON.parse(raw);
const b64 = Buffer.from(raw, "utf8").toString("base64");

const out = path.join(path.dirname(abs), "render-GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64.txt");
fs.writeFileSync(out, b64 + "\n", "utf8");

console.log("# GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_B64（Render 1行シークレット）");
console.log("# ソース:", abs);
console.log("");
console.log(b64);
console.log("");
console.log("# 保存:", out);
console.log("# 反映: npm run render:upsert-play-sa-b64");
