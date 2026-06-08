"use strict";

const helmet = require("helmet");
const cors = require("cors");
const rateLimit = require("express-rate-limit");

const allowedOrigins = (process.env.CORS_ALLOWED_ORIGINS || "https://auraface.jp,https://admin.auraface.jp")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

function applySecurityMiddleware(app) {
  app.use(
    helmet({
      contentSecurityPolicy: false,
      crossOriginResourcePolicy: { policy: "cross-origin" },
    })
  );

  app.use((req, res, next) => {
    if (process.env.NODE_ENV === "production") {
      if (req.headers["x-forwarded-proto"] !== "https") {
        return res.redirect(301, `https://${req.headers.host}${req.url}`);
      }
    }
    next();
  });

  app.use(
    cors({
      origin(origin, callback) {
        if (!origin) return callback(null, true);
        if (allowedOrigins.includes(origin)) return callback(null, true);
        if (process.env.NODE_ENV !== "production") return callback(null, true);
        return callback(new Error("CORS blocked"));
      },
      credentials: true,
    })
  );

  const apiLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: Number(process.env.RATE_LIMIT_API_MAX || 60),
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      error: "アクセスが多すぎます。少し時間を置いて再試行してください。",
    },
  });

  const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    max: Number(process.env.RATE_LIMIT_AUTH_MAX || 10),
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      error: "ログイン試行回数が多すぎます。",
    },
  });

  app.use("/api/", apiLimiter);
  app.use("/predict", apiLimiter);
  app.use("/admin/login", authLimiter);

  return { apiLimiter, authLimiter };
}

module.exports = { applySecurityMiddleware, allowedOrigins };
