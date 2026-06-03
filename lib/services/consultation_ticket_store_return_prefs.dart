import 'package:shared_preferences/shared_preferences.dart';

/// 占い相談の券不足からストアを開いたあと、購入完了で相談タブへ戻るフラグ（プロセス再起動後も維持）。
class ConsultationTicketStoreReturnPrefs {
  ConsultationTicketStoreReturnPrefs._();

  static const _keyPending = 'consult_return_after_ticket_store_v1';

  static Future<void> setPending(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setBool(_keyPending, true);
    } else {
      await prefs.remove(_keyPending);
    }
  }

  static Future<bool> isPending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPending) == true;
  }

  static Future<void> clear() => setPending(false);
}
