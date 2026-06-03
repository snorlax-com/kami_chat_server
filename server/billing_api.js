/**
 * Google Play 購入記録 API（SQLite）
 * kami_chat_server 等の Express アプリにマウント:
 *   const { createBillingRouter } = require('./billing_api');
 *   app.use(createBillingRouter(db));
 */
const express = require('express');

const CANONICAL_PRODUCTS = new Set([
  'subscription_monthly_500',
  'ticket_normal_600',
  'ticket_urgent_10000',
]);

function ensureBillingTables(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS billing_purchases (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      firebase_uid TEXT NOT NULL,
      product_id TEXT NOT NULL,
      raw_product_id TEXT,
      purchase_id TEXT NOT NULL,
      purchase_token TEXT,
      order_id TEXT,
      purchase_time_ms INTEGER,
      is_subscription INTEGER NOT NULL DEFAULT 0,
      is_restore INTEGER NOT NULL DEFAULT 0,
      platform TEXT NOT NULL DEFAULT 'android',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(firebase_uid, purchase_id)
    );
    CREATE INDEX IF NOT EXISTS idx_billing_uid ON billing_purchases(firebase_uid);
    CREATE INDEX IF NOT EXISTS idx_billing_token ON billing_purchases(purchase_token);
  `);
}

function createBillingRouter(db, verifyFirebaseToken) {
  ensureBillingTables(db);
  const router = express.Router();

  router.post('/api/billing/purchases', express.json(), async (req, res) => {
    try {
      const auth = req.headers.authorization || '';
      const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
      if (!token || !verifyFirebaseToken) {
        return res.status(401).json({ error: 'unauthorized' });
      }
      const decoded = await verifyFirebaseToken(token);
      const uid = decoded.uid;
      const {
        productId,
        rawProductId,
        purchaseId,
        purchaseToken,
        orderId,
        purchaseTimeMs,
        isSubscription,
        isRestore,
        platform,
      } = req.body || {};

      if (!productId || !purchaseId) {
        return res.status(400).json({ error: 'productId and purchaseId required' });
      }
      if (!CANONICAL_PRODUCTS.has(productId)) {
        return res.status(400).json({ error: 'unknown productId' });
      }

      const stmt = db.prepare(`
        INSERT INTO billing_purchases (
          firebase_uid, product_id, raw_product_id, purchase_id,
          purchase_token, order_id, purchase_time_ms,
          is_subscription, is_restore, platform
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(firebase_uid, purchase_id) DO NOTHING
      `);
      stmt.run(
        uid,
        productId,
        rawProductId || null,
        purchaseId,
        purchaseToken || null,
        orderId || null,
        purchaseTimeMs ?? null,
        isSubscription ? 1 : 0,
        isRestore ? 1 : 0,
        platform || 'android',
      );

      return res.status(200).json({ ok: true });
    } catch (e) {
      console.error('[billing_api]', e);
      return res.status(500).json({ error: 'internal' });
    }
  });

  return router;
}

module.exports = { createBillingRouter, ensureBillingTables };
