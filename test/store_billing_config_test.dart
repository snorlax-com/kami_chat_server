import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';

void main() {
  test('sideload テスト購入は debug ビルドのみ', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(
      StoreBillingConfig.shouldUseSideloadTestPurchase(
        isSideloadInstall: true,
        billingAvailable: false,
      ),
      kDebugMode,
    );
    expect(
      StoreBillingConfig.shouldUseSideloadTestPurchase(
        isSideloadInstall: false,
        billingAvailable: false,
      ),
      isFalse,
    );
  });

  test('Play 内部テスト案内は release sideload で billing 未準備時のみ', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(
      StoreBillingConfig.shouldShowPlayInternalTestInstallPrompt(
        isSideloadInstall: true,
        billingReady: false,
      ),
      !kDebugMode,
    );
    expect(
      StoreBillingConfig.shouldShowPlayInternalTestInstallPrompt(
        isSideloadInstall: false,
        billingReady: false,
      ),
      isFalse,
    );
    expect(
      StoreBillingConfig.shouldShowPlayInternalTestInstallPrompt(
        isSideloadInstall: true,
        billingReady: true,
      ),
      isFalse,
    );
  });
}
