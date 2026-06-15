import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kami_face_oracle/config/mail_bridge_config.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/services/developer_reply_notify_service.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';

/// 実機で創設者（占い師）返信→通知の動作確認用。
class DeveloperReplyTestService {
  DeveloperReplyTestService._();

  /// ローカル通知のみ（サーバー不要）。
  static Future<void> testLocalNotification() async {
    final chatId = await DeveloperChatPref.getActiveChatId() ?? 'test_chat';
    final enabled = await PushNotificationService.instance.areSystemNotificationsEnabled();
    if (!enabled) {
      await PushNotificationService.instance.openSystemSettings();
      throw Exception(
        '通知がオフです。設定アプリで AuraFace の「通知」をオンにしてから、もう一度お試しください。',
      );
    }
    await PushNotificationService.instance.showDeveloperReplyLocal(
      chatId: chatId,
      messageCreatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    debugPrint('[DevReplyTest] local notification shown');
  }

  /// 本番サーバーへ創設者（占い師）返信を送り、続けてポーリングで通知する。
  static Future<String> sendTestDevReplyOnServer() async {
    final chatId = await DeveloperChatPref.getActiveChatId();
    if (chatId == null || chatId.isEmpty) {
      throw Exception('先に占い相談タブから相談を1通送信してください。');
    }

    final enabled = await PushNotificationService.instance.areSystemNotificationsEnabled();
    if (!enabled) {
      await PushNotificationService.instance.openSystemSettings();
      throw Exception(
        '通知がオフです。設定アプリで AuraFace の「通知」をオンにしてから、もう一度お試しください。',
      );
    }

    final uri = Uri.parse('$kMailBridgeProductionUrl/api/chat/dev-reply');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'chatId': chatId,
            'text': '【テスト】創設者（占い師）からの返信です。通知確認用メッセージです。',
          }),
        )
        .timeout(const Duration(seconds: 60));

    final body = res.body;
    debugPrint('[DevReplyTest] dev-reply status=${res.statusCode} body=$body');

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('サーバーエラー (${res.statusCode}): $body');
    }

    // サーバー FCM の有無に関わらず、端末側で即ポーリングしてローカル通知
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final notified = await DeveloperReplyNotifyService.pollAndNotifyOnce(
      chatId: chatId,
      force: true,
    );

    final pushHint = body.contains('"push"') ? body : '(push詳細なし＝サーバー未更新の可能性)';
    return notified
        ? '創設者（占い師）テスト返信を送信し、通知を表示しました。\n$pushHint'
        : '創設者（占い師）テスト返信は送信済みですが、通知はスキップされました（既読扱いまたは同一メッセージ）。\nホームタブに移動して「状態を再確認」してください。\n$pushHint';
  }
}
