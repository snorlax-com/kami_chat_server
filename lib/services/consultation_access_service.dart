import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/billing_log.dart';
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';

/// 質問機能のアクセス制御（サブスク + 券）。
class ConsultationAccessService {
  ConsultationAccessService._();

  /// 起動時・画面表示時に Play と同期してから状態を返す。
  static Future<ConsultationAccessState> loadState() async {
    final iap = IAPService.instance;
    await iap.ensureReady();
    await iap.syncSubscriptionStatusFromPlay();

    var subscribed = await ConsultationSubscriptionService.isActive();
    if (StoreBillingConfig.requirePlayVerifiedAccess) {
      final sideloadOk = await SideloadBillingService.isSideloadTestSubscriptionValid();
      subscribed = subscribed && (iap.hasVerifiedPlaySubscription || sideloadOk);
    }

    final normal = await ConsultationTicketService.normalTickets();
    final urgent = await ConsultationTicketService.priorityTickets();
    final state = ConsultationAccessState(
      isSubscribed: subscribed,
      normalTickets: normal,
      urgentTickets: urgent,
    );
    BillingLog.info(
      'accessState subscribed=${state.isSubscribed} normal=${state.normalTickets} urgent=${state.urgentTickets}',
    );
    return state;
  }

  /// 送信に使う券種（通常優先。至急券のみのときは至急）。
  static ConsultationSendTicketKind? resolveSendTicketKind(ConsultationAccessState state) {
    if (!state.isSubscribed) return null;
    if (state.normalTickets >= ConsultationTicketService.normalCostPerSend) {
      return ConsultationSendTicketKind.normal;
    }
    if (state.urgentTickets >= ConsultationTicketService.priorityCostPerSend) {
      return ConsultationSendTicketKind.urgent;
    }
    return null;
  }

  /// 新規相談の券種（画面で選んだ種別を優先。不足時のみ自動フォールバック）。
  static ConsultationSendTicketKind? resolveFirstSendTicketKind(
    ConsultationAccessState state, {
    required ConsultationSendTicketKind preference,
  }) {
    if (!state.isSubscribed) return null;
    if (preference == ConsultationSendTicketKind.urgent &&
        state.urgentTickets >= ConsultationTicketService.priorityCostPerSend) {
      return ConsultationSendTicketKind.urgent;
    }
    if (preference == ConsultationSendTicketKind.normal &&
        state.normalTickets >= ConsultationTicketService.normalCostPerSend) {
      return ConsultationSendTicketKind.normal;
    }
    return resolveSendTicketKind(state);
  }

  static bool canChooseNormalSend(ConsultationAccessState state) =>
      state.normalTickets >= ConsultationTicketService.normalCostPerSend;

  static bool canChooseUrgentSend(ConsultationAccessState state) =>
      state.urgentTickets >= ConsultationTicketService.priorityCostPerSend;

  /// スレッド追記時（至急スレッドは至急券のみ）。
  static ConsultationSendTicketKind? resolveFollowUpTicketKind(
    ConsultationAccessState state,
    String consultationType,
  ) {
    if (!state.isSubscribed) return null;
    if (consultationType == ConsultationMailType.priorityGuidance) {
      if (state.urgentTickets >= ConsultationTicketService.priorityCostPerSend) {
        return ConsultationSendTicketKind.urgent;
      }
      return null;
    }
    return resolveSendTicketKind(state);
  }
}

class ConsultationAccessState {
  const ConsultationAccessState({
    required this.isSubscribed,
    required this.normalTickets,
    required this.urgentTickets,
  });

  final bool isSubscribed;
  final int normalTickets;
  final int urgentTickets;

  bool get hasAnyTicket =>
      normalTickets >= ConsultationTicketService.normalCostPerSend ||
      urgentTickets >= ConsultationTicketService.priorityCostPerSend;
}

enum ConsultationSendTicketKind { normal, urgent }
