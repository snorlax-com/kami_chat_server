import 'package:kami_face_oracle/app_navigation.dart';

/// 通知タップで起動したときのスプラッシュ省略・占い相談直行。
class NotificationLaunchRouter {
  NotificationLaunchRouter._();

  static bool skipOpeningSplash = false;

  /// 通知タップから起動（スプラッシュを飛ばす）。
  static void markLaunchFromNotification({String? chatId}) {
    skipOpeningSplash = true;
    AppNavigation.stagePendingConsultationChat(chatId);
    // ignore: avoid_print
    print('[NotificationLaunch] skipOpeningSplash chatId=$chatId');
  }

  /// 通知タップ時（フォア／バック／コールドスタート）。
  static Future<void> routeFromNotificationTap({String? chatId}) async {
    if (chatId != null && chatId.trim().isNotEmpty) {
      markLaunchFromNotification(chatId: chatId.trim());
    }
    await AppNavigation.openConsultationChat(chatId: chatId);
  }
}
