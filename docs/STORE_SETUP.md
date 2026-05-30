# ストア（Google Play 課金）セットアップ

AuraFace のストアは **月額サブスク** と **消耗型相談券** を Google Play で販売します。

## アプリ側の商品 ID（Play Console と完全一致）

| 商品 ID | 種類 | 表示名 | 価格（参考） |
|---------|------|--------|--------------|
| `monthly_subscription_500` | 定期購入 | 月額サブスク | ¥500/月 |
| `normal_ticket_600` | 消耗型 | 通常質問券 1枚 | ¥600 |
| `urgent_ticket_10000` | 消耗型 | 至急質問券 1枚 | ¥10,000 |

- サブスク定義: `assets/data/consultation_subscription.json`
- 消耗型定義: `assets/data/consultation_ticket_products.json`
- IAP 処理: `lib/services/iap_service.dart`
- アクセス制御: `lib/services/consultation_access_service.dart`
- 画面: `lib/ui/pages/store_page.dart`（タブ「ストア」）

パッケージ名（Android）: `com.auraface.kami_face_oracle`

---

## 課金フロー

```
チュートリアル完了 → 占い相談タブで質問
  ↓ サブスク未加入
ストアへ誘導 → 月額 ¥500 サブスク加入
  ↓ 初回特典（1ユーザー1回のみ）
通常質問券 1枚付与 → 初回質問可能
  ↓ 2回目以降
通常券 ¥600 または 至急券 ¥10,000 を購入して質問
```

### サブスク（`monthly_subscription_500`）

- `buyNonConsumable` → 購入成功後 `completePurchase`（acknowledge）
- 初回加入時のみ通常券1枚（`has_received_subscription_bonus_v1` フラグで重複防止）
- 起動時・ストア表示時・質問画面表示時に `queryPastPurchases` で状態同期

### 消耗型（`normal_ticket_600` / `urgent_ticket_10000`）

- `buyConsumable`（`autoConsume: true`）→ 購入成功後 `completePurchase`
- 通常券 → `normalTickets += 1`
- 至急券 → `urgentTickets += 1`（優先券）
- 同一 `purchaseID` への二重付与は `iap_purchase_ack_store.dart` で防止

---

## Google Play Console 手順

### 1. 定期購入

1. **収益化** → **定期購入** → **定期購入を作成**
2. 商品 ID: `monthly_subscription_500`
3. 基本プラン: ¥500 / 1 month
4. **有効** にしてアプリと紐付け

### 2. 消耗型アイテム

1. **収益化** → **アプリ内アイテム** → **商品を作成**
2. 商品 ID: `normal_ticket_600` / `urgent_ticket_10000`
3. **商品タイプ: 消耗型**（Consumable）
4. 価格を設定し **有効** にする

### 3. テスト

1. 内部テストトラックに AAB をアップロード
2. **ライセンステスト** にテスト用 Google アカウントを追加
3. Play 経由でインストール（ADB 直インストールのみだと商品クエリが空になることがある）

---

## アプリ内の表示

### ストア画面

- 月額サブスク ¥500（初回特典説明付き）
- 通常質問券 ¥600
- 至急質問券 ¥10,000
- サブスク状態・券残数

### 占い相談画面

- サブスク状態・通常券・至急券残数
- 未加入時: 送信無効 + 「ストアへ移動」
- 券0枚時: 600円/10,000円の購入選択ダイアログ → ストアへ

---

## Play 未連携時（sideload / 開発）

`lib/config/store_billing_config.dart` の `allowAppStoreWhenPlayMissing = true` により、
Play 商品が取得できない場合はアプリ内フォールバック購入が可能（テスト用）。

---

## Apple App Store（iOS）

Android 版を優先実装。iOS 側は `defaultTargetPlatform` で分岐し、
同一商品 ID を App Store Connect に登録すれば共有可能。

---

## チェックリスト

- [ ] Play Console に定期購入 `monthly_subscription_500`
- [ ] Play Console に消耗型 2商品（ID 一致）
- [ ] 内部テストトラックに AAB アップロード
- [ ] ライセンステスター追加
- [ ] サブスク加入 → 初回通常券1枚
- [ ] 通常券/至急券購入 → 残数増加
- [ ] 占い相談送信 → 券1枚減少
