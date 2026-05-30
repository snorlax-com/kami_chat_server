import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kami_face_oracle/config/consultation_subscription_config.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/consultation_access_service.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:kami_face_oracle/services/store_catalog_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// 設定画面などからサブスク状態を確認・解除する。
class SubscriptionSettingsInfo {
  const SubscriptionSettingsInfo({
    required this.isSubscribed,
    required this.planName,
    required this.priceLabel,
    required this.managementKind,
  });

  final bool isSubscribed;
  final String planName;
  final String priceLabel;
  final SubscriptionManagementKind managementKind;
}

enum SubscriptionManagementKind {
  none,
  googlePlay,
  appStore,
  sideloadTest,
  localDebug,
}

class SubscriptionManagementService {
  SubscriptionManagementService._();

  static const _androidPackage = 'com.auraface.kami_face_oracle';

  static Future<SubscriptionSettingsInfo> loadInfo() async {
    await StoreCatalogService.ensureLoaded();
    final plan = StoreCatalogService.subscription;
    final access = await ConsultationAccessService.loadState();
    final iap = IAPService.instance;
    await iap.ensureReady();

    var kind = SubscriptionManagementKind.none;
    if (access.isSubscribed) {
      if (await SideloadBillingService.isSideloadTestSubscriptionValid()) {
        kind = SubscriptionManagementKind.sideloadTest;
      } else if (iap.hasVerifiedPlaySubscription ||
          (StoreBillingConfig.preferGooglePlay && !kIsWeb)) {
        kind = SubscriptionManagementKind.googlePlay;
      } else if (!kIsWeb && Platform.isIOS) {
        kind = SubscriptionManagementKind.appStore;
      } else if (StoreBillingConfig.allowAppStoreWhenPlayMissing) {
        kind = SubscriptionManagementKind.localDebug;
      }
    }

    final product = iap.subscriptionProduct;
    final priceLabel = product?.price ?? '¥${plan.priceYen}';

    return SubscriptionSettingsInfo(
      isSubscribed: access.isSubscribed,
      planName: plan.name,
      priceLabel: priceLabel,
      managementKind: kind,
    );
  }

  /// Google Play / App Store のサブスク管理画面を開く。
  static Future<bool> openStoreSubscriptionManagement() async {
    if (!kIsWeb && Platform.isIOS) {
      return _launch(Uri.parse('https://apps.apple.com/account/subscriptions'));
    }
    final sku = ConsultationSubscriptionConfig.productId;
    return _launch(
      Uri.parse(
        'https://play.google.com/store/account/subscriptions?sku=$sku&package=$_androidPackage',
      ),
    );
  }

  static Future<bool> _launch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// ADB 直インストール時のテストサブスクを端末ローカルで解除。
  static Future<void> cancelSideloadTestSubscription() async {
    await ConsultationSubscriptionService.setActive(false);
    await SideloadBillingService.clearSideloadTestPurchase();
    await IAPService.instance.syncSubscriptionStatusFromPlay();
  }

  /// debug 用ローカルサブスクを解除。
  static Future<void> cancelLocalDebugSubscription() async {
    await ConsultationSubscriptionService.setActive(false);
    await IAPService.instance.syncSubscriptionStatusFromPlay();
  }
}
