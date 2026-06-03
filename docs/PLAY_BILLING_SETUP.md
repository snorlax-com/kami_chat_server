# Google Play Billing テスト環境セットアップ

## 商品 ID（アプリ内定数）

| 種別 | 商品 ID | 価格目安 |
|------|---------|----------|
| 定期購入 | `subscription_monthly_500` | ¥500/月 |
| 消耗型 | `ticket_normal_600` | ¥600 |
| 消耗型 | `ticket_urgent_10000` | ¥10,000 |

定義: `lib/config/play_billing_products.dart`

旧 ID（`monthly_subscription_500` 等）は移行期間のみクエリに含めます。Play Console は **正規 ID** で登録してください。

## Play Console 設定

1. **アプリ** → **収益化** → **商品**
2. 定期購入: `subscription_monthly_500`（基本プラン 1 件）
3. アプリ内商品（消耗型）: `ticket_normal_600`, `ticket_urgent_10000`
4. **ライセンステスト** にテスターの Gmail を追加
5. **内部テスト** トラックに AAB/APK をアップロード
6. テスターを **メールリスト** に追加し、オプトイン URL から参加

## 内部テスト手順

1. Play Console で内部テスト版をリリース（審査不要だが初回は数時間かかる場合あり）
2. テスター端末で **同じ Google アカウント** で Play ストアにログイン
3. オプトインリンクから参加 → Play ストアでアプリを **インストール/更新**
4. アプリ起動 → ストアタブ → サブスク加入（テストカード・テスト購入）
5. 加入後: 通常券・至急券が表示されること
6. `adb logcat | grep BILLING` で `[BILLING]` ログ確認

## 実機での確認方法

```bash
cd kami_face_oracle
flutter build appbundle --release   # Play 提出用
# または内部テスト用 APK
flutter build apk --release
adb logcat -s flutter | grep BILLING
```

確認項目:

- [ ] 未加入時: サブスクのみ表示、券は非表示
- [ ] 加入後: 通常券・至急券表示・購入フロー起動
- [ ] 初回加入: 質問券 +1（重複なし）
- [ ] 「購入を復元」でサブスク状態復元
- [ ] 再起動後も加入状態維持

## よくある失敗原因

| 現象 | 原因 |
|------|------|
| ITEM_NOT_FOUND / 商品未取得 | Console の ID 不一致・反映待ち（最大数時間） |
| 課金画面が開かない | ADB 直インストール（Play 経由で再インストール） |
| テスト購入できない | ライセンステスト未登録・内部テスト未参加 |
| SERVICE_DISCONNECTED | Play ストア未ログイン・Play サービス更新 |
| 加入なのに券が出ない | 初回相談未送信（2 回目以降購入可のガード） |
| サブスクだけ復元できない | 別 Google アカウントで購入している |

## 本番前チェック

- [ ] Play Console 商品 ID が `play_billing_products.dart` と一致
- [ ] 署名キー（アップロードキー）が Console 登録 SHA と一致
- [ ] `com.android.vending.BILLING` 権限（AndroidManifest）
- [ ] 内部テストで実課金フロー確認済み
- [ ] サーバー `/api/billing/purchases` デプロイ（purchaseToken 保存）
- [ ] R8 有効化時 `proguard-rules-billing.pro` 適用済み

## サーバー連携

`POST /api/billing/purchases`（Bearer: Firebase ID Token）

実装例: `server/billing_api.js`
