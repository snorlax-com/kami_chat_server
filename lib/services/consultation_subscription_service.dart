import 'package:shared_preferences/shared_preferences.dart';

/// 相談券サブスクの加入状態（端末ローカル。Play の queryPastPurchases と同期）。
class ConsultationSubscriptionService {
  ConsultationSubscriptionService._();

  static const _kActive = 'consult_sub_active_v1';

  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kActive) ?? false;
  }

  static Future<void> setActive(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kActive, active);
  }
}
