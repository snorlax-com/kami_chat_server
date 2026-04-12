"use strict";

const { randomUUID } = require("crypto");

function createGuestSessionId() {
  return `guest_${randomUUID()}`;
}

function createUserId() {
  return `user_${randomUUID()}`;
}

module.exports = { createGuestSessionId, createUserId };
