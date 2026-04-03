# kami_chat_server（Render 用チャット + Gmail 通知）

## Render でスレッド API が 404 になるとき

リポジトリ**ルート**でビルドしていると、古い `index.js` だけが動き **`GET /api/chat/thread` が無い**ことがあります。

**対処（どちらか）**

1. Render ダッシュボード → 該当 Web Service → **Settings** → **Root Directory** を **`kami_chat_server`** にして **Manual Deploy**  
2. リポジトリルートの **`render.yaml`**（`rootDir: kami_chat_server`）を Blueprint として同期

---

アプリ（Flutter）は `POST /api/chat/send` でここに相談を送り、**Resend** 経由で開発者の **Gmail（ADMIN_EMAIL）** に通知します。

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

未設定の場合も `POST /api/chat/send` は **200** でチャットはメモリに保存されますが、レスポンスは `mailSent: false` / `status: "saved_but_mail_failed"` になります。アプリはオレンジの SnackBar で知らせます。

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
