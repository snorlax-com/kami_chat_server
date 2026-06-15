import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:kami_face_oracle/config/play_billing_products.dart';

/// Google Play 月額サブスクリプション定義。
class ConsultationSubscriptionPlan {
  const ConsultationSubscriptionPlan({
    required this.productId,
    required this.name,
    required this.description,
    required this.priceYen,
    required this.billingPeriodLabel,
    required this.firstBonusNormalTickets,
  });

  final String productId;
  final String name;
  final String description;
  final int priceYen;
  final String billingPeriodLabel;

  /// 初回加入特典として付与する通常券枚数（1ユーザー1回）。
  final int firstBonusNormalTickets;
}

class ConsultationSubscriptionConfig {
  ConsultationSubscriptionConfig._();

  static const _assetPath = 'assets/data/consultation_subscription.json';

  static const ConsultationSubscriptionPlan _fallback = ConsultationSubscriptionPlan(
    productId: PlayBillingProducts.subscriptionMonthly500,
    name: '月額サブスク',
    description: '質問機能を利用するにはサブスク加入が必要です。初回加入時に質問券1枚をプレゼントします。',
    priceYen: 500,
    billingPeriodLabel: '月',
    firstBonusNormalTickets: 1,
  );

  static ConsultationSubscriptionPlan? _loaded;

  static ConsultationSubscriptionPlan get plan => _loaded ?? _fallback;

  static String get productId => plan.productId;

  static bool isSubscriptionProduct(String id) => PlayBillingProducts.isSubscriptionProduct(id);

  static Future<void> ensureLoaded() async {
    if (_loaded != null) return;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _loaded = ConsultationSubscriptionPlan(
        productId: json['productId']?.toString() ?? _fallback.productId,
        name: json['name']?.toString() ?? _fallback.name,
        description: json['description']?.toString() ?? _fallback.description,
        priceYen: (json['priceYen'] as num?)?.toInt() ?? _fallback.priceYen,
        billingPeriodLabel: json['billingPeriodLabel']?.toString() ?? _fallback.billingPeriodLabel,
        firstBonusNormalTickets:
            (json['firstBonusNormalTickets'] as num?)?.toInt() ?? _fallback.firstBonusNormalTickets,
      );
    } catch (e, st) {
      debugPrint('[ConsultationSubscriptionConfig] load failed: $e\n$st');
      _loaded = _fallback;
    }
  }
}
