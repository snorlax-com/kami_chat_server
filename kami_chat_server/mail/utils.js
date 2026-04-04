"use strict";

function escapeHtml(str = "") {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

/** @param {number} ms */
function formatReceivedAtJst(ms) {
  return new Intl.DateTimeFormat("ja-JP", {
    timeZone: "Asia/Tokyo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(new Date(ms));
}

/** @param {string} message @param {number} maxLen */
function messagePreview(message, maxLen = 200) {
  const s = String(message || "").replace(/\r\n/g, "\n").trim();
  if (s.length <= maxLen) return s;
  return s.slice(0, maxLen) + "…";
}

/** Gmail 一覧の2行目（スニペット）用。本文先頭と混ざらないようゼロ幅スペースで埋める */
function gmailPreheader(visibleText, padZwsp = 120) {
  const pad = "\u200c".repeat(padZwsp);
  return `<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#fff;opacity:0;">${escapeHtml(visibleText)}${pad}</div>`;
}

module.exports = { escapeHtml, formatReceivedAtJst, messagePreview, gmailPreheader };
