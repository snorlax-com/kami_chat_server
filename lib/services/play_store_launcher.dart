import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kami_face_oracle/config/consultation_subscription_config.dart';
import 'package:kami_face_oracle/services/billing_log.dart';
import 'package:url_launcher/url_launcher.dart';

/// Google Play ストア / サブスク管理画面を開く。
class PlayStoreLauncher {
  PlayStoreLauncher._();

  static const _channel = MethodChannel('com.auraface.kami_face_oracle/billing');
  static const androidPackage = 'com.auraface.kami_face_oracle';

  /// アプリの Play ストアページ（内部テスト参加用）。
  static Future<bool> openAppListing() async {
    return openUrl(
      'https://play.google.com/store/apps/details?id=$androidPackage',
      marketUrl: 'market://details?id=$androidPackage',
    );
  }

  /// 定期購入の管理・解除画面。
  static Future<bool> openSubscriptionManagement() async {
    final sku = ConsultationSubscriptionConfig.productId;
    final urls = [
      'https://play.google.com/store/account/subscriptions?package=$androidPackage&sku=$sku',
      'https://play.google.com/store/account/subscriptions?sku=$sku&package=$androidPackage',
      'https://play.google.com/store/account/subscriptions',
    ];
    for (final url in urls) {
      if (await openUrl(url)) return true;
    }
    return false;
  }

  /// HTTPS / market URL を Play ストアアプリ優先で開く。
  static Future<bool> openUrl(String httpsUrl, {String? marketUrl}) async {
    if (Platform.isAndroid) {
      try {
        final ok = await _channel.invokeMethod<bool>('openPlayStoreUrl', {
          'url': httpsUrl,
          'marketUrl': marketUrl,
        });
        if (ok == true) {
          BillingLog.info('openPlayStoreUrl native ok: $httpsUrl');
          return true;
        }
      } catch (e, st) {
        BillingLog.error('openPlayStoreUrl native failed', e, st);
      }
    }

    for (final uri in [
      if (marketUrl != null) Uri.parse(marketUrl),
      Uri.parse(httpsUrl),
    ]) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          BillingLog.info('launchUrl ok: $uri');
          return true;
        }
      } catch (e) {
        BillingLog.error('launchUrl failed $uri', e);
      }
    }
    return false;
  }
}
