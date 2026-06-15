import 'package:flutter/foundation.dart';
import 'package:kami_face_oracle/core/integration_test_flags.dart';

/// ストア課金の運用設定。
class StoreBillingConfig {
  StoreBillingConfig._();

  /// Android では常に Google Play のみ。Web / 非 Android debug のみローカル付与可。
  static bool get allowAppStoreWhenPlayMissing => kDebugMode && !preferGooglePlay;

  /// Google Play 課金を優先する（Android 本番）。
  static bool get preferGooglePlay => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// release Android では Play で検証できたサブスクのみ有効。
  static bool get requirePlayVerifiedAccess => preferGooglePlay && !kDebugMode;

  /// Play 商品未取得かつ sideload インストール時、明示確認付きテスト購入を許可。
  static bool get allowSideloadTestPurchases =>
      preferGooglePlay && !IntegrationTestFlags.forcePlayBilling;
}
