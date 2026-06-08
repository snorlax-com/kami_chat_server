"use strict";

const jwt = require("jsonwebtoken");
const { verifyBearerToken } = require("../firebaseVerify");

function getBearerToken(req) {
  const authHeader = req.headers.authorization || "";
  if (!authHeader.startsWith("Bearer ")) return null;
  return authHeader.replace(/^Bearer\s+/i, "").trim();
}

/**
 * ユーザー API 用: Firebase ID トークン、または JWT（管理者以外）。
 * 開発時は x-identity-dev-secret バイパス可（firebaseVerify と同条件）。
 */
async function requireAuth(req, res, next) {
  if (process.env.NODE_ENV !== "production") {
    const secret = process.env.IDENTITY_DEV_SECRET;
    const uid = process.env.IDENTITY_DEV_UID;
    const got = req.get("x-identity-dev-secret");
    if (secret && uid && got === secret) {
      req.user = { userId: uid, role: "user", email: null };
      return next();
    }
  }

  const token = getBearerToken(req);
  if (!token) {
    return res.status(401).json({ error: "認証が必要です。" });
  }

  const jwtSecret = process.env.JWT_SECRET;
  if (jwtSecret && String(jwtSecret).trim()) {
    try {
      const decoded = jwt.verify(token, jwtSecret);
      if (decoded && decoded.role === "admin") {
        req.user = {
          userId: decoded.email || "admin",
          role: "admin",
          email: decoded.email || null,
        };
        return next();
      }
      if (decoded && decoded.userId) {
        req.user = {
          userId: String(decoded.userId),
          role: decoded.role || "user",
          email: decoded.email || null,
        };
        return next();
      }
    } catch (_) {
      /* Firebase へフォールスルー */
    }
  }

  try {
    const identity = await verifyBearerToken(token);
    if (identity) {
      req.user = {
        userId: identity.uid,
        role: "user",
        email: identity.email,
      };
      return next();
    }
  } catch (e) {
    console.warn("[auth] firebase verify failed", { message: e.message });
  }

  return res.status(401).json({ error: "認証トークンが無効です。" });
}

function requireAdmin(req, res, next) {
  if (!req.user || req.user.role !== "admin") {
    return res.status(403).json({ error: "管理者権限が必要です。" });
  }
  next();
}

/** メール内リンク用 HMAC トークン（既存）または管理者 JWT（Bearer） */
function requireAdminOrMailToken(req, res, next) {
  if (req.user && req.user.role === "admin") {
    return next();
  }

  const bearer = getBearerToken(req);
  const jwtSecret = (process.env.JWT_SECRET || "").trim();
  if (bearer && jwtSecret) {
    try {
      const decoded = jwt.verify(bearer, jwtSecret);
      if (decoded && decoded.role === "admin") {
        req.user = { role: "admin", email: decoded.email || null };
        return next();
      }
    } catch (_) {
      /* mail token へ */
    }
  }

  const { verifyToken } = require("../token");
  const chatId = req.query?.chatId || req.body?.chatId;
  const token = req.query?.token || req.body?.token;
  const expires = req.query?.expires || req.body?.expires;
  if (verifyToken(chatId, token, expires)) {
    req.mailTokenAuth = true;
    return next();
  }
  return res.status(403).json({ error: "管理者権限が必要です。" });
}

module.exports = {
  requireAuth,
  requireAdmin,
  requireAdminOrMailToken,
  getBearerToken,
};
