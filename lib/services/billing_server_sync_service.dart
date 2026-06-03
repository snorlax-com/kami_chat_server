import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'package:kami_face_oracle/config/play_billing_products.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/billing_log.dart';

/// 購入成功を Node.js API / SQLite に記録（不正防止用 purchaseToken 保存）。
class BillingServerSyncService {
  BillingServerSyncService._();

  static String get _base => AuraFaceChatMailService.effectiveDefaultBaseUrl;

  static Future<void> syncPurchase({
    required String productId,
    required String purchaseId,
    String? purchaseToken,
    String? orderId,
    int? purchaseTimeMs,
    bool isSubscription = false,
    bool isRestore = false,
  }) async {
    final canonical = PlayBillingProducts.resolveCanonicalProductId(productId);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      BillingLog.warn('syncPurchase skipped: no Firebase user');
      return;
    }

    String? idToken;
    try {
      idToken = await user.getIdToken();
    } catch (e, st) {
      BillingLog.error('syncPurchase getIdToken failed', e, st);
      return;
    }
    if (idToken == null || idToken.isEmpty) return;

    final uri = Uri.parse('$_base/api/billing/purchases');
    final body = <String, dynamic>{
      'productId': canonical,
      'rawProductId': productId,
      'purchaseId': purchaseId,
      if (purchaseToken != null && purchaseToken.isNotEmpty) 'purchaseToken': purchaseToken,
      if (orderId != null && orderId.isNotEmpty) 'orderId': orderId,
      if (purchaseTimeMs != null) 'purchaseTimeMs': purchaseTimeMs,
      'isSubscription': isSubscription,
      'isRestore': isRestore,
      'platform': 'android',
    };

    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode == 404) {
        BillingLog.warn('syncPurchase: /api/billing/purchases not deployed (404)');
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BillingLog.error('syncPurchase failed ${res.statusCode} ${res.body}');
        return;
      }
      BillingLog.purchase('synced to server product=$canonical purchaseId=$purchaseId');
    } catch (e, st) {
      BillingLog.error('syncPurchase network error', e, st);
    }
  }
}
