"use strict";

/**
 * MAIL_FROM のアドレス部分はそのまま、表示名だけ差し替える（Resend の検証ドメインを維持）
 * @param {string} mailFrom 例: AuraFace <notify@example.com> または notify@example.com
 * @param {string} displayName 例: AuraFace｜通常相談
 */
function withDisplayName(mailFrom, displayName) {
  const s = String(mailFrom).trim();
  const open = s.lastIndexOf("<");
  const close = s.lastIndexOf(">");
  if (open >= 0 && close > open) {
    const addr = s.slice(open + 1, close).trim();
    return `${displayName} <${addr}>`;
  }
  if (/^[^\s<>]+@[^\s<>]+$/.test(s)) {
    return `${displayName} <${s}>`;
  }
  return s;
}

module.exports = { withDisplayName };
