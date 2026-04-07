import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';

/// メールブリッジ上の「最新の相談スレッド」IDと、開発者返信の既読位置。
class DeveloperChatPref {
  DeveloperChatPref._();

  static const activeChatIdKey = 'developer_chat_active_chat_id';
  static const activeConsultationTypeKey = 'developer_chat_active_consultation_type';
  static const lastSeenDevCreatedAtKey = 'developer_chat_last_seen_dev_created_at_ms';

  /// [consultationType] はメールブリッジの種別（至急スレッドの追記も至急テンプレで送るため）。
  static Future<void> setActiveChatId(
    String chatId, {
    String consultationType = ConsultationMailType.normal,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(activeChatIdKey, chatId);
    await sp.setString(activeConsultationTypeKey, consultationType);
  }

  static Future<String?> getActiveChatId() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(activeChatIdKey);
  }

  /// 未設定（旧バージョン）のときは null → 呼び出し側は通常扱い。
  static Future<String?> getActiveConsultationType() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(activeConsultationTypeKey);
  }

  static Future<int> getLastSeenDevCreatedAt() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(lastSeenDevCreatedAtKey) ?? 0;
  }

  static Future<void> setLastSeenDevCreatedAt(int ms) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(lastSeenDevCreatedAtKey, ms);
  }
}
