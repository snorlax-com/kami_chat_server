import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/core/integration_test_flags.dart';
import 'package:kami_face_oracle/features/consent/consent_service.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/bridge_thread_local_store.dart';
import 'package:kami_face_oracle/services/consultation_identity.dart';
import 'package:kami_face_oracle/services/consultation_send_history_service.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/services/notification_launch_router.dart';
import 'package:kami_face_oracle/services/notification_permission_prompt.dart';
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:kami_face_oracle/testing/integration_test_consultation_mail_stub.dart';
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
    if (!IntegrationTestFlags.forcePlayBilling) {
      await SideloadBillingService.markSideloadTestPurchase();
    }

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

  /// Play 購入ボトムシート確認用（2回目以降の券購入可・テスト購入ダイアログなし）。
  static Future<void> seedForPlayBillingSheetTest() async {
    await IntegrationTestFlags.clearRuntimeFlags();
    await IntegrationTestFlags.enableConsultationMailTestMode();
    await seedSubscribedWithNoTickets();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', ConsultationIdentity.integrationTestUid);
    await prefs.setBool(
      'consult_first_send_completed_v1_${ConsultationIdentity.integrationTestUid}',
      true,
    );
  }

  static const normalThreadChatId =
      'consultation_${ConsultationIdentity.integrationTestUid}_1000';

  /// 至急券のみ・スレッドなしで新規至急送信を検証する。
  static Future<void> seedForUrgentOnlyFirstSend() async {
    await IntegrationTestFlags.enableConsultationMailTestMode();
    IntegrationTestConsultationMailStub.install();
    await seedSubscribedWithNoTickets();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('consult_priority_tickets_v1', 1);
    await prefs.setString('user_id', ConsultationIdentity.integrationTestUid);
    await ConsultationSendHistoryService.markFirstConsultationCompleted();
    await DeveloperChatPref.clearPinnedChatId();
    await prefs.remove(DeveloperChatPref.activeChatIdKey);
    await prefs.remove(DeveloperChatPref.activeConsultationTypeKey);
  }

  /// 通常スレッド表示中に至急を選んで新規至急スレッドへ送るケース。
  static Future<void> seedForUrgentFromNormalThread() async {
    await IntegrationTestFlags.enableConsultationMailTestMode();
    IntegrationTestConsultationMailStub.install();
    await seedSubscribedWithNoTickets();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('consult_priority_tickets_v1', 1);
    await prefs.setInt('consult_normal_tickets_v1', 1);
    await prefs.setString('user_id', ConsultationIdentity.integrationTestUid);
    await ConsultationSendHistoryService.markFirstConsultationCompleted();

    final now = DateTime.now().millisecondsSinceEpoch;
    final msg = BridgeChatMessage(
      id: 1,
      role: 'user',
      text: '通常スレッドの1通目',
      createdAt: now,
      consultationType: ConsultationMailType.normal,
    );
    await BridgeThreadLocalStore.save(normalThreadChatId, [msg]);
    await DeveloperChatPref.setActiveChatId(
      normalThreadChatId,
      consultationType: ConsultationMailType.normal,
      pin: true,
    );
  }

  /// チュートリアル疑似撮影→Reveal→結果の E2E 用。
  static Future<void> seedTutorialRevealFlow() async {
    await IntegrationTestFlags.enableCameraRouteForTest();
    NotificationPermissionPrompt.suppressForIntegrationTest = true;
    await ConsentService.instance.setAgeConfirmed(true);
    await ConsentService.instance.setCookieBannerShown();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tutorial_diagnosis_result_json');
    await prefs.remove('tutorial_diagnosis_consumed_v1');
    await prefs.remove('tutorial_guest_exited_without_login_v1');
    await prefs.setBool('tutorial_diagnosis_unlocked', false);
  }
}
