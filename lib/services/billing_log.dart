import 'package:flutter/foundation.dart';

/// Google Play Billing ログ（logcat: `I flutter` / `adb logcat | grep BILLING`）。
class BillingLog {
  BillingLog._();

  static void info(String message) {
    debugPrint('[BILLING] $message');
  }

  static void purchase(String message) {
    debugPrint('[BILLING PURCHASE] $message');
  }

  static void error(String message, [Object? err, StackTrace? st]) {
    debugPrint('[BILLING ERROR] $message${err != null ? ': $err' : ''}');
    if (st != null) debugPrint('[BILLING ERROR] $st');
  }

  static void warn(String message) {
    debugPrint('[BILLING WARN] $message');
  }
}
