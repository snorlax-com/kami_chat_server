"use strict";

const bcrypt = require("bcrypt");

async function main() {
  const password = process.argv[2];

  if (!password) {
    console.error("使い方: node scripts/hashPassword.js パスワード");
    process.exit(1);
  }

  const hash = await bcrypt.hash(password, 12);
  console.log(hash);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
