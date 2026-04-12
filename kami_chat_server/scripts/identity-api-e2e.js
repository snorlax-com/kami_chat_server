"use strict";

/**
 * ゲスト診断・claim・GET /me・threads・二重 claim をローカルで検証する。
 * 空いている PORT を使う（既定 0 なら 31700–31999 からランダム）。
 *
 *   node scripts/identity-api-e2e.js
 *   PORT=30990 node scripts/identity-api-e2e.js
 */

const http = require("http");
const { spawn } = require("child_process");
const path = require("path");

function request(port, method, pth, body, extraHeaders = {}) {
  return new Promise((resolve, reject) => {
    const payload = body != null ? JSON.stringify(body) : "";
    const headers = { ...extraHeaders };
    if (payload) {
      headers["Content-Type"] = "application/json";
      headers["Content-Length"] = Buffer.byteLength(payload);
    }
    const req = http.request(
      { hostname: "127.0.0.1", port, path: pth, method, headers },
      (res) => {
        let buf = "";
        res.on("data", (c) => (buf += c));
        res.on("end", () => resolve({ status: res.statusCode, body: buf }));
      }
    );
    req.on("error", reject);
    req.end(payload || undefined);
  });
}

async function waitHealth(port, maxMs = 8000) {
  const t0 = Date.now();
  while (Date.now() - t0 < maxMs) {
    try {
      const r = await request(port, "GET", "/health");
      if (r.status === 200) return;
    } catch (_) {}
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error("server did not become healthy");
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

async function main() {
  const baseDir = path.join(__dirname, "..");
  let port = Number(process.env.PORT || 0);
  if (!port) {
    port = 31700 + Math.floor(Math.random() * 299);
  }

  const env = {
    ...process.env,
    PORT: String(port),
    NODE_ENV: "development",
    IDENTITY_DEV_SECRET: "e2e_identity_secret",
    IDENTITY_DEV_UID: "e2e_firebase_uid",
  };

  const child = spawn(process.execPath, ["index.js"], {
    cwd: baseDir,
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });

  let stderr = "";
  child.stderr.on("data", (c) => {
    stderr += c.toString();
  });

  try {
    await waitHealth(port);

    let r = await request(port, "POST", "/api/auth/guest-session", {});
    assert(r.status === 200, `guest-session ${r.status} ${r.body}`);
    const { guestSessionId } = JSON.parse(r.body);
    assert(guestSessionId && guestSessionId.startsWith("guest_"), "guestSessionId");

    r = await request(port, "POST", "/api/diagnosis/tutorial", {
      guestSessionId,
      pillarKey: "fire",
      summaryText: "s",
      detailJson: { k: 1 },
    });
    assert(r.status === 200, `tutorial ${r.status} ${r.body}`);

    r = await request(port, "POST", "/api/auth/claim-guest-data", { guestSessionId });
    assert(r.status === 401, `claim without auth expected 401 got ${r.status}`);

    r = await request(port, "POST", "/api/auth/claim-guest-data", { guestSessionId }, {
      "x-identity-dev-secret": "e2e_identity_secret",
    });
    assert(r.status === 200, `claim ${r.status} ${r.body}`);
    const c1 = JSON.parse(r.body);
    assert(c1.success === true && c1.already === false, "first claim");

    r = await request(port, "GET", "/api/diagnosis/me", null, {
      "x-identity-dev-secret": "e2e_identity_secret",
    });
    assert(r.status === 200, `me ${r.status} ${r.body}`);
    const me = JSON.parse(r.body);
    assert(me.isUnlocked === true && me.detailJson && me.detailJson.k === 1, "me detail");

    r = await request(port, "POST", "/api/auth/claim-guest-data", { guestSessionId }, {
      "x-identity-dev-secret": "e2e_identity_secret",
    });
    assert(r.status === 200, `second claim ${r.status}`);
    const c2 = JSON.parse(r.body);
    assert(c2.already === true, "idempotent claim");

    r = await request(port, "POST", "/api/chat/send", {
      userId: "e2e_firebase_uid",
      chatId: "e2e_thread_1",
      message: "hello\n\n__AURAFACE_SEND_TIER__:normal__",
      userName: "e2e",
    });
    assert(r.status === 200, `chat send ${r.status}`);

    r = await request(port, "GET", "/api/chat/threads/me", null, {
      "x-identity-dev-secret": "e2e_identity_secret",
    });
    assert(r.status === 200, `threads ${r.status}`);
    const th = JSON.parse(r.body);
    assert(Array.isArray(th.threads) && th.threads.some((t) => t.id === "e2e_thread_1"), "thread listed");

    console.log("identity-api-e2e: OK (port %s)", port);
  } finally {
    child.kill("SIGTERM");
    await new Promise((r) => setTimeout(r, 300));
    if (child.exitCode === null) child.kill("SIGKILL");
  }
}

main().catch((e) => {
  console.error("identity-api-e2e: FAIL", e.message);
  process.exit(1);
});
