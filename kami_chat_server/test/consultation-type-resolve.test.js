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
