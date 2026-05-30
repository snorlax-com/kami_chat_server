import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/consultation_tab_visibility.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';

/// 開発者返信の検知とローカル通知（lastSeen とは独立）。
class DeveloperReplyNotifyService {
  DeveloperReplyNotifyService._();

  static const _prefsKeyLastNotifiedMs = 'dev_reply_local_notify_ms_v1';

  static Future<int> lastNotifiedMs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsKeyLastNotifiedMs) ?? 0;
  }

  static Future<void> _setLastNotifiedMs(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyLastNotifiedMs, ms);
  }

  /// 新しい開発者返信があれば通知（ユーザーが相談画面を見ていないとき）。
  static Future<bool> notifyIfNeeded({
    required String chatId,
    required int maxDevCreatedAt,
    bool force = false,
  }) async {
    if (maxDevCreatedAt <= 0) return false;
    if (!force && ConsultationTabVisibility.userIsViewingConsultation) return false;

    final lastNotified = await lastNotifiedMs();
    if (!force && maxDevCreatedAt <= lastNotified) return false;

    await PushNotificationService.instance.showDeveloperReplyLocal(chatId: chatId);
    await _setLastNotifiedMs(maxDevCreatedAt);
    debugPrint('[DevReplyNotify] local notification chatId=$chatId maxDev=$maxDevCreatedAt');
    return true;
  }

  /// アクティブな相談スレッドをポーリングし、開発者返信があれば通知する。
  static Future<void> pollAndNotify() async {
    final chatId = await DeveloperChatPref.getActiveChatId();
    if (chatId == null || chatId.isEmpty) return;
    await pollAndNotifyOnce(chatId: chatId);
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
