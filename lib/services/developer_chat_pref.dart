import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/services/consultation_chat_id.dart';
import 'package:kami_face_oracle/services/consultation_identity.dart';

/// メールブリッジ上の「最新の相談スレッド」IDと、創設者（占い師）返信の既読位置。
/// アカウント（bridge userId）ごとに SharedPreferences を分離する。
class DeveloperChatPref {
  DeveloperChatPref._();

  static const activeChatIdKey = 'developer_chat_active_chat_id';
  static const activeConsultationTypeKey = 'developer_chat_active_consultation_type';
  static const lastSeenDevCreatedAtKey = 'developer_chat_last_seen_dev_created_at_ms';
  /// 送信直後に表示するスレッド（古い長いスレッドへ戻らないよう固定）
  static const pinnedChatIdKey = 'developer_chat_pinned_chat_id_v1';
  /// ストア遷移などで占い相談入力欄の下書きを保持
  static const consultationDraftKey = 'developer_chat_consultation_draft_v1';
  /// 至急メール専用 chatId（表示スレッドとは別。旧 leading キーは互換のため残す）。
  static const leadingThreadChatIdKey = 'developer_chat_leading_thread_chat_id_v1';

  static String _scoped(String base, String userId) => '${base}_$userId';

  static Future<String> _userId() => ConsultationIdentity.bridgeUserIdOrLegacy();

  static Future<void> _migrateLegacyForUser(SharedPreferences sp, String userId) async {
    final legacyChat = sp.getString(activeChatIdKey);
    if (legacyChat == null || legacyChat.isEmpty) return;
    if (!ConsultationChatId.belongsToUser(legacyChat, userId)) return;

    final scopedChatKey = _scoped(activeChatIdKey, userId);
    if (!sp.containsKey(scopedChatKey)) {
      await sp.setString(scopedChatKey, legacyChat);
    }

    final legacyType = sp.getString(activeConsultationTypeKey);
    if (legacyType != null && legacyType.isNotEmpty) {
      final scopedTypeKey = _scoped(activeConsultationTypeKey, userId);
      if (!sp.containsKey(scopedTypeKey)) {
        await sp.setString(scopedTypeKey, legacyType);
      }
    }

    final legacyPinned = sp.getString(pinnedChatIdKey);
    if (legacyPinned != null &&
        legacyPinned.isNotEmpty &&
        ConsultationChatId.belongsToUser(legacyPinned, userId)) {
      final scopedPinnedKey = _scoped(pinnedChatIdKey, userId);
      if (!sp.containsKey(scopedPinnedKey)) {
        await sp.setString(scopedPinnedKey, legacyPinned);
      }
    }

    if (sp.containsKey(lastSeenDevCreatedAtKey)) {
      final scopedSeenKey = _scoped(lastSeenDevCreatedAtKey, userId);
      if (!sp.containsKey(scopedSeenKey)) {
        await sp.setInt(scopedSeenKey, sp.getInt(lastSeenDevCreatedAtKey) ?? 0);
      }
    }

    final legacyDraft = sp.getString(consultationDraftKey);
    if (legacyDraft != null && legacyDraft.trim().isNotEmpty) {
      final scopedDraftKey = _scoped(consultationDraftKey, userId);
      if (!sp.containsKey(scopedDraftKey)) {
        await sp.setString(scopedDraftKey, legacyDraft);
      }
    }

    final legacyLeading = sp.getString(leadingThreadChatIdKey);
    if (legacyLeading != null &&
        legacyLeading.isNotEmpty &&
        ConsultationChatId.belongsToUser(legacyLeading, userId)) {
      final scopedLeadingKey = _scoped(leadingThreadChatIdKey, userId);
      if (!sp.containsKey(scopedLeadingKey)) {
        await sp.setString(scopedLeadingKey, legacyLeading);
      }
    }
  }

  /// [consultationType] はメールブリッジの種別（至急スレッドの追記も至急テンプレで送るため）。
  static Future<void> setActiveChatId(
    String chatId, {
    String consultationType = ConsultationMailType.normal,
    bool pin = false,
  }) async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_scoped(activeChatIdKey, uid), chatId);
    await sp.setString(_scoped(activeConsultationTypeKey, uid), consultationType);
    if (pin) {
      await sp.setString(_scoped(pinnedChatIdKey, uid), chatId);
    }
  }

  static Future<String?> getPinnedChatId() async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await _migrateLegacyForUser(sp, uid);
    return sp.getString(_scoped(pinnedChatIdKey, uid));
  }

  static Future<void> clearPinnedChatId() async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_scoped(pinnedChatIdKey, uid));
  }

  static Future<String?> getActiveChatId() async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await _migrateLegacyForUser(sp, uid);
    return sp.getString(_scoped(activeChatIdKey, uid));
  }

  /// 未設定（旧バージョン）のときは null → 呼び出し側は通常扱い。
  static Future<String?> getActiveConsultationType() async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await _migrateLegacyForUser(sp, uid);
    return sp.getString(_scoped(activeConsultationTypeKey, uid));
  }

  static Future<int> getLastSeenDevCreatedAt() async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await _migrateLegacyForUser(sp, uid);
    return sp.getInt(_scoped(lastSeenDevCreatedAtKey, uid)) ?? 0;
  }

  static Future<void> setLastSeenDevCreatedAt(int ms) async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_scoped(lastSeenDevCreatedAtKey, uid), ms);
  }

  static Future<void> saveConsultationDraft(String text) async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    final key = _scoped(consultationDraftKey, uid);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      await sp.remove(key);
      return;
    }
    await sp.setString(key, text);
  }

  static Future<String?> getConsultationDraft() async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await _migrateLegacyForUser(sp, uid);
    final v = sp.getString(_scoped(consultationDraftKey, uid));
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  static Future<void> clearConsultationDraft() async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_scoped(consultationDraftKey, uid));
  }

  static Future<void> setLeadingThreadChatId(String chatId) async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_scoped(leadingThreadChatIdKey, uid), chatId);
  }

  static Future<String?> getLeadingThreadChatId() async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await _migrateLegacyForUser(sp, uid);
    return sp.getString(_scoped(leadingThreadChatIdKey, uid));
  }

  static Future<void> clearLeadingThreadChatId() async {
    final uid = await _userId();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_scoped(leadingThreadChatIdKey, uid));
  }
}
