import 'package:flutter/foundation.dart';

/// 課金ログ（他サービスと同様 debugPrint → logcat `I flutter`）。
class BillingLog {
  BillingLog._();

  static void info(String message) {
    debugPrint('[AuraFaceBilling] $message');
  }

  static void error(String message, [Object? err, StackTrace? st]) {
    debugPrint('[AuraFaceBilling] ERROR $message${err != null ? ': $err' : ''}');
    if (st != null) debugPrint('[AuraFaceBilling] $st');
  }
}
