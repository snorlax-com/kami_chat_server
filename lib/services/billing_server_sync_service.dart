import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:kami_face_oracle/config/play_billing_products.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/auth_api_headers.dart';
import 'package:kami_face_oracle/services/billing_log.dart';

/// Google Play 購入をサーバーで検証してから券付与の根拠とする。
class BillingServerSyncService {
  BillingServerSyncService._();

  static String get _base => AuraFaceChatMailService.effectiveDefaultBaseUrl;

  /// サーバー検証成功時のみ true。トークン欠落・検証失敗・二重送信は false。
  static Future<bool> verifyPurchaseOnServer({
    required String productId,
    required String purchaseToken,
    required bool isSubscription,
  }) async {
    final playProductId = PlayBillingProducts.playStoreProductId(productId);
    if (purchaseToken.isEmpty) {
      BillingLog.warn('verifyPurchase skipped: empty purchaseToken');
      return false;
    }

    final authHeaders = await AuthApiHeaders.authorizationJson();
    if (!authHeaders.containsKey('Authorization')) {
      BillingLog.warn('verifyPurchase skipped: not signed in');
      return false;
    }

    final productType = isSubscription ? 'subs' : 'inapp';
    final uri = Uri.parse('$_base/api/billing/verify');
    final body = jsonEncode({
      'productId': playProductId,
      'purchaseToken': purchaseToken,
      'productType': productType,
    });

    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              ...authHeaders,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        BillingLog.purchase('server verify ok product=$playProductId');
        return true;
      }
      BillingLog.error('verifyPurchase failed status=${res.statusCode}');
      return false;
    } catch (e, st) {
      BillingLog.error('verifyPurchase network error', e, st);
      return false;
    }
  }

  /// 監査用の購入記録（検証とは別。失敗しても券付与は verify に依存）。
  static Future<void> syncPurchaseAudit({
    required String productId,
    required String purchaseId,
    String? purchaseToken,
    String? orderId,
    int? purchaseTimeMs,
    bool isSubscription = false,
    bool isRestore = false,
  }) async {
    final canonical = PlayBillingProducts.resolveCanonicalProductId(productId);
    final authHeaders = await AuthApiHeaders.authorizationJson();
    if (!authHeaders.containsKey('Authorization')) return;

    final uri = Uri.parse('$_base/api/billing/purchases');
    final body = jsonEncode({
      'productId': canonical,
      'rawProductId': productId,
      'purchaseId': purchaseId,
      if (purchaseToken != null && purchaseToken.isNotEmpty) 'purchaseToken': purchaseToken,
      if (orderId != null && orderId.isNotEmpty) 'orderId': orderId,
      if (purchaseTimeMs != null) 'purchaseTimeMs': purchaseTimeMs,
      'isSubscription': isSubscription,
      'isRestore': isRestore,
      'platform': 'android',
    });

    try {
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              ...authHeaders,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode == 404) return;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        BillingLog.error('syncPurchaseAudit failed ${res.statusCode}');
      }
    } catch (e, st) {
      BillingLog.error('syncPurchaseAudit network error', e, st);
    }
  }
}
