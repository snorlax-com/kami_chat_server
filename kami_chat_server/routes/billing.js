"use strict";

const express = require("express");
const { google } = require("googleapis");
const { requireAuth } = require("../middleware/auth");
const idb = require("../identityDb");

const router = express.Router();
const androidPublisher = google.androidpublisher("v3");

const PRODUCT_ALIASES = {
  ticket_normal_600: "normal_ticket_600",
  ticket_urgent_10000: "urgent_ticket_10000",
  subscription_monthly_500: "monthly_subscription_500",
};

function canonicalProductId(productId) {
  const id = String(productId || "").trim();
  return PRODUCT_ALIASES[id] || id;
}

async function getAuthClient() {
  const auth = new google.auth.GoogleAuth({
    keyFile: process.env.GOOGLE_APPLICATION_CREDENTIALS,
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  return auth.getClient();
}

function ticketTypeForProduct(canonicalId) {
  if (canonicalId === "normal_ticket_600") return "normal";
  if (canonicalId === "urgent_ticket_10000") return "urgent";
  return null;
}

function grantTicket(userId, productId, purchaseToken) {
  const db = idb.getDb();
  const canonical = canonicalProductId(productId);
  const ticketType = ticketTypeForProduct(canonical);
  if (!ticketType) {
    return Promise.reject(new Error("unknown productId"));
  }

  const existing = db
    .prepare("SELECT id FROM purchases WHERE purchase_token = ?")
    .get(purchaseToken);
  if (existing) return Promise.resolve({ duplicate: true });

  const now = new Date().toISOString();
  const insertPurchase = db.prepare(
    "INSERT INTO purchases (user_id, product_id, purchase_token, created_at) VALUES (?, ?, ?, ?)"
  );
  const insertTicket = db.prepare(
    "INSERT INTO tickets (user_id, type, amount, created_at) VALUES (?, ?, ?, ?)"
  );

  const tx = db.transaction(() => {
    insertPurchase.run(userId, canonical, purchaseToken, now);
    insertTicket.run(userId, ticketType, 1, now);
  });
  tx();
  return Promise.resolve({ duplicate: false });
}

function grantSubscriptionBenefit(userId, productId, purchaseToken) {
  const db = idb.getDb();
  const canonical = canonicalProductId(productId);

  const existing = db
    .prepare("SELECT id FROM subscriptions WHERE purchase_token = ?")
    .get(purchaseToken);
  if (existing) return Promise.resolve({ duplicate: true });

  const now = new Date().toISOString();
  const insertSub = db.prepare(
    "INSERT INTO subscriptions (user_id, product_id, purchase_token, status, created_at) VALUES (?, ?, ?, ?, ?)"
  );
  const insertTicket = db.prepare(
    "INSERT INTO tickets (user_id, type, amount, created_at) VALUES (?, ?, ?, ?)"
  );

  const tx = db.transaction(() => {
    insertSub.run(userId, canonical, purchaseToken, "active", now);
    insertTicket.run(userId, "normal", 1, now);
  });
  tx();
  return Promise.resolve({ duplicate: false });
}

router.post("/api/billing/verify", requireAuth, async (req, res) => {
  const { productId, purchaseToken, productType } = req.body || {};
  const userId = req.user.userId;

  if (!productId || !purchaseToken || !productType) {
    return res.status(400).json({ error: "購入情報が不足しています。" });
  }

  const pkg = (process.env.GOOGLE_PLAY_PACKAGE_NAME || "").trim();
  if (!pkg) {
    return res.status(503).json({ error: "課金検証が設定されていません。" });
  }

  try {
    const authClient = await getAuthClient();
    google.options({ auth: authClient });
    const playProductId = String(productId).trim();
    const canonical = canonicalProductId(playProductId);

    if (productType === "subs") {
      const response = await androidPublisher.purchases.subscriptions.get({
        packageName: pkg,
        subscriptionId: playProductId,
        token: String(purchaseToken),
      });
      const purchase = response.data;
      if (!purchase || Number(purchase.paymentState) !== 1) {
        return res.status(400).json({ error: "サブスク購入が確認できません。" });
      }
      await grantSubscriptionBenefit(userId, canonical, String(purchaseToken));
    } else if (productType === "inapp") {
      const response = await androidPublisher.purchases.products.get({
        packageName: pkg,
        productId: playProductId,
        token: String(purchaseToken),
      });
      const purchase = response.data;
      if (!purchase || Number(purchase.purchaseState) !== 0) {
        return res.status(400).json({ error: "購入が確認できません。" });
      }
      await grantTicket(userId, canonical, String(purchaseToken));
    } else {
      return res.status(400).json({ error: "productType が不正です。" });
    }

    res.json({ ok: true });
  } catch (err) {
    console.error("billing verify error", { message: err.message });
    res.status(500).json({ error: "購入検証に失敗しました。" });
  }
});

module.exports = router;
