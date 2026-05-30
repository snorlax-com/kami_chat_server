import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'auraface_dev_reply';
const _channelName = '開発者からの返信';

/// バックグラウンド／終了時の FCM 受信（トップレベル関数必須）。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint(
    '[FCM:bg] type=${message.data['type']} chatId=${message.data['chatId']} '
    'messageId=${message.data['messageId']}',
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
        description: '開発者からの占い相談返信',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  final chatId = message.data['chatId']?.toString() ?? '';
  final title = message.notification?.title ?? 'AuraFaceから新しい導きが届きました';
  final body =
      message.notification?.body ?? '開発者から返信が届いています。タップして確認してください。';

  await plugin.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: '開発者からの占い相談返信',
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
}
