import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kami_face_oracle/core/integration_test_flags.dart';

/// integration_test 用: メールブリッジ HTTP を差し替え、送信ペイロードを検証する。
class IntegrationTestConsultationMailStub {
  IntegrationTestConsultationMailStub._();

  static bool _active = false;
  static Map<String, dynamic>? lastSendBody;
  static String? lastSendChatId;

  static Future<bool> isEnabled() async {
    if (_active) return true;
    if (IntegrationTestFlags.bypassConsultationFirebaseAuth) {
      _active = true;
      return true;
    }
    return false;
  }

  static void reset() {
    _active = false;
    lastSendBody = null;
    lastSendChatId = null;
  }

  static void install() {
    lastSendBody = null;
    lastSendChatId = null;
    _active = true;
    unawaited(IntegrationTestFlags.enableConsultationMailTestMode());
  }

  static Future<http.Response> postSend({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    lastSendBody = Map<String, dynamic>.from(decoded);
    lastSendChatId = decoded['chatId']?.toString();

    final urgent = decoded['urgent'] == true ||
        decoded['consultationType'] == 'priority_guidance';
    final ct = urgent ? 'priority_guidance' : 'normal';

    return http.Response(
      jsonEncode({
        'status': 'ok',
        'success': true,
        'chatId': lastSendChatId,
        'messageId': 9001,
        'mailSent': true,
        'consultationType': ct,
        'mailUrgent': urgent,
        'mailEmergencyDelivered': urgent,
        'mailSubject': urgent ? '【至急相談】integration_test' : '【通常相談】integration_test',
        'mailApiBuild': 'v2-consultation-tier-r12-emergency-retry',
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }

  static Future<http.Response> getThread({
    required Uri uri,
    required Map<String, String> headers,
  }) async {
    final chatId = uri.queryParameters['chatId'] ?? '';
    return http.Response(
      jsonEncode({
        'status': 'ok',
        'chatId': chatId,
        'messages': const <Map<String, dynamic>>[],
        'retentionExpired': false,
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}
