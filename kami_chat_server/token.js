const crypto = require("crypto");

const secret = process.env.TOKEN_SECRET || "change-me-in-production";

function generateToken(chatId) {
  const expires =
    Date.now() +
    Number(process.env.TOKEN_EXPIRES_HOURS || 168) * 60 * 60 * 1000;
  const payload = `${chatId}.${expires}`;
  const signature = crypto
    .createHmac("sha256", secret)
    .update(payload)
    .digest("hex");
  return { token: signature, expires };
}

function verifyToken(chatId, token, expires) {
  if (!chatId || !token || typeof token !== "string") return false;
  const exp = Number(expires);
  if (!exp || isNaN(exp) || Date.now() > exp) return false;

  const payload = `${chatId}.${exp}`;
  const expected = crypto
    .createHmac("sha256", secret)
    .update(payload)
    .digest("hex");

  try {
    if (expected.length !== token.length) return false;
    return crypto.timingSafeEqual(
      Buffer.from(expected, "utf8"),
      Buffer.from(token, "utf8")
    );
  } catch (_) {
    return false;
  }
}

module.exports = { generateToken, verifyToken };
