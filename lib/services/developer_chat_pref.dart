import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';

/// メールブリッジ上の「最新の相談スレッド」IDと、開発者返信の既読位置。
class DeveloperChatPref {
  DeveloperChatPref._();

  static const activeChatIdKey = 'developer_chat_active_chat_id';
  static const activeConsultationTypeKey = 'developer_chat_active_consultation_type';
  static const lastSeenDevCreatedAtKey = 'developer_chat_last_seen_dev_created_at_ms';
  /// 送信直後に表示するスレッド（古い長いスレッドへ戻らないよう固定）
  static const pinnedChatIdKey = 'developer_chat_pinned_chat_id_v1';
  /// ストア遷移などで占い相談入力欄の下書きを保持
  static const consultationDraftKey = 'developer_chat_consultation_draft_v1';

  /// [consultationType] はメールブリッジの種別（至急スレッドの追記も至急テンプレで送るため）。
  static Future<void> setActiveChatId(
    String chatId, {
    String consultationType = ConsultationMailType.normal,
    bool pin = false,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(activeChatIdKey, chatId);
    await sp.setString(activeConsultationTypeKey, consultationType);
    if (pin) {
      await sp.setString(pinnedChatIdKey, chatId);
    }
  }

  static Future<String?> getPinnedChatId() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(pinnedChatIdKey);
  }

  static Future<void> clearPinnedChatId() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(pinnedChatIdKey);
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

  static Future<void> saveConsultationDraft(String text) async {
    final sp = await SharedPreferences.getInstance();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      await sp.remove(consultationDraftKey);
      return;
    }
    await sp.setString(consultationDraftKey, text);
  }

  static Future<String?> getConsultationDraft() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(consultationDraftKey);
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  static Future<void> clearConsultationDraft() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(consultationDraftKey);
  }
}
