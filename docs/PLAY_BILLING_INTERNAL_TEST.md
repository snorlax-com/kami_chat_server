# Google Play Billing 内部テスト手順

## 商品 ID（Play Console と完全一致）

| 種別 | 商品 ID | 価格（参考） |
|------|---------|-------------|
| 月額サブスク | `subscription_monthly_500` | ¥500 |
| 通常相談券 | `normal_ticket_600` | ¥600 |
| 至急相談券 | `urgent_ticket_10000` | ¥10,000 |

旧 ID（`monthly_subscription_500` 等）はクエリ互換のみ。Play Console には上記 3 つを登録してください。

---

## Play Console で設定すべき項目

### 1. アプリ
- パッケージ名: `com.auraface.kami_face_oracle`
- **内部テスト**トラックに AAB/APK をアップロード

### 2. 収益化 → 商品
- **定期購入**: `subscription_monthly_500`（基本プラン 1 件、月額 ¥500）
- **アプリ内商品（消耗型）**:
  - `normal_ticket_600`
  - `urgent_ticket_10000`

### 3. ライセンステスト
- 設定 → ライセンステストにテスターの Gmail を追加
- テスター端末の Play ストアは**同じ Google アカウント**でログイン

### 4. サーバー（Render `kami_chat_server`）
| 環境変数 | 内容 |
|---------|------|
| `GOOGLE_PLAY_PACKAGE_NAME` | `com.auraface.kami_face_oracle` |
| `GOOGLE_APPLICATION_CREDENTIALS` | サービスアカウント JSON のパス |
| Firebase 認証 | 購入検証 API はログイン必須 |

サービスアカウントに Play Console → ユーザーと権限 → **「注文とサブスクリプションの管理」** を付与。

---

## 内部テスト手順

1. Play Console で内部テスト版をリリース（審査不要、テスター追加後数時間で反映）
2. テスター端末で内部テスト参加リンクからインストール（**ADB 直インストール不可**）
3. AuraFace 起動 → **Google ログイン**（匿名のみではサーバー検証・券付与不可）
4. 通知許可（任意）
5. ストアタブ → **サブスクに加入** → 画面下から **Google Play 購入シート**が表示される
6. 購入完了後、サーバー検証 → 券残高反映
7. 通常券・至急券も同様に **購入** ボタン → Play 公式画面

---

## テスト用チェックリスト

### 購入フロー
- [ ] ストアで商品価格が Play から表示される（「商品情報を読み込み中」で止まらない）
- [ ] サブスクボタンで Play 購入シート（下から）が開く
- [ ] 通常券・至急券ボタンで Play 購入シートが開く
- [ ] 購入キャンセル時にエラーにならずストアに戻れる
- [ ] 購入成功後 `acknowledgePurchase`（`completePurchase`）が実行される
- [ ] 購入成功後サーバー `/api/billing/verify` が 200
- [ ] 検証成功後のみ券残高が増える

### アカウント分離
- [ ] アカウント A で購入した券がアカウント B に表示されない
- [ ] ログアウト → 別アカウントログインで残高が切り替わる
- [ ] サブスク加入状態もアカウントごとに独立

### 復元・同期
- [ ] ストアの **購入を復元** で `restorePurchases` が動作
- [ ] アプリ再起動後もログインアカウントの残高がサーバーから同期される

### 相談送信
- [ ] 通常券・至急券送信時にサーバー `/api/billing/consume` で残高が減る

---

## 実装ファイル一覧

### Flutter（クライアント）
| ファイル | 役割 |
|---------|------|
| `lib/config/play_billing_products.dart` | 商品 ID 定数 |
| `lib/services/iap_service.dart` | Play Billing 接続・購入・acknowledge |
| `lib/services/billing_server_sync_service.dart` | verify / status / consume API |
| `lib/services/billing_account_service.dart` | アカウント別同期・口座切替 |
| `lib/services/billing_account_status.dart` | 残高 DTO |
| `lib/services/consultation_ticket_service.dart` | アカウント別券キャッシュ |
| `lib/services/consultation_subscription_service.dart` | アカウント別サブスクキャッシュ |
| `lib/ui/pages/store_page.dart` | ストア UI・購入ボタン |
| `lib/ui/pages/developer_chat_page.dart` | 送信時券消費 |
| `assets/data/consultation_subscription.json` | サブスク定義 |
| `assets/data/consultation_ticket_products.json` | 券商品定義 |
| `android/app/build.gradle.kts` | `billing:7.1.1` |

### サーバー
| ファイル | 役割 |
|---------|------|
| `kami_chat_server/routes/billing.js` | verify / status / consume |
| `kami_chat_server/identityDb.js` | purchases / subscriptions / tickets |

---

## トラブルシュート

| 症状 | 確認 |
|------|------|
| 購入シートが出ない | 内部テスト版からインストールしているか、Play にログインしているか |
| `notFoundIDs` | Play Console 商品 ID・公開状態・反映待ち（最大数時間） |
| 購入成功だが券が増えない | Google ログイン済みか、`/api/billing/verify` ログ |
| 503 課金検証 | サーバー env `GOOGLE_PLAY_PACKAGE_NAME` / サービスアカウント |

ログ: `adb logcat | grep BILLING`
