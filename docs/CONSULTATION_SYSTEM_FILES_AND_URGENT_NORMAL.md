# 占い相談（メールブリッジ）関連ファイル一覧と「至急／通常」の区別

本ドキュメントは、**占い相談 → kami_chat_server → Resend → Gmail** の経路に関わる **Flutter / Node / スクリプト / 設定** を一覧し、**通常相談**と**至急（優先導き）**の区別の仕方をまとめたものです。

---

## 1. 用語と値（API で共通）

| 概念 | 定数値 | 意味 |
|------|--------|------|
| 通常相談 | `normal` | 通常の件名・差出人テンプレ |
| 至急（優先導き） | `priority_guidance` | 至急用件名・差出人・メールヘッダー |

Flutter 側の文字列定義: `lib/config/consultation_mail_types.dart`  
サーバー側の正規化・解決: `kami_chat_server/constants/consultationTypes.js`

---

## 2. 至急と通常の区別の仕方（全体像）

### 2.1 アプリ（Flutter）

1. **占い相談画面**（`ConsultationPage`）でユーザーが **「通常相談」** か **「至急相談」** を押す。
2. `_send(urgent: false | true)` が呼ばれ、本文に `AuraFaceChatMailService.applyNewUrgentConsultationPrefix` を適用したうえで **`ConsultationMailNewSend.send` → `AuraFaceChatMailService.sendLockedNewConsultation`** で送信する（新規相談専用。追記は `send()`）。
   - 至急: `ConsultationMailType.priorityGuidance`（= 文字列 `priority_guidance`）
   - 通常: `ConsultationMailType.normal`
3. **券・枠**（至急は優先券＋1日の至急枠）: `ConsultationTicketService` で検証・消費。
4. **HTTP POST** `POST {baseUrl}/api/chat/send` の JSON には少なくとも次が含まれる:
   - `consultationType`: `normal` / `priority_guidance`
   - `urgent`: 至急なら `true`
   - `consultationPriority`: 至急なら `2`、通常なら `1`
   - ヘッダー `X-AuraFace-Consultation-Type`: 上と同じ文字列
   - `message` 末尾に機械可読マーカー（サーバーが保存・メール前に除去）  
     `\n\n__AURAFACE_SEND_TIER__:priority_guidance__` または `...:normal__`  
     → 中間で JSON の種別フィールドだけ欠けても **`message` が残る経路**向けの冗長。
5. **本番の接続先**: `lib/config/mail_bridge_config.dart` の `kMailBridgeProductionUrl`（例: Render）。  
   リリース／プロファイルでは `AuraFaceChatMailService.consultationSendBaseUrl` により **本番 URL を優先**（古い `mail_bridge_base_url` に流されにくくする）。

### 2.2 サーバー（kami_chat_server）

`POST /api/chat/send` で **種別を解決**し、メモリに保存する `consultationType` と **Resend 用テンプレ**に渡す。

**解決の優先順位**（`resolveConsultationTypeFromSendBody`、概略）:

1. リクエスト body の `consultationType` または `consultation_type` が **非空** → 正規化して採用（明示 `normal` は至急に上書きしない）。
2. 上記が無い場合、`message` から **埋め込みマーカー**を解析。
3. 無い場合、HTTP ヘッダー `X-AuraFace-Consultation-Type`。
4. 無い場合、`consultationPriority` / `consultation_priority` が `2`。
5. 無い場合、`urgent` が真（bool / 数値 / 文字列の一部）。
6. それ以外は `normal`。

**至急の受付時間外**（任意）: 環境変数 `CONSULTATION_URGENT_JST_HOUR_START` / `END` を **両方**設定しているときのみ、`priority_guidance` は **403** で拒否（メールも送らない）。未設定なら **24時間**至急可（`config/urgentReception.js`）。

**本文先頭 `（緊急）`**: 至急として保存・メールする直前に `constants/consultationTypes.js` の `ensurePriorityGuidanceBodyPrefix` でサーバー側も付与（クライアント漏れの救済）。クライアントは `AuraFaceChatMailService.applyNewUrgentConsultationPrefix` で同趣旨。

**メール（Resend）**: `mail/sendConsultationMail.js` が `consultationType` に応じて件名・差出人・HTML/テキスト・ヘッダー（`List-Id` 等）を切り替え。**宛先**は `mail/resolveConsultationNotificationRecipients.js` で一元化する。

| 種別 | Resend の `to`（重複は除去） |
|------|------------------------------|
| `normal` | 主宛先 1 件: `MAIL_TO_NORMAL` → なければ `DEV_NOTIFICATION_EMAIL` → なければ `ADMIN_EMAIL` |
| `priority_guidance` | 上記の主宛先（`MAIL_TO_PRIORITY` 優先）に加え、**第2宛先**（`EMERGENCY_NOTIFICATION_EMAIL`、未設定時は `emergencyauraface@gmail.com`）。**宛先が2件のときは Resend へ宛先ごとに 1 通ずつ送信**（Gmail のスレッド統合等で第2宛が見えない問題の回避）。 |

環境変数の例は `kami_chat_server/.env.example` とルート `render.yaml` のコメントを参照。

### 2.3 レガシー実装（参考）

`auraface-chat-mail-bridge/` は別系統の Node サーバー（Zod + SQLite 等）。**Render の Root Directory を誤るとこちらが動き**、以前は種別を無視して同じ件名になることがあった。現在は Zod スキーマとマーカー・ヘッダーに対応した版がリポジトリに含まれる。**本番は `kami_chat_server` をデプロイする想定**（`render.yaml` の `rootDir: kami_chat_server`）。

---

## 3. Flutter ファイル（パスと役割）

| パス | 役割 |
|------|------|
| `lib/config/consultation_mail_types.dart` | `normal` / `priority_guidance` 定数 |
| `lib/config/consultation_send_contract.dart` | 新規送信の種別決定（ボタン押下のみ）・`ConsultationSendSource`（logcat 用） |
| `lib/config/mail_bridge_config.dart` | 本番 URL `kMailBridgeProductionUrl` |
| `lib/services/auraface_chat_mail_service.dart` | `POST/GET` チャットAPI、埋め込みマーカー、ヘッダー、至急本文接頭辞、`sendLockedNewConsultation`、リリース時 `print`（logcat タグ **`AuraFaceMailSend`**） |
| `lib/services/consultation_mail_new_send.dart` | 新規相談のみ `sendLockedNewConsultation` へ委譲（至急/通常の取り違え防止） |
| `lib/services/consultation_ticket_service.dart` | 通常券・優先券・至急1日枠の検証・消費 |
| `lib/services/developer_chat_pref.dart` | アクティブ `chatId` と種別の永続化（追記メール用） |
| `lib/services/developer_chat_unread_service.dart` | 未読判定（スレッド取得、本番 URL 解決） |
| `lib/services/cloud_service.dart` | Firestore 利用時の相談履歴（`consultationType` / `urgent` 保存） |
| `lib/ui/pages/consultation_page.dart` | **メイン占い相談 UI**・送信・SnackBar（サーバー応答と至急の不一致警告） |
| `lib/ui/pages/consultation_page_new.dart` | メールベース相談（別フロー、同じ mail service） |
| `lib/ui/pages/consultation_mail_bridge_test_page.dart` | 開発用接続テスト・手動送信 |
| `lib/ui/pages/developer_chat_page.dart` | 開発者返信・追記（スレッド先頭 user の `consultationType` を優先） |
| `lib/ui/pages/pillar_chat_page.dart` | 柱チャットからの開発者通知（種別は通常固定） |
| `lib/ui/pages/home_page.dart` | 占い相談・テストページへの遷移 |
| `lib/app_widgets.dart` | E2E 時のみ `ConsultationPage` をホームにする分岐 |
| `lib/services/remote_config_service.dart` | コスト等 Remote Config（**メールブリッジ URL の上書きは行わない**） |

**統合テスト**: `integration_test/consultation_mail_test.dart`  
**ミニ版リポジトリ内のコピー**: `github_chat_minimal/lib/...`（本番アプリのソース・オブとは別扱いでよい）

---

## 4. kami_chat_server（Node）ファイル

| パス | 役割 |
|------|------|
| `kami_chat_server/index.js` | `POST /api/chat/send`, `GET /api/chat/thread`, 管理画面ルート、種別ログ |
| `kami_chat_server/constants/consultationTypes.js` | 正規化、種別解決、**本文マーカー抽出** `extractEmbeddedConsultationTier`、至急本文接頭辞 `ensurePriorityGuidanceBodyPrefix` |
| `kami_chat_server/config/urgentReception.js` | 至急 JST 時間帯（任意） |
| `kami_chat_server/mail/resolveConsultationNotificationRecipients.js` | 種別に応じた通知先メールアドレス配列（主＋至急時の緊急宛、重複除去） |
| `kami_chat_server/mail/sendConsultationMail.js` | Resend 送信、`to` 配列、種別別件名・差出人・ヘッダー |
| `kami_chat_server/mail/buildConsultationNotification.js` | 通知 HTML/テキスト組み立て |
| `kami_chat_server/mail/buildAdminReplyUrl.js` | 返信 URL に `consultationType` クエリ |
| `kami_chat_server/mail/mailFrom.js` | `MAIL_FROM` の表示名差し替え |
| `kami_chat_server/mail/templates/normalConsultation.js` | 通常テンプレ |
| `kami_chat_server/mail/templates/priorityGuidance.js` | 至急テンプレ |
| `kami_chat_server/mail/utils.js` | メール用ユーティリティ |
| `kami_chat_server/token.js` | 返信トークン |
| `kami_chat_server/README.md` | 環境変数・トラブルシュート・種別説明 |

**テスト**

| パス |
|------|
| `kami_chat_server/test/consultation-type-resolve.test.js` |
| `kami_chat_server/test/consultation-notification.test.js` |
| `kami_chat_server/test/resolve-consultation-notification-recipients.test.js` |
| `kami_chat_server/test/urgent-reception.test.js` |
| `kami_chat_server/test/mailFrom.test.js` |

**補助スクリプト**: `kami_chat_server/scripts/send-receive-send-test.js`, `e2e-full-flow-test.js`, `render-production-smoke.js`

**npm**: `npm run test:consultation-mail` で上記テスト群を実行。

---

## 5. レガシー・その他

| パス | 役割 |
|------|------|
| `auraface-chat-mail-bridge/index.js` | 旧ブリッジ（種別・マーカー対応版。デプロイ先によってはこちらが動く） |
| `render.yaml` | Render Blueprint（`rootDir: kami_chat_server`） |
| `docs/gmail_notification_setup.md` | Gmail / フィルタ補足 |
| `docs/consultation_mail_loop_test_status.md` | ループテスト・スクリプト案内 |
| `docs/TESTING.md` | `consultation_mail_test.dart` の実行例 |
| `docs/e2e_render_chat_flow.md` | E2E 応答形式 |

**シェル（自動化）**

| パス |
|------|
| `scripts/consultation_and_mail_test.sh` |
| `scripts/consultation_mail_loop_test.sh` |
| `scripts/consultation_mail_auto_retry.sh` |
| `scripts/run_consultation_mail_test_android.sh` |

**実機インストール**: `install_on_device.sh`（`flutter install --release`）

---

## 6. 送信経路（新規は `sendLockedNewConsultation`／追記は `send`）と `sendSource`

| 画面 | ファイル | `sendSource` 定数 | 新規相談の `consultationType` | 実機での主な導線 |
|------|----------|-------------------|------------------------------|------------------|
| 占い相談（メイン） | `consultation_page.dart` | `consultation_page` | ボタン: 至急→`priority_guidance`、通常→`normal`（`ConsultationSendContract`） | **ホーム**「占い相談」→ `ConsultationPage`（`home_page.dart`）。E2E 時は `app_widgets.dart` でホーム直開きも同画面 |
| 占い相談（新UI） | `consultation_page_new.dart` | `consultation_page_new` | 同上 | 現状 `Navigator` からの参照なし（コード上は未接続の別画面） |
| 開発者チャット追記 | `developer_chat_page.dart` | `developer_chat_follow_up` | **スレッド先頭 user の `consultationType`**（無ければ Pref） | 占い相談送信後に保存された `chatId` から遷移した追記のみ |
| 柱チャット（チュートリアル） | `pillar_chat_page.dart` | `pillar_chat_tutorial` | 常に `normal` | 性格詳細などから `PillarChatPage` を開いたときの開発者通知 |
| ブリッジテスト | `consultation_mail_bridge_test_page.dart` | `consultation_mail_bridge_test_page` | テスト用（主に `normal`） | ホーム等からテストページを開いた開発者向け |

**実機ユーザーが「通常／至急」を選ぶのは基本的に `ConsultationPage` のみ**（`consultation_page_new` は未配線なら到達しない）。

---

## 7. 運用で確認するとよいログ

- **Render（kami_chat_server）**: `[chat/send] consultationType` の `raw` / `embeddedTier` / `normalized`。
- **実機 logcat（リリース）**: `adb logcat | grep AuraFaceMailSend`（1 行に URL・`sendSource`・種別・ヘッダー値・本文末尾プレビュー・応答の `debugResolved` 等）。

### 7.1 想定ログ例（リリース／実機・抜粋）

**通常相談を 1 回送った直後（本文は例）**

```text
I/flutter: [AuraFaceMailSend] pre_send sendSource=consultation_page url=https://kami-chat-server.onrender.com/api/chat/send chatId=consultation_user123_1712... consultationType=normal urgent=false consultationPriority=1 headerX-AuraFace-Consultation-Type=normal messageTail="...__AURAFACE_SEND_TIER__:normal__"
I/flutter: [AuraFaceMailSend] resp status=200 mailSent=true mailUrgent=false responseCt=normal subject=... build=v2-consultation-tier-r8-send-debug-fields debugResolved=normal
```

**至急相談を 1 回送った直後**

```text
I/flutter: [AuraFaceMailSend] pre_send sendSource=consultation_page url=https://kami-chat-server.onrender.com/api/chat/send chatId=consultation_user123_1712... consultationType=priority_guidance urgent=true consultationPriority=2 headerX-AuraFace-Consultation-Type=priority_guidance messageTail="...__AURAFACE_SEND_TIER__:priority_guidance__"
I/flutter: [AuraFaceMailSend] resp status=200 mailSent=true mailUrgent=true responseCt=priority_guidance subject=... build=v2-consultation-tier-r8-send-debug-fields debugResolved=priority_guidance
```

`WARN baseUrl!=本番定数` が出る場合は、インスタンスの `baseUrl` が `kMailBridgeProductionUrl` と不一致（古い `mail_bridge_base_url` や誤った `--dart-define=MAIL_BRIDGE_URL`）の疑いあり。

---

## 8. API レスポンスのデバッグ項目（POST /api/chat/send）

成功時 JSON に含まれる（サーバー実装: `kami_chat_server/index.js`）:

- `debugReceivedConsultationType` / `debugReceivedConsultationPriority` / `debugReceivedUrgent`
- `debugReceivedHeaderConsultationType`
- `debugEmbeddedTier`
- `debugResolvedConsultationType`
- `debugMailSubject` / `debugMailTo`（**配列**。至急時は主宛先＋緊急宛の複数要素になりうる）

Flutter は `SendChatResponse.sendDebug` にマップとして格納する。

---

## 9. クイック API 例（手動テスト）

```bash
# 至急
curl -sS -X POST "https://kami-chat-server.onrender.com/api/chat/send" \
  -H "Content-Type: application/json" \
  -d '{"userId":"t","chatId":"t-'$(date +%s)'","message":"test","userName":"u","consultationType":"priority_guidance"}'

# 通常
curl -sS -X POST "https://kami-chat-server.onrender.com/api/chat/send" \
  -H "Content-Type: application/json" \
  -d '{"userId":"t","chatId":"t-'$(date +%s)'","message":"test","userName":"u","consultationType":"normal"}'
```

レスポンスの `mailSubject` / `mailUrgent` / `mailApiBuild` で、サーバーがどう解釈したか確認できます。

---

*このファイルはリポジトリ内の実装に基づく索引です。デプロイ先・コミットが異なると挙動がずれるため、本番は Render のデプロイコミットと `Root Directory`（**必ず `kami_chat_server`**）も合わせて確認してください。*
