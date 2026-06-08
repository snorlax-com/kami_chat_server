import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kami_face_oracle/core/integration_test_flags.dart';
import 'package:kami_face_oracle/services/notification_launch_router.dart';
import 'package:kami_face_oracle/push/firebase_messaging_background.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/fcm_token_repository.dart';

/// 通知許可の状態（設定画面表示用）。
class NotificationPermissionStatus {
  const NotificationPermissionStatus({
    required this.granted,
    required this.label,
    required this.canRequestInApp,
    required this.needsSystemSettings,
  });

  final bool granted;
  final String label;
  final bool canRequestInApp;
  /// Android 10 など：設定アプリで通知をオンにする必要がある
  final bool needsSystemSettings;
}

/// 開発者返信の FCM プッシュ通知（許可・トークン・表示・タップ遷移）。
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  /// integration_test 中は FCM 許可ダイアログを出さない。
  static bool suppressForIntegrationTest = false;

  static const String _channelId = 'auraface_dev_reply';
  static const String _channelName = '開発者からの返信';
  static const String notificationTitle = 'AuraFaceから新しい導きが届きました';
  static const String notificationBody =
      '開発者から返信が届いています。タップして確認してください。';

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _localReady = false;
  bool _fcmReady = false;
  int? _androidSdkIntCache;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  Future<int?> androidSdkInt() async {
    if (!Platform.isAndroid) return null;
    if (_androidSdkIntCache != null) return _androidSdkIntCache;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _androidSdkIntCache = info.version.sdkInt;
      return _androidSdkIntCache;
    } catch (e) {
      debugPrint('[PushNotification] androidSdkInt failed: $e');
      return null;
    }
  }

  /// OS 上で通知が有効か（Android 10 は設定トグル、Android 13+ はランタイム許可含む）。
  Future<bool> areSystemNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final plugin = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await plugin?.areNotificationsEnabled();
      // ignore: avoid_print
      print('[PushNotification] areNotificationsEnabled=$enabled');
      return enabled ?? true;
    }
    if (Platform.isIOS) {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    }
    return true;
  }

  Future<void> init() async {
    try {
      await ensureLocalReady();
      if (!CloudService.isFirebaseAppReady) {
        debugPrint('[PushNotification] Firebase not ready — local only');
        return;
      }
      await _initFcm();
    } catch (e, st) {
      debugPrint('[PushNotification] init failed: $e\n$st');
    }
  }

  /// ローカル通知プラグインの初期化（Firebase 不要）。
  Future<void> ensureLocalReady() async {
    if (_localReady) return;
    await _initLocalNotifications();
    _localReady = true;
    // ignore: avoid_print
    print('[PushNotification] local notifications ready');
  }

  /// 通知タップでコールドスタートしたか（runApp 前に呼ぶ）。
  Future<void> consumeColdStartNotificationTap() async {
    await ensureLocalReady();
    try {
      final details = await _local.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return;
      final payload = details!.notificationResponse?.payload;
      // ignore: avoid_print
      print('[PushNotification] cold start from local notification payload=$payload');
      NotificationLaunchRouter.markLaunchFromNotification(
        chatId: payload != null && payload.isNotEmpty ? payload : null,
      );
    } catch (e) {
      debugPrint('[PushNotification] consumeColdStartNotificationTap: $e');
    }
  }

  /// FCM 通知タップでコールドスタート（Firebase 初期化後・runApp 前）。
  Future<void> consumeFcmInitialMessageIfAny() async {
    if (!CloudService.isFirebaseAppReady) return;
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial == null || !_isDeveloperReply(initial)) return;
      final chatId = initial.data['chatId']?.toString();
      // ignore: avoid_print
      print('[PushNotification] cold start from FCM chatId=$chatId');
      NotificationLaunchRouter.markLaunchFromNotification(chatId: chatId);
    } catch (e) {
      debugPrint('[PushNotification] consumeFcmInitialMessageIfAny: $e');
    }
  }

  Future<void> _initFcm() async {
    if (_fcmReady) return;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _requestFcmPermission();

    final messaging = FirebaseMessaging.instance;
    if (Platform.isIOS) {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpened);
    _tokenRefreshSub = messaging.onTokenRefresh.listen(_persistToken);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null && !user.isAnonymous) {
        await syncTokenNow();
      }
    });

    unawaited(syncTokenNow());

    final initial = await messaging.getInitialMessage();
    if (initial != null && !NotificationLaunchRouter.skipOpeningSplash) {
      unawaited(_handleNotificationOpen(initial));
    }

    _fcmReady = true;
    debugPrint('[PushNotification] FCM initialized');
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _authSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
  }

  Future<void> _requestFcmPermission() async {
    if (suppressForIntegrationTest || IntegrationTestFlags.bypassConsultationFirebaseAuth) {
      return;
    }
    if (!CloudService.isFirebaseAppReady) return;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('[PushNotification] FCM permission: ${settings.authorizationStatus}');
  }

  /// 現在の通知許可状態。
  Future<NotificationPermissionStatus> getPermissionStatus() async {
    await ensureLocalReady();

    if (Platform.isAndroid) {
      final sdk = await androidSdkInt();
      final enabled = await areSystemNotificationsEnabled();
      if (enabled) {
        return const NotificationPermissionStatus(
          granted: true,
          label: '許可済み（通知オン）',
          canRequestInApp: false,
          needsSystemSettings: false,
        );
      }
      if (sdk != null && sdk < 33) {
        return const NotificationPermissionStatus(
          granted: false,
          label: 'オフ（設定アプリで AuraFace の通知をオンにしてください）',
          canRequestInApp: false,
          needsSystemSettings: true,
        );
      }
      final st = await Permission.notification.status;
      if (st.isPermanentlyDenied) {
        return const NotificationPermissionStatus(
          granted: false,
          label: '拒否（システム設定から変更できます）',
          canRequestInApp: false,
          needsSystemSettings: true,
        );
      }
      return NotificationPermissionStatus(
        granted: false,
        label: '未許可',
        canRequestInApp: true,
        needsSystemSettings: st.isPermanentlyDenied,
      );
    }

    if (Platform.isIOS) {
      if (!CloudService.isFirebaseAppReady) {
        return const NotificationPermissionStatus(
          granted: false,
          label: 'Firebase 未初期化',
          canRequestInApp: false,
          needsSystemSettings: false,
        );
      }
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final auth = settings.authorizationStatus;
      final granted = auth == AuthorizationStatus.authorized ||
          auth == AuthorizationStatus.provisional;
      return NotificationPermissionStatus(
        granted: granted,
        label: granted ? '許可済み' : '未許可',
        canRequestInApp: !granted,
        needsSystemSettings: false,
      );
    }

    return const NotificationPermissionStatus(
      granted: false,
      label: 'この端末では未対応',
      canRequestInApp: false,
      needsSystemSettings: false,
    );
  }

  /// 通知を有効化（Android 13+ はダイアログ、Android 10–12 は設定案内）。
  Future<bool> ensureNotificationPermission() async {
    await ensureLocalReady();

    if (Platform.isAndroid) {
      final sdk = await androidSdkInt();
      if (sdk != null && sdk < 33) {
        final enabled = await areSystemNotificationsEnabled();
        if (enabled) return true;
        debugPrint('[PushNotification] Android<$sdk: open system settings for notifications');
        await openSystemSettings();
        return false;
      }

      var st = await Permission.notification.status;
      if (!st.isGranted) {
        st = await Permission.notification.request();
        debugPrint('[PushNotification] Android 13+ notification request: $st');
      }
      return st.isGranted && await areSystemNotificationsEnabled();
    }

    if (!CloudService.isFirebaseAppReady) return false;
    await _requestFcmPermission();
    return areSystemNotificationsEnabled();
  }

  /// OS のアプリ設定（通知トグル）を開く。
  Future<void> openSystemSettings() async {
    await openAppSettings();
  }

  /// ログイン後・相談送信後などから明示的にトークンを再登録する。
  Future<void> syncTokenNow() async {
    if (!CloudService.isFirebaseAppReady || !_fcmReady) return;
    final token = await _getFcmTokenWithRetry();
    await _persistToken(token);
  }

  /// 相談送信時にサーバーへ渡す用。
  Future<String?> getCachedFcmToken() async {
    if (!CloudService.isFirebaseAppReady) return null;
    if (!_fcmReady) {
      unawaited(_initFcm());
    }
    return _getFcmTokenWithRetry();
  }

  Future<String?> _getFcmTokenWithRetry() async {
    for (var i = 0; i < 5; i++) {
      try {
        final t = await FirebaseMessaging.instance.getToken();
        if (t != null && t.isNotEmpty) return t;
      } catch (e) {
        debugPrint('[PushNotification] getToken attempt $i: $e');
      }
      await Future<void>.delayed(Duration(seconds: 1 + i));
    }
    return null;
  }

  /// ローカル通知（フォアグラウンド／Watchdog 用）。
  Future<void> showDeveloperReplyLocal({required String chatId}) async {
    await ensureLocalReady();

    final enabled = await areSystemNotificationsEnabled();
    if (!enabled) {
      debugPrint('[PushNotification] skip local show: system notifications disabled');
      return;
    }

    // ignore: avoid_print
    print('[PushNotification] showing local notification chatId=$chatId');
    await _local.show(
      chatId.hashCode,
      notificationTitle,
      notificationBody,
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
      payload: chatId,
    );
  }

  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        unawaited(
          NotificationLaunchRouter.routeFromNotificationTap(
            chatId: payload != null && payload.isNotEmpty ? payload : null,
          ),
        );
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = _local.resolvePlatformSpecificImplementation<
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
  }

  Future<void> _persistToken(String? token) async {
    if (token == null || token.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;

    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'other';

    if (user != null && !user.isAnonymous) {
      await FcmTokenRepository.saveToken(
        uid: user.uid,
        token: token,
        platform: platform,
      );
      return;
    }

    debugPrint('[PushNotification] token obtained but user not signed in (skip server register)');
  }

  bool _isDeveloperReply(RemoteMessage message) {
    return message.data['type'] == 'dev_reply';
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    if (!_isDeveloperReply(message)) return;
    debugPrint('[PushNotification] foreground dev_reply chatId=${message.data['chatId']}');

    if (message.notification != null && Platform.isIOS) return;

    await ensureLocalReady();
    final chatId = message.data['chatId']?.toString() ?? '';
    await _local.show(
      message.hashCode,
      message.notification?.title ?? notificationTitle,
      message.notification?.body ?? notificationBody,
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

  void _onNotificationOpened(RemoteMessage message) {
    _handleNotificationOpen(message);
  }

  Future<void> _handleNotificationOpen(RemoteMessage message) async {
    if (!_isDeveloperReply(message)) return;
    final chatId = message.data['chatId']?.toString();
    await NotificationLaunchRouter.routeFromNotificationTap(chatId: chatId);
  }
}
