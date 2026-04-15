"use strict";

/**
 * Firebase サービスアカウント JSON を FIREBASE_SERVICE_ACCOUNT_JSON_B64 用の1行に変換。
 *
 *   npm run firebase:b64 -- path/to/adminsdk.json
 *   node scripts/firebase-service-account-to-b64.js path/to/adminsdk.json
 */

const fs = require("fs");
const path = require("path");

const p = process.argv[2];
if (!p) {
  console.error(
    "Usage: npm run firebase:b64 -- <path-to-service-account.json>\n" +
    "  例: npm run firebase:b64 -- ./secrets/firebase-adminsdk.json"
  );
  process.exit(1);
}

const abs = path.isAbsolute(p) ? p : path.resolve(process.cwd(), p);
let raw;
try {
  raw = fs.readFileSync(abs, "utf8");
} catch (e) {
  console.error("read failed:", e.message);
  process.exit(1);
}

let j;
try {
  j = JSON.parse(raw);
} catch (e) {
  console.error("invalid JSON:", e.message);
  process.exit(1);
}

if (j.type !== "service_account") {
  console.error('expected JSON type "service_account", got:', j.type);
  process.exit(1);
}

const b64 = Buffer.from(raw, "utf8").toString("base64");
console.log("# Render の Environment に次の1行を FIREBASE_SERVICE_ACCOUNT_JSON_B64 として登録:\n");
console.log(b64);
console.log("");
