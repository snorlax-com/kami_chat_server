# kami_chat_server（Render 用チャット + Gmail 通知）

## Render でスレッド API が 404 になるとき

リポジトリ**ルート**でビルドしていると、古い `index.js` だけが動き **`GET /api/chat/thread` が無い**ことがあります。

**対処（どちらか）**

1. Render ダッシュボード → 該当 Web Service → **Settings** → **Root Directory** を **`kami_chat_server`** にして **Manual Deploy**  
2. リポジトリルートの **`render.yaml`**（`rootDir: kami_chat_server`）を Blueprint として同期

---

アプリ（Flutter）は `POST /api/chat/send` でここに相談を送り、**Resend** 経由で開発者の **Gmail（ADMIN_EMAIL）** に通知します。

### 相談種別（consultationType）

| 値 | 意味 | 差出人表示名（例） | メール件名の傾向 |
|----|------|-------------------|------------------|
| `normal`（省略時もこれ） | 通常相談 | `AuraFace｜通常相談` | `[AuraFace] 新しい相談が届きました` |
| `priority_guidance` | 優先導き（至急） | `至急占い相談｜AuraFace【優先導き】` | `【至急占い・緊急】2時間以内要対応｜優先導き｜AuraFace …` |

- 件名・HTML/テキスト本文は **`mail/buildConsultationNotification.js`** が種別で切り替えます。送信時の **From 表示名・メールヘッダー** は **`mail/sendConsultationMail.js`** で切り替えます。
- テンプレート: `mail/templates/normalConsultation.js`, `mail/templates/priorityGuidance.js`
- Gmail でのフィルタ・通知の設定手順: リポジトリ **`docs/gmail_notification_setup.md`**

## Gmail が届かないとき

1. **このリポジトリの最新版を Render に再デプロイ**しているか確認してください（メール送信はサーバー側コードが必要です）。
2. Render の **Environment** に次をすべて設定してください。

| 変数 | 説明 |
|------|------|
| `RESEND_API_KEY` | [Resend](https://resend.com) の API キー |
| `ADMIN_EMAIL` | 通知を受け取る Gmail（開発者） |
| `MAIL_FROM` | Resend で検証済みの送信元（例: `AuraFace <onboarding@resend.dev>` または独自ドメイン） |
| `BASE_URL` | **このサービスの公開 URL**（末尾スラッシュなし）。例: `https://kami-chat-server.onrender.com`。メール内「返信ページを開く」リンクに使います。 |
| `TOKEN_SECRET` | 本番では長いランダム文字列（返信リンクの署名用） |
| `TOKEN_EXPIRES_HOURS` | 任意。デフォルト 168（7日） |
| `CONSULTATION_URGENT_JST_HOUR_START` | 任意。**至急**を JST の時刻帯に限定するときのみ、`END` とセットで 0–23。未設定なら **24 時間**受付。 |
| `CONSULTATION_URGENT_JST_HOUR_END` | 任意。上とセット（例: `10` と `23` で 10:00–23:59）。片方だけでは無効。 |

未設定の場合も `POST /api/chat/send` は **200** でチャットはメモリに保存されますが、レスポンスは `mailSent: false` / `status: "saved_but_mail_failed"` になります。アプリはオレンジの SnackBar で知らせます。

至急が時間外のとき（上記 `START`/`END` を**両方**設定した場合のみ）、`priority_guidance` は **403**、`status: "error"` で拒否されます（メモリにも保存しません）。

### 至急なのに Gmail が「通常相談」になるとき

1. **Render** の Web Service で **Root Directory** が `kami_chat_server` になっているか、**Manual Deploy** で最新コミットが載っているか確認する（古い `index.js` だと `consultationType` が無視される）。
2. ログの `[chat/send] consultationType` で `raw` / `normalized` が `priority_guidance` か確認する。`[sendConsultationMail][URGENT]` が出ていれば Resend まで至急テンプレで送っている。
3. Flutter **リリース**は `kMailBridgeProductionUrl` 固定でこのサービスに送る。実機で以前「接続先を設定」した URL は占い相談では使われない。

4. **至急で始めたのに追記だけ通常メールになる**とき: アプリの「開発者とのやりとり」は、追記の `consultationType` を **GET `/api/chat/thread` の先頭ユーザー発言**に合わせる（共有設定だけに依存しない）。`messages[].consultationType` が JSON に含まれることを Render ログで確認する。

## ローカル

```bash
npm install
cp .env.example .env   # なければ .env を手作り
# .env に上記変数を設定
node index.js
```

## テスト

```bash
node scripts/send-receive-send-test.js http://127.0.0.1:3000
```

相談通知メールの件名・本文組み立てのみ（Resend 不要）:

```bash
npm run test:consultation-mail
```
