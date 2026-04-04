/**
 * 至急（priority_guidance）のサーバー側受付方針。
 * デフォルトは 24 時間受付（Flutter アプリと一致）。
 * 運用で JST の時間帯だけに絞る場合は、次の両方を設定:
 *   CONSULTATION_URGENT_JST_HOUR_START=10
 *   CONSULTATION_URGENT_JST_HOUR_END=23
 * （いずれか一方だけでは無効＝24 時間扱い）
 */

function parseEnvHour(name) {
  const v = process.env[name];
  if (v == null || String(v).trim() === "") return null;
  const n = Number(v);
  if (!Number.isInteger(n) || n < 0 || n > 23) return null;
  return n;
}

function getJstHour(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Tokyo",
    hour: "numeric",
    hour12: false,
  }).formatToParts(date);
  const h = parts.find((p) => p.type === "hour");
  return Number(h.value);
}

/**
 * @returns {{ allowed: boolean, enforced: boolean, jstHour?: number, start?: number, end?: number, mode: string }}
 */
function isUrgentAllowedAt(date = new Date()) {
  const start = parseEnvHour("CONSULTATION_URGENT_JST_HOUR_START");
  const end = parseEnvHour("CONSULTATION_URGENT_JST_HOUR_END");
  if (start == null || end == null) {
    return { allowed: true, enforced: false, mode: "24h" };
  }
  const jstHour = getJstHour(date);
  const allowed = jstHour >= start && jstHour <= end;
  return {
    allowed,
    enforced: true,
    jstHour,
    start,
    end,
    mode: "jst_window",
  };
}

function policySummaryForLog() {
  const start = parseEnvHour("CONSULTATION_URGENT_JST_HOUR_START");
  const end = parseEnvHour("CONSULTATION_URGENT_JST_HOUR_END");
  if (start == null || end == null) {
    return { enforced: false, note: "priority_guidance 24h (set START+END to restrict JST hours)" };
  }
  return { enforced: true, jstWindow: `${start}:00–${end}:59 JST` };
}

module.exports = {
  getJstHour,
  isUrgentAllowedAt,
  policySummaryForLog,
};
