import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/play_install_service.dart';

/// ADB 直インストール時の明示テスト購入（debug のみ。release では無効）。
class SideloadBillingService {
  SideloadBillingService._();

  static const _kSideloadPurchase = 'consult_sub_sideload_purchase_v1';

  static bool get _allowsSideloadTest => kDebugMode;

  static Future<bool> hasSideloadTestPurchase() async {
    if (!_allowsSideloadTest) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSideloadPurchase) == true;
  }

  static Future<void> markSideloadTestPurchase() async {
    if (!_allowsSideloadTest) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSideloadPurchase, true);
  }

  /// sideload テスト購入のサブスクをアクセス判定に使えるか（debug sideload のみ）。
  static Future<bool> isSideloadTestSubscriptionValid() async {
    if (!_allowsSideloadTest) return false;
    if (!await hasSideloadTestPurchase()) return false;
    await PlayInstallService.ensureLoaded();
    if (!PlayInstallService.isSideloadInstall) {
      return ConsultationSubscriptionService.isActive();
    }
    if (!await ConsultationSubscriptionService.isActive()) {
      await ConsultationSubscriptionService.setActive(true);
    }
    return true;
  }

  static Future<void> clearSideloadTestPurchase() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSideloadPurchase);
  }
}
