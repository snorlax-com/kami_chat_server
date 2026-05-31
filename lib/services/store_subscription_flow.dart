import 'package:flutter/material.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/services/local_ticket_store_service.dart';
import 'package:kami_face_oracle/services/play_install_service.dart';
import 'package:kami_face_oracle/services/play_store_launcher.dart';
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:kami_face_oracle/services/store_catalog_service.dart';
import 'package:kami_face_oracle/services/store_ui_helper.dart';

/// ストア画面を開かずにサブスク加入を開始する。
class StoreSubscriptionFlow {
  StoreSubscriptionFlow._();

  static Future<void> purchase(
    BuildContext context, {
    void Function(String? productId)? onPurchasingChanged,
  }) async {
    await StoreCatalogService.ensureLoaded();
    await PlayInstallService.ensureLoaded();
    final iap = IAPService.instance;
    await iap.refreshCatalog();

    final isSideload = PlayInstallService.isSideloadInstall;
    final canUseSideloadTest =
        StoreBillingConfig.allowSideloadTestPurchases && isSideload;
    final plan = StoreCatalogService.subscription;

    if (canUseSideloadTest) {
      await _purchaseSideloadTest(context, onPurchasingChanged: onPurchasingChanged);
      return;
    }

    if (iap.canSubscribeViaPlay) {
      final product = iap.subscriptionProduct!;
      final ok = await StoreUiHelper.confirm(
        title: plan.name,
        body: '${plan.description}\n\n月額 ${product.price}\nGoogle Play の定期購入画面が開きます。',
        confirmLabel: 'Google Play で加入',
        fallbackContext: context,
      );
      if (!ok) return;
      onPurchasingChanged?.call(plan.productId);
      final outcome = await iap.subscribeViaPlay();
      switch (outcome) {
        case StorePurchasePlayLaunched():
          return;
        case StorePurchasePlayLaunchFailed():
        case StorePurchaseUnavailable():
          onPurchasingChanged?.call(null);
          StoreUiHelper.showSnack(
            'Google Play の購入画面を開けませんでした。Play ストア版をインストールしているか確認してください。',
            backgroundColor: Colors.orange.shade800,
          );
          if (await _offerOpenPlayStore(context)) return;
          if (canUseSideloadTest) {
            await _purchaseSideloadTest(context, onPurchasingChanged: onPurchasingChanged);
          } else if (StoreBillingConfig.allowAppStoreWhenPlayMissing) {
            await _purchaseAppStore(context, onPurchasingChanged: onPurchasingChanged);
          } else {
            _showPlayUnavailable(context, isSideload, iap);
          }
      }
      return;
    }

    if (StoreBillingConfig.allowAppStoreWhenPlayMissing) {
      await _purchaseAppStore(context, onPurchasingChanged: onPurchasingChanged);
      return;
    }
    await _showPlayUnavailable(context, isSideload, iap);
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

  static Future<void> _showPlayUnavailable(
    BuildContext context,
    bool isSideload,
    IAPService iap,
  ) async {
    final parts = <String>[
      'Google Play 課金を開始できません。',
      if (isSideload)
        '現在 ADB 直インストールです。Play Console の内部テスト経由でインストールすると本番課金が使えます。',
      if (!iap.isAvailable) '端末の Play ストア / 課金サービスを確認してください。',
      if (iap.isAvailable && !iap.hasSubscriptionInCatalog)
        'Play Console の定期購入「${StoreCatalogService.subscription.productId}」が未取得です。反映まで最大数時間かかることがあります。',
      if (StoreBillingConfig.allowSideloadTestPurchases &&
          isSideload &&
          !iap.hasSubscriptionInCatalog)
        '占い相談画面からテスト加入できます（実課金なし）。',
    ];
    final open = await StoreUiHelper.confirm(
      title: 'Google Play 課金を利用できません',
      body: parts.join('\n'),
      confirmLabel: 'Play ストアを開く',
      cancelLabel: '閉じる',
      fallbackContext: context,
    );
    if (open) {
      await PlayStoreLauncher.openAppListing();
    }
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

  static Future<void> _purchaseAppStore(
    BuildContext context, {
    bool silent = false,
    void Function(String? productId)? onPurchasingChanged,
  }) async {
    final plan = StoreCatalogService.subscription;
    if (!silent) {
      final ok = await StoreUiHelper.confirm(
        title: plan.name,
        body: '${plan.description}\n\n月額 ¥${plan.priceYen}\n初回特典: 通常質問券${plan.firstBonusNormalTickets}枚',
        confirmLabel: '加入',
        fallbackContext: context,
      );
      if (!ok) return;
    }
    onPurchasingChanged?.call(plan.productId);
    try {
      final bonus = await LocalTicketStoreService.purchaseSubscription();
      AppNavigation.notifyStoreAccessChanged();
      StoreUiHelper.showSnack('サブスク加入（初回特典 +$bonus 通常券）', backgroundColor: Colors.green);
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
