import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/bridge_thread_local_store.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/consultation_tab_visibility.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/services/developer_reply_notify_prefs.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';

/// 創設者（占い師）返信の検知とローカル通知（lastSeen とは独立）。
class DeveloperReplyNotifyService {
  DeveloperReplyNotifyService._();

  static bool _pollInFlight = false;

  static Future<int> lastNotifiedMs() async {
    // 互換用（テスト等）。複数スレッド対応後は per-key 管理を使う。
    return 0;
  }

  /// FCM 受信後にポーリング側の重複通知を防ぐ。
  static Future<void> markNotifiedFromRemote({
    required String chatId,
    int? messageCreatedAt,
    int? messageId,
  }) async {
    if (messageCreatedAt != null && messageCreatedAt > 0) {
      await DeveloperReplyNotifyPrefs.markNotified(
        chatId: chatId,
        messageCreatedAt: messageCreatedAt,
      );
      return;
    }
    if (messageId != null && messageId > 0) {
      await DeveloperReplyNotifyPrefs.markNotified(
        chatId: chatId,
        messageCreatedAt: messageId,
      );
    }
  }

  /// 新しい創設者（占い師）返信があれば通知（ユーザーが相談画面を見ていないとき）。
  static Future<bool> notifyIfNeeded({
    required String chatId,
    required int maxDevCreatedAt,
    bool force = false,
  }) async {
    if (maxDevCreatedAt <= 0) return false;

    final alreadyNotified = await DeveloperReplyNotifyPrefs.wasNotified(
      chatId: chatId,
      messageCreatedAt: maxDevCreatedAt,
    );
    if (!force && alreadyNotified) return false;

    if (!force && ConsultationTabVisibility.userIsViewingConsultation) {
      await DeveloperReplyNotifyPrefs.markNotified(
        chatId: chatId,
        messageCreatedAt: maxDevCreatedAt,
      );
      return false;
    }

    await PushNotificationService.instance.showDeveloperReplyLocal(
      chatId: chatId,
      messageCreatedAt: maxDevCreatedAt,
    );
    await DeveloperReplyNotifyPrefs.markNotified(
      chatId: chatId,
      messageCreatedAt: maxDevCreatedAt,
    );
    debugPrint('[DevReplyNotify] local notification chatId=$chatId maxDev=$maxDevCreatedAt');
    return true;
  }

  /// アクティブな相談スレッドをポーリングし、創設者（占い師）返信があれば通知する。
  static Future<void> pollAndNotify() async {
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      final chatIds = <String>{};
      final active = await DeveloperChatPref.getActiveChatId();
      if (active != null && active.isNotEmpty) chatIds.add(active);
      try {
        chatIds.addAll(await BridgeThreadLocalStore.listCachedChatIds());
      } catch (_) {}

      for (final chatId in chatIds) {
        await pollAndNotifyOnce(chatId: chatId);
      }
    } finally {
      _pollInFlight = false;
    }
  }

  /// 指定 chatId のスレッドを確認して通知。戻り値は通知を表示したか。
  static Future<bool> pollAndNotifyOnce({
    required String chatId,
    bool force = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(AuraFaceChatMailService.prefKeyBaseUrl);
      final bridgeUrl = AuraFaceChatMailService.consultationSendBaseUrl(savedUrl);
      final service = AuraFaceChatMailService(baseUrl: bridgeUrl);
      final res = await service.getThread(chatId: chatId);
      if (!res.success) return false;

      var maxDev = 0;
      for (final m in res.messages) {
        if (m.isFromDev && m.createdAt > maxDev) maxDev = m.createdAt;
      }
      return notifyIfNeeded(chatId: chatId, maxDevCreatedAt: maxDev, force: force);
    } catch (e) {
      debugPrint('[DevReplyNotify] poll failed: $e');
      return false;
    }
  }
}
