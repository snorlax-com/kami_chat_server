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

  /// debug + sideload のみ。release 実機では Play 課金を強制しテスト購入ダイアログは出さない。
  static bool get allowSideloadTestPurchases =>
      preferGooglePlay && kDebugMode && !IntegrationTestFlags.forcePlayBilling;

  /// Play Billing が使えない debug sideload 向けテスト購入のみ。
  static bool shouldUseSideloadTestPurchase({
    required bool isSideloadInstall,
    required bool billingAvailable,
  }) =>
      allowSideloadTestPurchases && isSideloadInstall && !billingAvailable;

  /// release の ADB 直インストールで Play 課金案内を出す。
  static bool shouldShowPlayInternalTestInstallPrompt({
    required bool isSideloadInstall,
    required bool billingReady,
  }) =>
      preferGooglePlay &&
      !kDebugMode &&
      isSideloadInstall &&
      !billingReady;
}
