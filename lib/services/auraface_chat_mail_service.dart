// lib/services/auraface_chat_mail_service.dart
// AuraFace Chat Mail Bridge API（POST /api/chat/send, GET /api/chat/thread）

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kami_face_oracle/config/mail_bridge_config.dart';

class AuraFaceChatMailService {
  /// ローカル開発用（シミュレータ・エミュレータ）
  static const String defaultBaseUrl = 'http://127.0.0.1:3000';

  /// 本番URL: ビルド時 --dart-define か lib/config/mail_bridge_config.dart の kMailBridgeProductionUrl を使用。
  static const String _productionFromEnv = String.fromEnvironment('MAIL_BRIDGE_URL', defaultValue: '');
  static String? get productionBaseUrl {
    if (_productionFromEnv.isNotEmpty) return _productionFromEnv.trim();
    return kMailBridgeProductionUrl;
  }

  /// 実機デバッグ用: ビルド時に --dart-define=DEV_MAIL_BRIDGE_URL=http://PCのIP:3000 を指定すると未保存時もそのURLを使用
  static const String _devUrlFromEnv = String.fromEnvironment('DEV_MAIL_BRIDGE_URL', defaultValue: '');

  /// SharedPreferences に保存するキー（テスト画面でサーバーURLを上書き保存する用）
  static const String prefKeyBaseUrl = 'mail_bridge_base_url';

  /// 実際に使うベースURL。本番では localhost フォールバックを禁止する。
  /// 優先: 保存URL > 本番URL > 開発用URL(実機) > デバッグ時のみ 127.0.0.1
  static String get effectiveDefaultBaseUrl {
    final prod = productionBaseUrl;
    if (prod != null && prod.trim().isNotEmpty) return prod.trim();
    if (kReleaseMode) {
      throw StateError(
        'MAIL_BRIDGE_URL is not configured for release build. '
        'Set kMailBridgeProductionUrl in lib/config/mail_bridge_config.dart or build with --dart-define=MAIL_BRIDGE_URL=...',
      );
    }
    if (_devUrlFromEnv.trim().isNotEmpty) return _devUrlFromEnv.trim();
    return defaultBaseUrl;
  }

  final String baseUrl;

  AuraFaceChatMailService({String? baseUrl})
      : baseUrl = _normalizeBaseUrl(
          (baseUrl?.trim() ?? '').isEmpty ? effectiveDefaultBaseUrl : baseUrl!.trim(),
        );

  static String _normalizeBaseUrl(String u) {
    return u.endsWith('/') ? u.substring(0, u.length - 1) : u;
  }

  /// 接続テスト（GET /health）。成功時 true、失敗時は例外または false。
  Future<bool> testConnection() async {
    try {
      final uri = Uri.parse('$baseUrl/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// ユーザーメッセージを送信（DB 保存 + 開発者 Gmail 通知）
  Future<SendChatResponse> send({
    required String userId,
    required String chatId,
    required String message,
    String? userEmail,
    String? userName,
  }) async {
    debugPrint('[MailBridge] send baseUrl=$baseUrl');
    try {
      final uri = Uri.parse('$baseUrl/api/chat/send');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'chatId': chatId,
              'userEmail': userEmail ?? '',
              'userName': userName ?? 'ユーザー',
              'message': message,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      if (res.statusCode == 200 && body != null && body['success'] == true) {
        debugPrint('[MailBridge] send success chatId=$chatId');
        return SendChatResponse(
          success: true,
          chatId: body['chatId'] as String? ?? chatId,
          messageId: body['messageId'] as int?,
        );
      }
      final err = body?['message']?.toString() ?? body?['error']?.toString() ?? 'HTTP ${res.statusCode}';
      debugPrint('[MailBridge] send failed: $err');
      return SendChatResponse(success: false, error: err);
    } catch (e, st) {
      debugPrint('[MailBridge] send exception: $e');
      debugPrint('[MailBridge] stack: $st');
      return SendChatResponse(success: false, error: 'ネットワークエラー: $e');
    }
  }

  /// スレッド取得（ポーリング用）。since は Unix ミリ秒で指定するとその時刻以降のみ取得
  Future<ThreadResponse> getThread({
    required String chatId,
    int? since,
  }) async {
    try {
      final query = <String, String>{'chatId': chatId};
      if (since != null) query['since'] = since.toString();
      final uri = Uri.parse('$baseUrl/api/chat/thread').replace(queryParameters: query);
      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      if (res.statusCode == 200 && body != null && body['messages'] != null) {
        final list = body['messages'] as List<dynamic>;
        final messages = list
            .map((m) => BridgeChatMessage(
                  id: m['id'] as int? ?? 0,
                  role: m['role'] as String? ?? 'user',
                  text: m['text'] as String? ?? '',
                  createdAt: m['createdAt'] is int ? m['createdAt'] as int : 0,
                ))
            .toList();
        return ThreadResponse(
          success: true,
          chatId: body['chatId'] as String? ?? chatId,
          messages: messages,
        );
      }
      return ThreadResponse(
        success: false,
        error: body?['error']?.toString() ?? 'HTTP ${res.statusCode}',
      );
    } catch (e) {
      return ThreadResponse(success: false, error: 'ネットワークエラー: $e');
    }
  }
}

class BridgeChatMessage {
  final int id;
  final String role; // 'user' | 'dev'
  final String text;
  final int createdAt;

  BridgeChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
  });

  bool get isFromDev => role == 'dev';
}

class SendChatResponse {
  final bool success;
  final String? chatId;
  final int? messageId;
  final String? error;

  SendChatResponse({
    required this.success,
    this.chatId,
    this.messageId,
    this.error,
  });
}

class ThreadResponse {
  final bool success;
  final String? chatId;
  final List<BridgeChatMessage> messages;
  final String? error;

  ThreadResponse({
    required this.success,
    this.chatId,
    this.messages = const [],
    this.error,
  });
}
