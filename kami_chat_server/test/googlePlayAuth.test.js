"use strict";

const { describe, it } = require("node:test");
const assert = require("node:assert/strict");

describe("googlePlayAuth", () => {
  it("package name を環境変数から読む", () => {
    process.env.GOOGLE_PLAY_PACKAGE_NAME = "com.example.app";
    delete require.cache[require.resolve("../googlePlayAuth")];
    const mod = require("../googlePlayAuth");
    assert.equal(mod.getGooglePlayPackageName(), "com.example.app");
  });

  it("health snapshot に billingReady フラグを含む", () => {
    process.env.GOOGLE_PLAY_PACKAGE_NAME = "com.auraface.kami_face_oracle";
    delete require.cache[require.resolve("../googlePlayAuth")];
    const mod = require("../googlePlayAuth");
    const snap = mod.getGooglePlayHealthSnapshot();
    assert.equal(typeof snap.googlePlayBillingReady, "boolean");
    assert.equal(snap.googlePlayPackageName, "com.auraface.kami_face_oracle");
  });
});
