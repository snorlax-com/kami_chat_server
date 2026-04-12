"use strict";

const fs = require("fs");
const path = require("path");
const Database = require("better-sqlite3");

let _db;

function openDb() {
  const dir = process.env.IDENTITY_DB_DIR || path.join(__dirname, "data");
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, "identity.sqlite");
  const db = new Database(file);
  db.pragma("journal_mode = WAL");
  db.exec(`
create table if not exists users (
  id text primary key,
  auth_provider text not null,
  provider_user_id text,
  email text,
  email_verified integer not null default 0,
  display_name text,
  photo_url text,
  created_at text not null,
  updated_at text not null
);

create unique index if not exists idx_users_provider_unique
on users(auth_provider, provider_user_id);

create table if not exists guest_sessions (
  id text primary key,
  converted_to_user_id text,
  created_at text not null,
  updated_at text not null
);

create table if not exists diagnosis_results (
  id text primary key,
  user_id text,
  guest_session_id text,
  pillar_key text not null,
  summary_text text,
  detail_json text not null,
  source_image_url text,
  is_unlocked integer not null default 0,
  created_at text not null,
  updated_at text not null,
  foreign key(user_id) references users(id),
  foreign key(guest_session_id) references guest_sessions(id)
);

create index if not exists idx_diagnosis_results_user_id
on diagnosis_results(user_id);

create index if not exists idx_diagnosis_results_guest_session_id
on diagnosis_results(guest_session_id);

create table if not exists chat_threads (
  id text primary key,
  user_id text not null,
  consultation_type text not null,
  created_at text not null,
  updated_at text not null
);

create index if not exists idx_chat_threads_user_id on chat_threads(user_id);

create table if not exists messages (
  id text primary key,
  thread_id text not null,
  sender_type text not null,
  body text not null,
  created_at text not null,
  foreign key(thread_id) references chat_threads(id)
);
`);
  return db;
}

function getDb() {
  if (!_db) _db = openDb();
  return _db;
}

function upsertUser(row) {
  const db = getDb();
  const stmt = db.prepare(`
insert into users (id, auth_provider, provider_user_id, email, email_verified, display_name, photo_url, created_at, updated_at)
values (@id, @auth_provider, @provider_user_id, @email, @email_verified, @display_name, @photo_url, @created_at, @updated_at)
on conflict(id) do update set
  email = excluded.email,
  email_verified = excluded.email_verified,
  display_name = excluded.display_name,
  photo_url = excluded.photo_url,
  updated_at = excluded.updated_at
`);
  stmt.run(row);
}

function insertGuestSession(id, now) {
  const db = getDb();
  db.prepare(
    `insert into guest_sessions (id, converted_to_user_id, created_at, updated_at) values (?, null, ?, ?)`
  ).run(id, now, now);
}

function guestSessionExists(id) {
  const db = getDb();
  const r = db.prepare(`select id, converted_to_user_id from guest_sessions where id = ?`).get(id);
  return r || null;
}

function insertTutorialDiagnosis(row) {
  const db = getDb();
  db.prepare(`
insert into diagnosis_results (
  id, user_id, guest_session_id, pillar_key, summary_text, detail_json, source_image_url, is_unlocked, created_at, updated_at
) values (
  @id, @user_id, @guest_session_id, @pillar_key, @summary_text, @detail_json, @source_image_url, @is_unlocked, @created_at, @updated_at
)
`).run(row);
}

function claimGuestDiagnosisToUser({ guestSessionId, userId, authProvider, now }) {
  const db = getDb();
  const gs = guestSessionExists(guestSessionId);
  if (!gs) {
    return { ok: false, code: "guest_not_found", message: "guest session not found" };
  }
  if (gs.converted_to_user_id) {
    if (gs.converted_to_user_id === userId) {
      return { ok: true, code: "already_claimed", already: true };
    }
    return { ok: false, code: "guest_already_claimed", message: "guest data already claimed by another user" };
  }

  const tx = db.transaction(() => {
    db.prepare(
      `update guest_sessions set converted_to_user_id = ?, updated_at = ? where id = ?`
    ).run(userId, now, guestSessionId);

    db.prepare(`
update diagnosis_results set
  user_id = ?,
  guest_session_id = null,
  is_unlocked = 1,
  updated_at = ?
where guest_session_id = ?
`).run(userId, now, guestSessionId);
  });
  tx();

  return { ok: true, code: "claimed", already: false };
}

function getLatestDiagnosisForUser(userId, { includeDetail }) {
  const db = getDb();
  const row = db
    .prepare(
      `select * from diagnosis_results where user_id = ? order by datetime(updated_at) desc limit 1`
    )
    .get(userId);
  if (!row) return null;
  const base = {
    id: row.id,
    pillarKey: row.pillar_key,
    summaryText: row.summary_text,
    isUnlocked: !!row.is_unlocked,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
  if (includeDetail && row.is_unlocked) {
    try {
      base.detailJson = JSON.parse(row.detail_json);
    } catch {
      base.detailJson = null;
    }
  }
  return base;
}

function upsertChatThread({ chatId, userId, consultationType, now }) {
  if (!chatId || !userId) return;
  const db = getDb();
  const existing = db.prepare(`select id from chat_threads where id = ?`).get(chatId);
  if (existing) {
    db.prepare(`update chat_threads set consultation_type = ?, updated_at = ? where id = ?`).run(
      consultationType,
      now,
      chatId
    );
  } else {
    db.prepare(`
insert into chat_threads (id, user_id, consultation_type, created_at, updated_at)
values (?, ?, ?, ?, ?)
`).run(chatId, userId, consultationType, now, now);
  }
}

function listThreadsForUser(userId) {
  const db = getDb();
  return db
    .prepare(
      `select id, consultation_type as consultationType, created_at as createdAt, updated_at as updatedAt
       from chat_threads where user_id = ? order by datetime(updated_at) desc`
    )
    .all(userId);
}

module.exports = {
  getDb,
  upsertUser,
  insertGuestSession,
  guestSessionExists,
  insertTutorialDiagnosis,
  claimGuestDiagnosisToUser,
  getLatestDiagnosisForUser,
  upsertChatThread,
  listThreadsForUser,
};
