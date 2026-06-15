import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kami_face_oracle/push/developer_reply_notification_id.dart';
import 'package:kami_face_oracle/services/developer_reply_notify_prefs.dart';

const _channelId = 'auraface_dev_reply';
const _channelName = '創設者（占い師）からの返信';

/// バックグラウンド／終了時の FCM 受信（トップレベル関数必須）。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint(
    '[FCM:bg] type=${message.data['type']} chatId=${message.data['chatId']} '
    'messageId=${message.data['messageId']} createdAt=${message.data['createdAt']}',
  );

  if (message.data['type'] != 'dev_reply') return;

  final plugin = FlutterLocalNotificationsPlugin();
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  await plugin.initialize(const InitializationSettings(android: android, iOS: ios));

  if (Platform.isAndroid) {
    final androidPlugin = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: '創設者（占い師）からの占い相談返信',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  final chatId = message.data['chatId']?.toString() ?? '';
  final messageCreatedAt = parseDevReplyCreatedAt(message.data);
  final messageId = parseDevReplyMessageId(message.data);
  final notificationId = developerReplyNotificationId(
    chatId: chatId,
    messageCreatedAt: messageCreatedAt,
    messageId: messageId,
  );
  final title = message.notification?.title ?? 'AuraFaceから新しい導きが届きました';
  final body =
      message.notification?.body ?? '創設者（占い師）から返信が届いています。タップして確認してください。';

  await plugin.show(
    notificationId,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: '創設者（占い師）からの占い相談返信',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    payload: chatId.isNotEmpty ? chatId : null,
  );

  if (chatId.isNotEmpty) {
    if (messageCreatedAt != null && messageCreatedAt > 0) {
      await DeveloperReplyNotifyPrefs.markNotified(
        chatId: chatId,
        messageCreatedAt: messageCreatedAt,
      );
    } else if (messageId != null && messageId > 0) {
      await DeveloperReplyNotifyPrefs.markNotified(
        chatId: chatId,
        messageCreatedAt: messageId,
      );
    }
  }
}
