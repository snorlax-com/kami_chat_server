const { test, beforeEach, afterEach } = require("node:test");
const assert = require("node:assert/strict");

let urgentReception;

beforeEach(() => {
  delete process.env.CONSULTATION_URGENT_JST_HOUR_START;
  delete process.env.CONSULTATION_URGENT_JST_HOUR_END;
  delete require.cache[require.resolve("../config/urgentReception")];
  urgentReception = require("../config/urgentReception");
});

afterEach(() => {
  delete process.env.CONSULTATION_URGENT_JST_HOUR_START;
  delete process.env.CONSULTATION_URGENT_JST_HOUR_END;
});

test("getJstHour: UTC 00:00 = 東京 09:00", () => {
  assert.strictEqual(urgentReception.getJstHour(new Date("2024-06-15T00:00:00.000Z")), 9);
});

test("未設定時は 24 時間至急可", () => {
  const r = urgentReception.isUrgentAllowedAt(new Date("2024-06-15T00:00:00.000Z"));
  assert.strictEqual(r.allowed, true);
  assert.strictEqual(r.enforced, false);
  assert.strictEqual(r.mode, "24h");
});

test("START/END 両方あるとき JST 9 時は不可（10–23）", () => {
  process.env.CONSULTATION_URGENT_JST_HOUR_START = "10";
  process.env.CONSULTATION_URGENT_JST_HOUR_END = "23";
  delete require.cache[require.resolve("../config/urgentReception")];
  urgentReception = require("../config/urgentReception");
  const r = urgentReception.isUrgentAllowedAt(new Date("2024-06-15T00:00:00.000Z"));
  assert.strictEqual(r.allowed, false);
  assert.strictEqual(r.enforced, true);
  assert.strictEqual(r.jstHour, 9);
});

test("START/END 両方あるとき JST 10 時は可", () => {
  process.env.CONSULTATION_URGENT_JST_HOUR_START = "10";
  process.env.CONSULTATION_URGENT_JST_HOUR_END = "23";
  delete require.cache[require.resolve("../config/urgentReception")];
  urgentReception = require("../config/urgentReception");
  const r = urgentReception.isUrgentAllowedAt(new Date("2024-06-15T01:00:00.000Z"));
  assert.strictEqual(r.allowed, true);
  assert.strictEqual(r.jstHour, 10);
});

test("一方だけ設定した場合は無効（24 時間）", () => {
  process.env.CONSULTATION_URGENT_JST_HOUR_START = "10";
  delete process.env.CONSULTATION_URGENT_JST_HOUR_END;
  delete require.cache[require.resolve("../config/urgentReception")];
  urgentReception = require("../config/urgentReception");
  const r = urgentReception.isUrgentAllowedAt(new Date("2024-06-15T00:00:00.000Z"));
  assert.strictEqual(r.allowed, true);
  assert.strictEqual(r.enforced, false);
});
