import 'package:flutter/material.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/services/local_ticket_store_service.dart';
import 'package:kami_face_oracle/services/play_billing_error_mapper.dart';
import 'package:kami_face_oracle/services/play_install_service.dart';
import 'package:kami_face_oracle/services/play_store_launcher.dart';
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:kami_face_oracle/services/store_catalog_service.dart';
import 'package:kami_face_oracle/services/store_ui_helper.dart';

/// サブスク加入 — 確認ダイアログなしで Google Play 購入ボトムシートを即表示。
class StoreSubscriptionFlow {
  StoreSubscriptionFlow._();

  static Future<void> purchase(
    BuildContext context, {
    void Function(String? productId)? onPurchasingChanged,
  }) async {
    await StoreCatalogService.ensureLoaded();
    await PlayInstallService.ensureLoaded();
    final iap = IAPService.instance;
    await iap.ensureReady();

    final isSideload = PlayInstallService.isSideloadInstall;
    final canUseSideloadTest =
        StoreBillingConfig.allowSideloadTestPurchases && isSideload;
    final plan = StoreCatalogService.subscription;

    if (canUseSideloadTest) {
      await _purchaseSideloadTest(context, onPurchasingChanged: onPurchasingChanged);
      return;
    }

    if (await iap.hasActiveSubscriptionOnPlay()) {
      StoreUiHelper.showSnack('すでにサブスクに加入しています', backgroundColor: Colors.green);
      return;
    }

    if (!iap.isAvailable) {
      _showPlayConnectionFailed(context, isSideload, iap);
      return;
    }

    if (!iap.hasSubscriptionInCatalog) {
      await iap.loadProducts();
    }

    if (!iap.canSubscribeViaPlay) {
      _showPlayConnectionFailed(context, isSideload, iap, catalogMissing: true);
      return;
    }

    onPurchasingChanged?.call(plan.productId);
    final outcome = await iap.subscribeViaPlay();
    switch (outcome) {
      case StorePurchasePlayLaunched():
        return;
      case StorePurchaseAlreadySubscribed():
        onPurchasingChanged?.call(null);
        StoreUiHelper.showSnack('すでにサブスクに加入しています', backgroundColor: Colors.green);
        return;
      case StorePurchasePlayLaunchFailed():
      case StorePurchaseUnavailable():
        onPurchasingChanged?.call(null);
        StoreUiHelper.showSnack(
          PlayBillingErrorMapper.billingUnavailableMessage(),
          backgroundColor: Colors.orange.shade800,
        );
        if (await _offerOpenPlayStore(context)) return;
    }
  }

  static Future<bool> _offerOpenPlayStore(BuildContext context) async {
    final ok = await StoreUiHelper.confirm(
      title: 'Play ストアを開く',
      body:
          'Google Play からアプリをインストールすると、定期購入の課金画面が利用できます。\n'
          '（内部テストに参加している Google アカウントでログインしてください）',
      confirmLabel: 'Play ストアを開く',
      cancelLabel: 'キャンセル',
      fallbackContext: context,
    );
    if (!ok) return false;
    return PlayStoreLauncher.openAppListing();
  }

  static void _showPlayConnectionFailed(
    BuildContext context,
    bool isSideload,
    IAPService iap, {
    bool catalogMissing = false,
  }) {
    final msg = PlayBillingErrorMapper.billingUnavailableMessage(
      catalogMissing: catalogMissing,
    );
    final extra = <String>[
      if (isSideload) 'ADB 直インストールの場合は内部テスト版を Play から入れ直してください。',
      if (iap.notFoundProductIds.isNotEmpty)
        '未取得 ID: ${iap.notFoundProductIds.join(", ")}',
    ];
    StoreUiHelper.showSnack(
      extra.isEmpty ? msg : '$msg\n${extra.join("\n")}',
      backgroundColor: Colors.orange.shade800,
    );
  }

  static Future<void> _purchaseSideloadTest(
    BuildContext context, {
    void Function(String? productId)? onPurchasingChanged,
  }) async {
    final plan = StoreCatalogService.subscription;
    final ok = await StoreUiHelper.confirm(
      title: 'テスト購入（サブスク）',
      body:
          'ADB 直インストールのため Google Play 課金は使えません。\n\n'
          '${plan.name}（¥${plan.priceYen}/月相当）\n'
          '初回特典: 通常券${plan.firstBonusNormalTickets}枚\n\n'
          '※本番は Play 内部テスト版で課金されます。',
      confirmLabel: 'テスト加入',
      fallbackContext: context,
    );
    if (!ok) return;
    onPurchasingChanged?.call(plan.productId);
    try {
      final bonus = await LocalTicketStoreService.purchaseSubscription(sideloadTest: true);
      AppNavigation.notifyStoreAccessChanged();
      StoreUiHelper.showSnack('テスト加入（初回特典 +$bonus 通常券）', backgroundColor: Colors.green);
    } finally {
      onPurchasingChanged?.call(null);
    }
  }

  /// 加入済みかどうかを再確認（Play 同期込み）。
  static Future<bool> refreshSubscribed() async {
    final iap = IAPService.instance;
    await iap.syncSubscriptionStatusFromPlay();
    var sub = await ConsultationSubscriptionService.isActive();
    if (StoreBillingConfig.requirePlayVerifiedAccess) {
      final sideloadOk = await SideloadBillingService.isSideloadTestSubscriptionValid();
      sub = sub && (iap.hasVerifiedPlaySubscription || sideloadOk);
    }
    return sub;
  }
}
