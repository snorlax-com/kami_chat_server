"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { withDisplayName } = require("../mail/mailFrom");

test("表示名のみ差し替え（角括弧形式）", () => {
  assert.equal(
    withDisplayName("Old <hi@example.com>", "AuraFace｜通常相談"),
    "AuraFace｜通常相談 <hi@example.com>"
  );
});

test("メールのみのときは表示名を付与", () => {
  assert.equal(withDisplayName("hi@example.com", "【優先】AuraFace"), "【優先】AuraFace <hi@example.com>");
});
