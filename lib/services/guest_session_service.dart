import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';

/// サーバー発行の guest_session_id を保持（チュートリアル診断の仮保存・認証後 claim 用）
class GuestSessionService {
  GuestSessionService._();

  static const prefKey = 'guest_session_id';

  static Future<String?> readStoredId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefKey);
  }

  /// アプリ起動時に1回呼ぶ。サーバーに取りに行き、失敗時はローカル ID のみ（オフライン用）。
  static Future<String> ensureGuestSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(prefKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final base = AuraFaceChatMailService.effectiveDefaultBaseUrl;
    try {
      final uri = Uri.parse('$base/api/auth/guest-session');
      final res = await http
          .post(uri, headers: const {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final m = jsonDecode(res.body) as Map<String, dynamic>?;
        final id = m?['guestSessionId'] as String?;
        if (id != null && id.isNotEmpty) {
          await prefs.setString(prefKey, id);
          return id;
        }
      }
      debugPrint('[GuestSession] server guest-session failed status=${res.statusCode} body=${res.body}');
    } catch (e) {
      debugPrint('[GuestSession] ensure error: $e');
    }

    final localId = 'guest_local_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString(prefKey, localId);
    return localId;
  }
}
