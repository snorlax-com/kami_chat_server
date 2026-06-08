import 'package:kami_face_oracle/config/consultation_subscription_config.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:kami_face_oracle/services/subscription_bonus_service.dart';
import 'package:kami_face_oracle/services/tutorial_subscribe_retake_service.dart';

/// Google Play 未連携時のアプリ内購入（debug / sideload テスト用）。
class LocalTicketStoreService {
  LocalTicketStoreService._();

  static Future<int> purchasePack(ConsultationTicketPack pack) async {
    if (pack.tickets <= 0) return 0;
    if (pack.isUrgent) {
      await ConsultationTicketService.addPriorityTickets(pack.tickets);
    } else {
      await ConsultationTicketService.addNormalTickets(pack.tickets);
    }
    return pack.tickets;
  }

  static Future<int> purchaseSubscription({bool sideloadTest = false}) async {
    if (!StoreBillingConfig.allowAppStoreWhenPlayMissing && !sideloadTest) return 0;
    final wasActive = await ConsultationSubscriptionService.isActive();
    await ConsultationSubscriptionService.setActive(true);
    if (sideloadTest) {
      await SideloadBillingService.markSideloadTestPurchase();
    }
    final bonus = await SubscriptionBonusService.grantFirstBonusIfEligible();
    await TutorialSubscribeRetakeService.onSubscriptionActivated(
      wasSubscribedBefore: wasActive,
    );
    return bonus;
  }
}
