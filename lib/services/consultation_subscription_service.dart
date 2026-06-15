import 'package:shared_preferences/shared_preferences.dart';

/// 相談券サブスクの加入状態（アカウントキーごとの端末キャッシュ）。
class ConsultationSubscriptionService {
  ConsultationSubscriptionService._();

  static const _kActivePrefix = 'consult_sub_active_v1';
  static String _accountKey = 'guest';

  static String _prefKey() => '${_kActivePrefix}_$_accountKey';

  static Future<void> bindAccountKey(String accountKey) async {
    _accountKey = accountKey.isNotEmpty ? accountKey : 'guest';
  }

  static Future<bool> isActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey()) ?? false;
  }

  static Future<void> setActive(bool active) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey(), active);
  }
}
