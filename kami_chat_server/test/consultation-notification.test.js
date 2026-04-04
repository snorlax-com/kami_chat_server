"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { buildConsultationNotification } = require("../mail/buildConsultationNotification");
const types = require("../constants/consultationTypes");

const baseInput = {
  userName: "占い相談ユーザー",
  userId: "user_test",
  chatId: "consultation_user_test_1",
  messageId: 42,
  receivedAtMs: Date.UTC(2026, 3, 3, 12, 0, 0),
  message: "本文のテストです。".repeat(5),
  adminReplyUrl: "https://example.com/admin/reply?chatId=c&token=t&expires=9&consultationType=normal",
};

test("通常相談: 件名が通常用である", () => {
  const { subject, html, text } = buildConsultationNotification({
    ...baseInput,
    consultationType: "normal",
  });
  assert.equal(subject, types.SUBJECT_NORMAL);
  assert.ok(subject.includes("[AuraFace]"));
  assert.ok(!subject.includes("優先導き"));
});

test("優先導き: 件名が優先用である（緊急の文字を含む）", () => {
  const { subject } = buildConsultationNotification({
    ...baseInput,
    consultationType: "priority_guidance",
  });
  assert.equal(subject, types.SUBJECT_PRIORITY);
  assert.ok(subject.includes("緊急"));
  assert.ok(subject.includes("優先導き"));
  assert.ok(subject.includes("[PRIORITY_GUIDANCE]"));
});

test("優先導き本文に 2時間以内対応 が含まれる", () => {
  const { html, text } = buildConsultationNotification({
    ...baseInput,
    consultationType: "priority_guidance",
  });
  assert.ok(text.includes("2時間以内"));
  assert.ok(html.includes("2時間以内"));
});

test("通常相談本文に優先導きの見出しが混ざらない", () => {
  const { html, text } = buildConsultationNotification({
    ...baseInput,
    consultationType: "normal",
  });
  assert.ok(!text.includes("【優先導き】"));
  assert.ok(!html.includes("【優先導き】"));
  assert.ok(!html.includes("【緊急】"));
  assert.ok(text.includes("通常相談"));
});

test("通常: HTML にプレヘッダー（一覧スニペット用・至急ではない旨）", () => {
  const { html } = buildConsultationNotification({
    ...baseInput,
    consultationType: "normal",
  });
  assert.ok(html.includes("至急ではありません"));
});

test("優先: HTML にプレヘッダー（一覧スニペット用・2時間以内・至急占い）", () => {
  const { html } = buildConsultationNotification({
    ...baseInput,
    consultationType: "priority_guidance",
  });
  assert.ok(html.includes("2時間以内"));
  assert.ok(html.includes("至急占い"));
  assert.ok(html.includes("通常相談メールとは別"));
});

test("優先: テキスト本文に「緊急」が複数箇所で明示される", () => {
  const { text, html } = buildConsultationNotification({
    ...baseInput,
    consultationType: "priority_guidance",
  });
  assert.ok((text.match(/緊急/g) || []).length >= 2);
  assert.ok(html.includes("緊急対応"));
});

test("consultationType urgent も優先導き扱い", () => {
  const { subject } = buildConsultationNotification({
    ...baseInput,
    consultationType: "urgent",
  });
  assert.equal(subject, types.SUBJECT_PRIORITY);
});

test("両方に返信URLが含まれる", () => {
  const url = baseInput.adminReplyUrl;
  const n = buildConsultationNotification({ ...baseInput, consultationType: "normal" });
  const p = buildConsultationNotification({ ...baseInput, consultationType: "priority_guidance" });
  assert.ok(n.text.includes(url));
  assert.ok(n.html.includes(url));
  assert.ok(p.text.includes(url));
  assert.ok(p.html.includes(url));
});

test("consultationType 未指定は通常扱い", () => {
  const { subject } = buildConsultationNotification({
    ...baseInput,
    consultationType: undefined,
  });
  assert.equal(subject, types.SUBJECT_NORMAL);
});

test("JST 表記が正しい（UTC 03:00 = 東京 12:00）", () => {
  const receivedAtMs = Date.UTC(2026, 3, 3, 3, 0, 0);
  const { text } = buildConsultationNotification({
    ...baseInput,
    receivedAtMs,
    consultationType: "normal",
  });
  assert.ok(text.includes("2026"));
  assert.ok(text.includes("12:00"));
});

test("normalize: 未知の値は normal", () => {
  const { subject } = buildConsultationNotification({
    ...baseInput,
    consultationType: "garbage",
  });
  assert.equal(subject, types.SUBJECT_NORMAL);
});

test("normalizeConsultationType: 空白付き priority_guidance", () => {
  assert.equal(types.normalizeConsultationType("  priority_guidance  "), types.PRIORITY_GUIDANCE);
});

test("normalizeConsultationType: priority（短縮）", () => {
  assert.equal(types.normalizeConsultationType("priority"), types.PRIORITY_GUIDANCE);
});
