/// Google サインイン用の **Web クライアント ID**（`….apps.googleusercontent.com`）。
///
/// **この定数が正（単一ソース）です。** 値を変えるときはここだけ直し、次を同一文字列に揃えてください。
/// - [android/app/google-services.json] の `oauth_client` および
///   `appinvite_service.other_platform_oauth_client` 内の **client_type 3** の `client_id`
///
/// Android の `android/app/build.gradle.kts` はこのファイルをパースして
/// `default_web_client_id` のフォールバック注入に使います（`oauth_client` が空のとき）。
/// 上書き: 環境変数 `GOOGLE_WEB_CLIENT_ID` または `android/local.properties` の
/// `googleWebClientId` / `GOOGLE_WEB_CLIENT_ID`（CI や端末ごとの差し替え用）。
///
/// `"oauth_client": []` のままだと ID トークンが取れず失敗しやすいです。
/// Firebase で SHA-1 を登録して JSON を取り直すか、上記 JSON の client_type 3 を手で揃えてください。
const String kGoogleOAuth2WebClientId =
    '848212343382-c589cku20fa5v5r77kvp5n6au2tgqd8k.apps.googleusercontent.com';
