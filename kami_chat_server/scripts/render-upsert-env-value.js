"use strict";

/**
 * Render API で環境変数を1件追加・更新（値を引数または stdin で渡す）。
 *
 *   export RENDER_API_KEY=rnd_...
 *   export RENDER_SERVICE_ID=srv_...
 *   node scripts/render-upsert-env-value.js GOOGLE_PLAY_PACKAGE_NAME com.auraface.kami_face_oracle
 */

const path = require("path");

require("dotenv").config({ path: path.join(__dirname, "..", ".env") });

const apiKey = process.env.RENDER_API_KEY;
const serviceId = process.env.RENDER_SERVICE_ID;
const envKey = process.argv[2];
const envValue = process.argv[3];

if (!apiKey || !String(apiKey).trim()) {
  console.error("ERROR: RENDER_API_KEY を設定してください");
  process.exit(1);
}
if (!serviceId || !String(serviceId).trim()) {
  console.error("ERROR: RENDER_SERVICE_ID を設定してください");
  process.exit(1);
}
if (!envKey || envValue == null || String(envValue).trim() === "") {
  console.error("Usage: node scripts/render-upsert-env-value.js ENV_KEY ENV_VALUE");
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
    body: JSON.stringify({ value: String(envValue) }),
  });
  console.log("HTTP", res.status, envKey);
  if (!res.ok) {
    const text = await res.text();
    console.error("FAILED:", String(text).slice(0, 300));
    process.exit(1);
  }
  try {
    await res.text();
  } catch (_) {}
  console.log("OK: Render 環境変数を更新しました:", envKey);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
