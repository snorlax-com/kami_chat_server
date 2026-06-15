# AuraFace Maestro E2E

Android エミュレータ上で AuraFace の主要フローを検証する Maestro テスト一式です。

## アプリ ID

`com.auraface.kami_face_oracle`

## 前提

- macOS + Android Studio（JBR / Java 21）
- Flutter SDK
- AVD: `Medium_Phone_API_36.1`（変更時は `MAESTRO_AVD`）
- **テスト用 Google アカウント A / B**（ログイン・切替テスト用）
- **Google Play テスト購入**（本番決済が走らないライセンステスター設定）

## セットアップ

```bash
cd kami_face_oracle
bash maestro/setup_maestro_env.sh
```

## 全テスト実行

```bash
bash maestro/run_all_tests.sh
```

## 画面を閉じても・Macスリープ中も継続（推奨）

**11本すべて完走するまで自動リトライ:**

```bash
bash maestro/start_watchdog.sh
tail -f test-results/maestro/watchdog.log
```

- `nohup` + `caffeinate -dims` で Mac スリープ抑止
- エミュレータ切断・途中停止時は最大30回まで再実行
- 完走時: `test-results/maestro/suite.completed` が作成される
- 停止: `kill $(cat test-results/maestro/watchdog.pid)`

### 1回だけ実行

```bash
bash maestro/run_all_tests_background.sh
```

## 結果

- JUnit: `test-results/maestro/junit/*.xml`
- スクリーンショット・デバッグ: `test-results/maestro/debug/<test名>/`

## テスト一覧

| ファイル | 内容 |
|---------|------|
| `00_launch.yaml` | 起動・年齢確認・メイン画面 |
| `01_tutorial.yaml` | チュートリアル・ログイン誘導 |
| `02_login.yaml` | Google ログイン UI |
| `03_free_trial.yaml` | 無料2回不可→サブスク案内（現仕様） |
| `04_store_subscription.yaml` | サブスク加入（テスト加入 / Play） |
| `05_ticket_purchase.yaml` | 通常券600円・至急券10000円 |
| `06_message_send.yaml` | 相談送信・券消費 |
| `07_logout_switch_account.yaml` | ログアウト・他アカウント券不可 |
| `08_settings_account_delete.yaml` | 設定・解約手順（削除UIは未実装） |
| `09_chat_scroll.yaml` | チャット表示・スクロール |
| `10_error_handling.yaml` | エラー時クラッシュなし |

## 現アプリ仕様との差分（重要）

1. **無料1回体験は廃止** — 初回からサブスク+券が必要。`03_free_trial.yaml` は「2回無料不可」を検証。
2. **アカウント削除 UI は未実装** — `08` はログアウト・解約手順のみ検証。
3. **Google ログイン / Play 購入** — エミュレータに Google アカウント・Play テスト設定が必要。未設定時は UI 到達まで自動、完了は手動確認。
4. **券・サブスクは端末ローカル + サーバー検証** — アカウント切替テストは実 Google アカウント A/B 推奨。

## 最重要チェック（手動併用推奨）

- アカウント A の券が B で使えない
- サブスク未加入で送信不可
- ログアウト後に他アカウントのローカル状態が残らない
- ログイン前に有料サーバー処理が走らない（チュートリアル送信前）
