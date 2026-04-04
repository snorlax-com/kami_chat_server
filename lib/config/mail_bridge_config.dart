// メールブリッジ本番URLの設定
//
// ユーザーにサーバーURLを入力させません。開発者側で以下を設定してください。
//
// 【メール通知が失敗する理由】
// アプリは「メールブリッジ」サーバーにHTTPで送信し、そこからResendで開発者Gmailに届きます。
// 未設定のままでは接続先が 127.0.0.1 になり、実機では届きません。
//
// 【本番で届けるには】
// 1) kMailBridgeProductionUrl に Render 等の URL を設定してリビルドする。
// 2) その Render サービス側で Resend 用の環境変数を必ず設定する（未設定だと mailSent:false で届かない）。
//    RESEND_API_KEY, ADMIN_EMAIL, MAIL_FROM, BASE_URL（サービス自身の https URL）, TOKEN_SECRET
//    詳細: kami_chat_server/README.md
// 設定すれば実機でも「URLを設定してください」は出ず、そのサーバー経由でメール送信されます。
// 既存の Vultr サーバー（aura_server :8000）でチャットブリッジを :3000 で動かす場合は server/README.md「既存の Vultr サーバーで動かす」を参照。
// 例: ブリッジを https://api.yourdomain.com にデプロイした場合
//   const String kMailBridgeProductionUrl = 'https://api.yourdomain.com';
//
// 【実機で開発テストする場合】デバッグビルドで占い相談を送り、メール失敗時に表示される「接続先を設定」から、
// 同じWi-FiのPCのIP（例: http://192.168.1.10:3000）を1回だけ設定すれば、以降は届く。

/// 本番で使うチャットAPIのURL。Render デプロイ先に統一。
/// 占い相談（リリース）は [AuraFaceChatMailService.consultationSendBaseUrl] により常にここへ送る（
/// 開発用に保存した古い mail_bridge_base_url で至急が通常メールになるのを防ぐ）。
const String kMailBridgeProductionUrl = 'https://kami-chat-server.onrender.com';
