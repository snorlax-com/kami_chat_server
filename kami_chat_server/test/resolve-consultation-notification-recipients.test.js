"use strict";

const { test, afterEach } = require("node:test");
const assert = require("node:assert/strict");
const types = require("../constants/consultationTypes");
const {
  resolveConsultationNotificationRecipients,
  resolvePrimaryRecipient,
  DEFAULT_EMERGENCY_NOTIFICATION_EMAIL,
} = require("../mail/resolveConsultationNotificationRecipients");

afterEach(() => {
  delete process.env.DEV_NOTIFICATION_EMAIL;
  delete process.env.ADMIN_EMAIL;
  delete process.env.MAIL_TO_NORMAL;
  delete process.env.MAIL_TO_PRIORITY;
  delete process.env.EMERGENCY_NOTIFICATION_EMAIL;
});

test("通常: 主宛先1件のみ（DEV_NOTIFICATION_EMAIL 優先）", () => {
  process.env.DEV_NOTIFICATION_EMAIL = "dev@example.com";
  process.env.ADMIN_EMAIL = "admin@example.com";
  const r = resolveConsultationNotificationRecipients(types.NORMAL);
  assert.deepEqual(r, ["dev@example.com"]);
});

test("通常: DEV なしなら ADMIN_EMAIL", () => {
  process.env.ADMIN_EMAIL = "only@example.com";
  const r = resolveConsultationNotificationRecipients("normal");
  assert.deepEqual(r, ["only@example.com"]);
});

test("通常: MAIL_TO_NORMAL があれば上書き", () => {
  process.env.ADMIN_EMAIL = "admin@example.com";
  process.env.MAIL_TO_NORMAL = "normal-box@example.com";
  const r = resolveConsultationNotificationRecipients(types.NORMAL);
  assert.deepEqual(r, ["normal-box@example.com"]);
});

test("至急: 主＋緊急の2件", () => {
  process.env.ADMIN_EMAIL = "admin@example.com";
  const r = resolveConsultationNotificationRecipients(types.PRIORITY_GUIDANCE);
  assert.deepEqual(r, ["admin@example.com", DEFAULT_EMERGENCY_NOTIFICATION_EMAIL]);
});

test("至急: EMERGENCY_NOTIFICATION_EMAIL で上書き", () => {
  process.env.ADMIN_EMAIL = "admin@example.com";
  process.env.EMERGENCY_NOTIFICATION_EMAIL = "custom-emergency@example.com";
  const r = resolveConsultationNotificationRecipients(types.PRIORITY_GUIDANCE);
  assert.deepEqual(r, ["admin@example.com", "custom-emergency@example.com"]);
});

test("至急: 主と緊急が同一なら1件に重複除去", () => {
  process.env.ADMIN_EMAIL = "same@example.com";
  process.env.EMERGENCY_NOTIFICATION_EMAIL = "same@example.com";
  const r = resolveConsultationNotificationRecipients(types.PRIORITY_GUIDANCE);
  assert.deepEqual(r, ["same@example.com"]);
});

test("至急: MAIL_TO_PRIORITY が主、緊急はデフォルト", () => {
  process.env.ADMIN_EMAIL = "admin@example.com";
  process.env.MAIL_TO_PRIORITY = "urgent@example.com";
  const r = resolveConsultationNotificationRecipients(types.PRIORITY_GUIDANCE);
  assert.deepEqual(r, ["urgent@example.com", DEFAULT_EMERGENCY_NOTIFICATION_EMAIL]);
});

test("resolvePrimaryRecipient は種別を正規化する", () => {
  process.env.ADMIN_EMAIL = "a@b.co";
  assert.equal(resolvePrimaryRecipient("priority_guidance"), "a@b.co");
});

test("主宛先が空なら例外", () => {
  assert.throws(
    () => resolveConsultationNotificationRecipients(types.NORMAL),
    /主通知先が未設定/
  );
});
