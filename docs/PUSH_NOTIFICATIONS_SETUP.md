# 開発者返信プッシュ通知（FCM）

## 概要

開発者が占い相談チャットに返信したとき、ログイン済みユーザーの端末へ FCM プッシュを送ります。

- **タイトル**: AuraFaceから新しい導きが届きました
- **本文**: 開発者から返信が届いています。タップして確認してください。
- **タップ時**: アプリを開き、下部タブの **占い相談** へ遷移（`chatId` があればそのスレッドを開く）

ユーザー自身の送信では通知しません（サーバーは `role: dev` のときのみ送信）。

## 必要な設定

### Firebase Console

1. プロジェクト `auraface-a609e` で **Cloud Messaging API** を有効化
2. **Android**: `android/app/google-services.json`（既存）
3. **iOS**: Firebase Console から iOS アプリを登録し、`ios/Runner/GoogleService-Info.plist` をダウンロードして配置
4. **iOS APNs**: Apple Developer で APNs キー（.p8）を作成し、Firebase Console → プロジェクト設定 → Cloud Messaging にアップロード

### Render（kami_chat_server）

既存の `FIREBASE_SERVICE_ACCOUNT_JSON` または `FIREBASE_SERVICE_ACCOUNT_JSON_B64` が必須（FCM 送信・トークン保存に Firestore Admin を使用）。

### iOS Xcode

1. Runner ターゲット → **Signing & Capabilities** → **Push Notifications** を追加
2. **Background Modes** → **Remote notifications** をオン
3. `Runner.entitlements` の `aps-environment` を配布用は `production` に変更（TestFlight / App Store）

## データ構造

Firestore:

```
users/{uid}/fcm_tokens/{docId}
  - token: string
  - platform: "android" | "ios"
  - updatedAt: timestamp
```

サーバー SQLite（重複防止）:

```
push_notification_log (chat_id, message_id, sent_at)
```

## テスト手順

1. 実機でログイン（匿名以外）
2. 通知許可を許可
3. ログで `[FcmToken] Firestore saved` またはサーバー `POST /api/fcm/register-token` が 200 か確認
4. 占い相談を1通送信（`chatId` と `userId` がサーバー SQLite `chat_threads` に登録されること）
5. 開発者返信: `POST /api/chat/dev-reply` または Gmail の返信リンク `/admin/reply`
6. 端末に通知 → タップで占い相談タブへ
7. **起動中 / バックグラウンド / 終了後** の3状態で確認
8. Android・iOS それぞれで確認

## トラブルシュート

| 現象 | 確認 |
|------|------|
| 通知が来ない | Render ログ `[push]`、FCM トークン有無、`chat_threads.user_id` |
| 重複通知 | `push_notification_log` で同一 messageId が1回だけか |
| iOS のみ不可 | GoogleService-Info.plist、APNs キー、Capabilities |
| トークン無効 | サーバーログ `invalidRemoved`、Firestore から当該トークン削除 |
