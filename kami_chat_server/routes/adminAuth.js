"use strict";

const express = require("express");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const path = require("path");

const router = express.Router();

router.get("/admin/login.html", (req, res) => {
  res.sendFile(path.join(__dirname, "..", "public", "admin", "login.html"));
});

router.post("/admin/login", async (req, res) => {
  const { email, password } = req.body || {};

  if (!email || !password) {
    return res.status(400).json({ error: "メールとパスワードが必要です。" });
  }

  const adminEmail = (process.env.ADMIN_EMAIL || "").trim();
  const adminHash = (process.env.ADMIN_PASSWORD_HASH || "").trim();
  const jwtSecret = (process.env.JWT_SECRET || "").trim();

  if (!adminEmail || !adminHash || !jwtSecret) {
    return res.status(503).json({ error: "管理者ログインが設定されていません。" });
  }

  if (String(email).trim() !== adminEmail) {
    return res.status(401).json({ error: "ログイン情報が違います。" });
  }

  const ok = await bcrypt.compare(String(password), adminHash);
  if (!ok) {
    return res.status(401).json({ error: "ログイン情報が違います。" });
  }

  const token = jwt.sign(
    {
      role: "admin",
      email: adminEmail,
    },
    jwtSecret,
    { expiresIn: "6h" }
  );

  res.json({ token });
});

module.exports = router;
