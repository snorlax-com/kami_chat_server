import 'package:flutter/foundation.dart';

/// ストア課金の運用設定。
class StoreBillingConfig {
  StoreBillingConfig._();

  /// debug のみ Play 未連携時のローカル付与（release では無効＝無料回避）。
  static bool get allowAppStoreWhenPlayMissing => kDebugMode;

  /// Google Play 課金を優先する（Android 本番）。
  static bool get preferGooglePlay => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// release Android では Play で検証できたサブスクのみ有効。
  static bool get requirePlayVerifiedAccess => preferGooglePlay && !kDebugMode;

  /// Play 商品未取得かつ sideload インストール時、明示確認付きテスト購入を許可。
  static bool get allowSideloadTestPurchases => preferGooglePlay;
}
