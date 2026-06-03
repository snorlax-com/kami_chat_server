import 'package:kami_face_oracle/features/consent/consent_service.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/notification_launch_router.dart';
import 'package:kami_face_oracle/services/notification_permission_prompt.dart';
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// integration_test 用: サブスク加入済み・券0枚の状態を作る。
class IntegrationTestSeed {
  IntegrationTestSeed._();

  static const _notificationPromptKey = 'notification_prompt_last_ms_v1';

  static Future<void> seedSubscribedWithNoTickets() async {
    NotificationLaunchRouter.skipOpeningSplash = true;
    NotificationPermissionPrompt.suppressForIntegrationTest = true;
    await ConsentService.instance.setAgeConfirmed(true);
    await ConsultationSubscriptionService.setActive(true);
    await SideloadBillingService.markSideloadTestPurchase();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('consult_normal_tickets_v1', 0);
    await prefs.setInt('consult_priority_tickets_v1', 0);
    await prefs.setBool('consult_tickets_initialized_v1', true);
    await prefs.setInt(
      _notificationPromptKey,
      DateTime.now().millisecondsSinceEpoch,
    );

    // 念のためサービス経由でも0枚に揃える
    final normal = await ConsultationTicketService.normalTickets();
    final urgent = await ConsultationTicketService.priorityTickets();
    if (normal != 0 || urgent != 0) {
      await prefs.setInt('consult_normal_tickets_v1', 0);
      await prefs.setInt('consult_priority_tickets_v1', 0);
    }
  }
}
