# ストア（相談券 IAP）セットアップ

AuraFace のストアは **相談券パック** を Google Play / App Store で販売し、購入1件につき端末に相談券を付与します（1枚＝占い相談の送信1回）。

## アプリ側の商品 ID（変更不可で Play と一致させる）

| 商品 ID | 表示名 | 付与枚数 | 参考価格（円） |
|---------|--------|----------|----------------|
| `gem_pack_small` | 相談券 1枚 | 1 | 120 |
| `gem_pack_medium` | 相談券 5枚 | 5 | 480 |
| `gem_pack_large` | 相談券 10枚 | 10 | 880 |
| `gem_pack_xlarge` | 相談券 20枚 | 20 | 1580 |

- 定義: `lib/services/consultation_ticket_packs_service.dart`
- IAP 処理: `lib/services/iap_service.dart`（**消耗型** `buyConsumable`）
- 画面: `lib/ui/pages/store_page.dart`（タブ「ストア」）

パッケージ名（Android）: `com.auraface.kami_face_oracle`

---

## Google Play Console 手順

1. **Google Play Console** → アプリ **AuraFace** を選択
2. **収益化** → **アプリ内アイテム** → **商品を作成**
3. 上表の **商品 ID** をそのまま入力（例: `gem_pack_small`）
4. **商品タイプ: 消耗型**（Consumable）を選択  
   - 非消耗型だと再購入できません
5. 名前・説明をアプリ表示に合わせる（例: 「相談券 1枚」「占い相談を1回分」）
6. 価格を設定（参考価格は Console 上で任意に調整可）
7. **有効** にして保存
8. 4商品すべて登録後、**内部テスト** または **クローズドテスト** トラックに APK/AAB をアップロード
9. **ライセンステスト** にテスト用 Google アカウントを追加（設定 → ライセンステスト）
10. テスト端末で Play ストアにそのアカウントでログインし、実機で購入テスト

### よくある原因（「商品が見つかりません」）

- 商品 ID の typo（アプリと Console で完全一致が必要）
- 商品が **下書き** のまま（**有効** になっているか）
- アップロードした **署名付きビルド** の `applicationId` が `com.auraface.kami_face_oracle` と一致していない
- テストトラックに参加していないアカウントでインストールしている
- Play 反映まで **数時間** かかることがある → ストア画面の「再読み込み」

### 実機デバッグ（ADB 直インストール）の注意

`flutter install` で入れた **release APK を直接入れただけ** だと、Play 課金の商品クエリが空になることがあります。IAP 検証には **Play 経由でインストールしたビルド**（内部テスト等）を使ってください。

---

## Apple App Store（将来 / iOS）

1. App Store Connect → アプリ内課金 → **消耗型**
2. 上記と同じ **商品 ID** を登録
3. 価格ティアを設定し、審査用スクリーンショットを添付

---

## 購入後の動作

1. 購入完了 → `ConsultationTicketService` に相談券を加算
2. 占い相談タブで送信 → `validateNormalSend` → 成功時 `consumeNormalTicket` で1枚消費
3. 同一 `purchaseID` への二重付与は `iap_purchase_ack_store.dart` で防止

---

## チェックリスト

- [ ] Play Console に消耗型 4商品（ID 一致）
- [ ] 内部テストトラックに AAB アップロード
- [ ] ライセンステスター追加
- [ ] テスト端末でストアタブに価格表示・購入・券増加
- [ ] 占い相談で送信→券1枚減少
