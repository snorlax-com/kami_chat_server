import 'package:flutter/foundation.dart';
import 'package:kami_face_oracle/config/consultation_subscription_config.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';

/// ストアカタログ（Play 未連携でも商品を表示）。
class StoreCatalogService {
  StoreCatalogService._();

  static bool _ready = false;

  static Future<void> ensureLoaded() async {
    if (_ready) return;
    await ConsultationTicketPacksService.ensureLoaded();
    await ConsultationSubscriptionConfig.ensureLoaded();
    _ready = true;
  }

  static ConsultationSubscriptionPlan get subscription => ConsultationSubscriptionConfig.plan;

  static List<ConsultationTicketPack> get consumables => ConsultationTicketPacksService.packs;

  static bool get hasProducts => consumables.isNotEmpty;

  static void debugResetReady() {
    assert(kDebugMode);
    _ready = false;
  }
}
