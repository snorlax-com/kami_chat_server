/// Google サインイン用の **Web クライアント ID**（`….apps.googleusercontent.com`）。
///
/// [android/app/google-services.json] に `oauth_client` が並んでいれば通常は不要です。
/// `"oauth_client": []` のままだと ID トークンが取れず Google に接続できません。
///
/// 対処のどちらか:
/// 1. Firebase コンソール → プロジェクトの設定 → Android アプリに **署名の SHA-1** を登録し、
///    **google-services.json を再ダウンロード**して `android/app/` に置き直す（推奨）
/// 2. Firebase で **Web** アプリを追加し、表示される **ウェブクライアント ID** を
///    下の定数に貼る（`--dart-define=GOOGLE_WEB_CLIENT_ID=...` でも可）
/// 3. または `android/local.properties` に `googleWebClientId=…apps.googleusercontent.com`
///    を書くとビルド時に `R.string.default_web_client_id` へ注入される（google_sign_in が参照）
const String kGoogleOAuth2WebClientId = '';
