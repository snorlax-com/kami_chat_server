"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const types = require("../constants/consultationTypes");

test("resolveConsultationTypeFromSendBody: 未指定は通常", () => {
  assert.equal(types.resolveConsultationTypeFromSendBody({}), types.NORMAL);
});

test("resolveConsultationTypeFromSendBody: priority_guidance", () => {
  assert.equal(
    types.resolveConsultationTypeFromSendBody({ consultationType: "priority_guidance" }),
    types.PRIORITY_GUIDANCE
  );
});

test("resolveConsultationTypeFromSendBody: consultation_type 別名", () => {
  assert.equal(
    types.resolveConsultationTypeFromSendBody({ consultation_type: "priority_guidance" }),
    types.PRIORITY_GUIDANCE
  );
});

test("resolveConsultationTypeFromSendBody: consultationType 欠落でも urgent で優先導き", () => {
  assert.equal(types.resolveConsultationTypeFromSendBody({ urgent: true }), types.PRIORITY_GUIDANCE);
});

test("resolveConsultationTypeFromSendBody: urgent 文字列 true", () => {
  assert.equal(types.resolveConsultationTypeFromSendBody({ urgent: "true" }), types.PRIORITY_GUIDANCE);
});

test("resolveConsultationTypeFromSendBody: 明示 normal は urgent でも通常（通常送信を至急にしない）", () => {
  assert.equal(
    types.resolveConsultationTypeFromSendBody({ consultationType: "normal", urgent: true }),
    types.NORMAL
  );
});

test("resolveConsultationTypeFromSendBody: 空文字 + urgent で優先導き", () => {
  assert.equal(types.resolveConsultationTypeFromSendBody({ consultationType: "", urgent: true }), types.PRIORITY_GUIDANCE);
});

test("resolveConsultationTypeFromSendBody: ヘッダー相当のみで優先導き", () => {
  assert.equal(types.resolveConsultationTypeFromSendBody({}, "priority_guidance"), types.PRIORITY_GUIDANCE);
});

test("resolveConsultationTypeFromSendBody: 本文 normal はヘッダーより優先", () => {
  assert.equal(
    types.resolveConsultationTypeFromSendBody({ consultationType: "normal" }, "priority_guidance"),
    types.NORMAL
  );
});

test("resolveConsultationTypeFromSendBody: 本文 priority_guidance はヘッダー normal より優先", () => {
  assert.equal(
    types.resolveConsultationTypeFromSendBody({ consultationType: "priority_guidance" }, "normal"),
    types.PRIORITY_GUIDANCE
  );
});

test("resolveConsultationTypeFromSendBody: body が誤って normal でも urgent+埋め込み至急なら至急", () => {
  assert.equal(
    types.resolveConsultationTypeFromSendBody(
      { consultationType: "normal", urgent: true, consultationPriority: 1 },
      null,
      "priority_guidance"
    ),
    types.PRIORITY_GUIDANCE
  );
});

test("resolveConsultationTypeFromSendBody: body が誤って normal でも priority2+埋め込み至急なら至急", () => {
  assert.equal(
    types.resolveConsultationTypeFromSendBody(
      { consultationType: "normal", urgent: false, consultationPriority: 2 },
      null,
      "priority_guidance"
    ),
    types.PRIORITY_GUIDANCE
  );
});

test("resolveConsultationTypeFromSendBody: consultationPriority 2", () => {
  assert.equal(types.resolveConsultationTypeFromSendBody({ consultationPriority: 2 }), types.PRIORITY_GUIDANCE);
});

test("normalizeConsultationType: 数値 2 は優先導き", () => {
  assert.equal(types.normalizeConsultationType(2), types.PRIORITY_GUIDANCE);
});

test("extractEmbeddedConsultationTier: 末尾マーカーを除去", () => {
  const { cleanText, embeddedTierRaw } = types.extractEmbeddedConsultationTier(
    "相談本文です\n\n__AURAFACE_SEND_TIER__:priority_guidance__"
  );
  assert.equal(cleanText.trimEnd(), "相談本文です");
  assert.equal(embeddedTierRaw, "priority_guidance");
});

test("resolveConsultationTypeFromSendBody: 埋め込みのみで優先導き", () => {
  assert.equal(types.resolveConsultationTypeFromSendBody({}, null, "priority_guidance"), types.PRIORITY_GUIDANCE);
});

test("resolveConsultationTypeFromSendBody: 明示 normal は埋め込みより優先", () => {
  assert.equal(
    types.resolveConsultationTypeFromSendBody({ consultationType: "normal" }, null, "priority_guidance"),
    types.NORMAL
  );
});
