import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/bridge_thread_local_store.dart';
import 'package:kami_face_oracle/services/consultation_identity.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';

/// 占い相談の送信履歴（初回相談完了 = 2回目以降の券購入解禁）。
class ConsultationSendHistoryService {
  ConsultationSendHistoryService._();

  static const _kFirstSent = 'consult_first_send_completed_v1';

  static Future<String> _scopedKey() async {
    final uid = await ConsultationIdentity.bridgeUserIdOrLegacy();
    return '${_kFirstSent}_$uid';
  }

  static Future<bool> hasCompletedFirstConsultation() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _scopedKey();
    if (prefs.getBool(key) == true) return true;
    return prefs.getBool(_kFirstSent) ?? false;
  }

  static Future<void> markFirstConsultationCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _scopedKey();
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);
  }

  /// 既存スレッドがあるユーザー向け（アップデート前から利用中）。
  static Future<void> migrateIfNeeded() async {
    if (await hasCompletedFirstConsultation()) return;
    final chatId = await DeveloperChatPref.getActiveChatId();
    if (chatId == null || chatId.isEmpty) return;
    final local = await BridgeThreadLocalStore.load(chatId);
    for (final m in local) {
      if (m.role == 'user') {
        await markFirstConsultationCompleted();
        return;
      }
    }
  }
}
