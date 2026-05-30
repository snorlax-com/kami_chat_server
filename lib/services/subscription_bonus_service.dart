import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/config/consultation_subscription_config.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';

/// サブスク初回特典（通常質問券1枚）の1回限り付与。
class SubscriptionBonusService {
  SubscriptionBonusService._();

  static const _kBonusGranted = 'has_received_subscription_bonus_v1';

  static Future<bool> hasReceivedBonus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBonusGranted) ?? false;
  }

  /// 未付与なら通常券を付与して `true`。既に付与済みなら `false`。
  static Future<int> grantFirstBonusIfEligible() async {
    await ConsultationSubscriptionConfig.ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kBonusGranted) == true) return 0;

    final tickets = ConsultationSubscriptionConfig.plan.firstBonusNormalTickets;
    if (tickets <= 0) return 0;

    await ConsultationTicketService.addNormalTickets(tickets);
    await prefs.setBool(_kBonusGranted, true);
    return tickets;
  }
}
