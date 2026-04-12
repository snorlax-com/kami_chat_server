import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';

/// kami_chat_server の診断・claim API（メールブリッジと同一 base）
class DiagnosisApiService {
  DiagnosisApiService._();

  static String get _base => AuraFaceChatMailService.effectiveDefaultBaseUrl;

  static Future<void> saveTutorialDiagnosis({
    required String guestSessionId,
    required String pillarKey,
    required Map<String, dynamic> detailJson,
    String? summaryText,
    String? sourceImageUrl,
  }) async {
    final uri = Uri.parse('$_base/api/diagnosis/tutorial');
    final body = <String, dynamic>{
      'guestSessionId': guestSessionId,
      'pillarKey': pillarKey,
      'detailJson': detailJson,
      if (summaryText != null) 'summaryText': summaryText,
      if (sourceImageUrl != null) 'sourceImageUrl': sourceImageUrl,
    };
    final res = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    if (res.statusCode == 404) {
      debugPrint(
        '[DiagnosisApi] POST /api/diagnosis/tutorial → 404（identity API 未デプロイ）。'
        'Render で kami_chat_server 最新をデプロイしてください。',
      );
      return;
    }
    if (res.statusCode != 200) {
      throw Exception('tutorial save failed: ${res.statusCode} ${res.body}');
    }
  }

  static Future<Map<String, dynamic>> claimGuestData({
    required String guestSessionId,
    required String idToken,
    String authProvider = 'firebase',
  }) async {
    final uri = Uri.parse('$_base/api/auth/claim-guest-data');
    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'guestSessionId': guestSessionId,
            'authProvider': authProvider,
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (res.statusCode != 200) {
      throw Exception('claim failed: ${res.statusCode} ${res.body}');
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return m;
  }

  /// 開発用: サーバーに IDENTITY_DEV_SECRET / IDENTITY_DEV_UID があるとき
  static Future<Map<String, dynamic>> claimGuestDataDevBypass({
    required String guestSessionId,
    required String devSecret,
  }) async {
    final uri = Uri.parse('$_base/api/auth/claim-guest-data');
    final res = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-identity-dev-secret': devSecret,
          },
          body: jsonEncode({'guestSessionId': guestSessionId, 'authProvider': 'dev'}),
        )
        .timeout(const Duration(seconds: 45));
    if (res.statusCode != 200) {
      throw Exception('claim dev failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>?> fetchMyDiagnosis({required String idToken}) async {
    final uri = Uri.parse('$_base/api/diagnosis/me');
    final res = await http
        .get(
          uri,
          headers: {'Authorization': 'Bearer $idToken'},
        )
        .timeout(const Duration(seconds: 45));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      debugPrint('[DiagnosisApi] me failed ${res.statusCode} ${res.body}');
      return null;
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> fetchMyThreads({required String idToken}) async {
    final uri = Uri.parse('$_base/api/chat/threads/me');
    final res = await http
        .get(
          uri,
          headers: {'Authorization': 'Bearer $idToken'},
        )
        .timeout(const Duration(seconds: 45));
    if (res.statusCode != 200) return [];
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final list = m['threads'];
    if (list is! List) return [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
