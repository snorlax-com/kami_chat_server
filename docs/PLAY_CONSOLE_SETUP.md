# Google Play Console 設定手順（AuraFace）

このドキュメントは **Play Console 上で人が行う作業** のチェックリストです。  
商品 ID・パッケージ名は `lib/config/play_billing_products.dart` と **完全一致** させてください。

---

## 0. 事前情報（コピー用）

| 項目 | 値 |
|------|-----|
| アプリ名（表示） | AuraFace |
| パッケージ名 | `com.auraface.kami_face_oracle` |
| 現在のバージョン（pubspec） | `1.0.0`（versionCode `76`） |
| 課金権限 | `com.android.vending.BILLING`（Manifest 済み） |

指紋・AAB ビルドはターミナルで:

```bash
cd kami_face_oracle
./scripts/play_console_prepare.sh
```

---

## 1. アプリの作成（未作成の場合）

1. [Google Play Console](https://play.google.com/console) にログイン
2. **アプリを作成** → デフォルト言語（日本語）→ アプリ名 **AuraFace**
3. 種別: **アプリ** / 無料（アプリ本体は無料、課金はアプリ内）

---

## 2. アプリの整合性（署名）

1. **リリース** → **アプリの整合性**
2. **Play アプリ署名** を有効化（推奨・初回のみ）
3. **アップロード鍵の証明書** に、リリース用 keystore の **SHA-1 / SHA-256** を登録  
   - ローカルで `./scripts/play_console_prepare.sh` の出力を貼る
4. Firebase を使う場合: Firebase Console → プロジェクト設定 → Android アプリ → **同じ SHA-1** を追加

> 現状 `android/app/build.gradle.kts` の release は debug 署名のままです。  
> **内部テスト公開前** に release 用 `keystore.jks` を作成し、`signingConfigs.release` を設定してください。

---

## 3. 収益化 → 商品の作成

**収益化** → **商品** で以下を **正規 ID** で登録（旧 ID は新規作成不要。アプリは互換クエリのみ）。

### 3.1 定期購入（サブスクリプション）

| 項目 | 値 |
|------|-----|
| 商品 ID | `monthly_subscription_500` |
| 名前（ユーザー向け） | 例: 占い相談サブスク（月額） |
| 説明 | サブスク加入でストア・占い相談が利用可能 |
| 請求期間 | 1 か月 |
| 価格 | ¥500（日本） |
| 基本プラン | 1 件作成（例: `monthly-base`） |
| 状態 | **有効** にして保存 |

### 3.2 アプリ内商品（消耗型）

| 商品 ID | 種別 | 価格目安 | 名前例 |
|---------|------|----------|--------|
| `normal_ticket_600` | 消耗型（マネージド） | ¥600 | 通常質問券 |
| `urgent_ticket_10000` | 消耗型（マネージド） | ¥10,000 | 至急質問券 |

各商品:

1. **商品 ID** を上表どおり（変更不可のため慎重に）
2. **購入の種類**: 消耗型
3. **デフォルトの価格** を設定
4. **有効** にして保存

反映まで **最大数時間** かかることがあります。

---

## 4. ライセンステスト

1. **設定** → **ライセンステスト**
2. テスト用 Gmail を追加（エミュ・実機で Play にログインするアカウント）
3. ライセンス応答: **LICENSED**（通常はデフォルト）

これで実課金なしの「テスト購入」が可能になります。

---

## 5. 内部テストトラック

1. **テストとリリース** → **内部テスト** → **新しいリリースを作成**
2. AAB をアップロード:

```bash
cd kami_face_oracle
flutter build appbundle --release
# 出力: build/app/outputs/bundle/release/app-release.aab
```

3. リリースノートを入力 → **レビューに送信** → **内部テストに公開**
4. **テスター** タブ → **メールリスト** を作成 → テスターの Gmail を追加
5. **オプトイン URL** をコピーし、テスター端末のブラウザで開く
6. Play ストアから **AuraFace をインストール**（ADB 直インストールでは課金が動かない場合あり）

---

## 6. Google Play Developer API（サーバー購入検証）

アプリ購入後の `POST /api/billing/verify` 用です（`kami_chat_server`）。

### 6.1 Google Cloud

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクト選択（Firebase と同じで可）
2. **API とサービス** → **ライブラリ** → **Google Play Android Developer API** を **有効化**
3. **IAM と管理** → **サービス アカウント** → 作成
4. キー（JSON）をダウンロード → サーバーに `secure/google-service-account.json` として配置（git に含めない）

### 6.2 Play Console で API 権限

1. Play Console → **ユーザーと権限**
2. 上記サービスアカウントのメールを **招待**
3. 権限: 少なくとも **財務データの表示**、**注文とサブスクリプションの管理**（購入検証に必要）

### 6.3 サーバー環境変数

`kami_chat_server/.env`（本番は Render 等のシークレット）:

```env
GOOGLE_PLAY_PACKAGE_NAME=com.auraface.kami_face_oracle
GOOGLE_APPLICATION_CREDENTIALS=./secure/google-service-account.json
```

---

## 7. 動作確認チェックリスト

端末条件:

- [ ] **Google Play 対応** エミュレータまたは実機
- [ ] Play ストアに **ライセンステスト用 Gmail** でログイン
- [ ] アプリは **内部テスト経由でインストール**

アプリ内:

- [ ] 占い相談 → 券不足 → ストア → **購入** タップで **下から Play ボトムシート**（テスト購入ダイアログではない）
- [ ] `adb logcat | grep BILLING` で `launchBillingFlow ... started=true`
- [ ] サブスク加入後、通常券・至急券がストアに表示される

ログのよくある原因:

| ログ / 現象 | 対処 |
|-------------|------|
| `isAvailable=false` | Play ログイン・内部テスト参加・商品「有効」待ち |
| `No account found`（Finsky） | エミュの Play ストアに Google アカウント追加 |
| `ITEM_NOT_FOUND` | 商品 ID の typo・反映待ち |
| `テスト購入` ダイアログ | ADB 直インストール → Play から入れ直し |

---

## 8. 本番公開前

- [ ] release 署名 keystore を Play のアップロード鍵として登録
- [ ] 商品 3 点がすべて **有効**
- [ ] プライバシーポリシー URL・データ安全のフォーム
- [ ] 内部テストで課金・サーバー検証まで完了

関連: [PLAY_BILLING_SETUP.md](./PLAY_BILLING_SETUP.md)
