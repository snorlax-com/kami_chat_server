// lib/services/auraface_chat_mail_service.dart
// チャットAPI（POST /api/chat/send, GET /api/chat/thread）本番: https://kami-chat-server.onrender.com

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kami_face_oracle/config/mail_bridge_config.dart';

/// Render 無料枠の初回遅延を考慮したタイムアウト（秒）
const int _kTimeoutSeconds = 60;

class AuraFaceChatMailService {
  static const String defaultBaseUrl = 'http://127.0.0.1:3000';

  static const String _productionFromEnv = String.fromEnvironment('MAIL_BRIDGE_URL', defaultValue: '');
  static String? get productionBaseUrl {
    if (_productionFromEnv.isNotEmpty) return _productionFromEnv.trim();
    return kMailBridgeProductionUrl;
  }

  static const String _devUrlFromEnv = String.fromEnvironment('DEV_MAIL_BRIDGE_URL', defaultValue: '');
  static const String prefKeyBaseUrl = 'mail_bridge_base_url';

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

  static void _log(String msg) {
    if (kDebugMode) debugPrint(msg);
  }

  /// エラー種別を分かりやすく分類
  static String _classifyError(Object e, [int? statusCode, String? body]) {
    final s = e.toString();
    if (s.contains('Timeout') || s.contains('タイムアウト')) return 'タイムアウト';
    if (s.contains('Connection') || s.contains('SocketException') || s.contains('Failed host')) return '通信不可';
    if (statusCode != null) {
      if (statusCode >= 500) return '500系';
      if (statusCode >= 400) return '400系';
    }
    if (body == null || body.isEmpty) return '空レスポンス';
    if (s.contains('FormatException') || s.contains('json')) return 'JSONパース失敗';
    return 'エラー: $e';
  }

  /// 接続テスト（GET /health）。Render 初回遅延のため 60 秒まで許容。
  Future<bool> testConnection() async {
    final uri = Uri.parse('$baseUrl/health');
    try {
      _log('[MailBridge] GET $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: _kTimeoutSeconds));
      _log('[MailBridge] health status=${res.statusCode} body=${res.body}');
      return res.statusCode == 200;
    } catch (e) {
      _log('[MailBridge] health error: ${_classifyError(e)}');
      return false;
    }
  }

  /// ユーザーメッセージを送信。サーバーが success:true または status が ok/received/saved_but_mail_failed で成功とみなす。
  Future<SendChatResponse> send({
    required String userId,
    required String chatId,
    required String message,
    String? userEmail,
    String? userName,
  }) async {
    final uri = Uri.parse('$baseUrl/api/chat/send');
    final bodyMap = {
      'userId': userId,
      'chatId': chatId,
      'userEmail': userEmail ?? '',
      'userName': userName ?? 'ユーザー',
      'message': message,
    };
    final bodyStr = jsonEncode(bodyMap);
    try {
      _log('[MailBridge] POST $uri body=$bodyStr');
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: bodyStr,
          )
          .timeout(const Duration(seconds: _kTimeoutSeconds));

      Map<String, dynamic>? body;
      try {
        body = res.body.isEmpty ? null : jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {
        _log('[MailBridge] send response parse error body=${res.body}');
        return SendChatResponse(success: false, error: _classifyError(const FormatException('parse'), res.statusCode, res.body));
      }

      _log('[MailBridge] send status=${res.statusCode} body=$body');

      final success = res.statusCode == 200 &&
          body != null &&
          (body['success'] == true ||
              body['status'] == 'ok' ||
              body['status'] == 'received' ||
              body['status'] == 'saved_but_mail_failed');
      if (success) {
        final mid = body['messageId'];
        final messageId = mid is int ? mid : (mid is num ? mid.toInt() : null);
        final ms = body['mailSent'];
        final bool? mailSent = ms is bool
            ? ms
            : ms is String
                ? (ms.toLowerCase() == 'true'
                    ? true
                    : ms.toLowerCase() == 'false'
                        ? false
                        : null)
                : null;
        final mailErr = body['error']?.toString();
        _log('[MailBridge] send mailSent=$mailSent error=$mailErr');
        return SendChatResponse(
          success: true,
          chatId: body['chatId'] as String? ?? chatId,
          messageId: messageId,
          mailSent: mailSent,
          mailError: (mailSent == false && mailErr != null && mailErr.isNotEmpty) ? mailErr : null,
        );
      }
      final err = body?['message']?.toString() ?? body?['error']?.toString() ?? 'HTTP ${res.statusCode}';
      return SendChatResponse(success: false, error: err);
    } catch (e, st) {
      final classified = _classifyError(e);
      _log('[MailBridge] send exception: $classified');
      if (kDebugMode) debugPrint('[MailBridge] $st');
      return SendChatResponse(
        success: false,
        error: classified.startsWith('エラー') ? classified : 'ネットワークエラー: $classified',
      );
    }
  }

  /// スレッド取得。since は Unix ミリ秒で指定するとその時刻以降のみ取得。
  Future<ThreadResponse> getThread({
    required String chatId,
    int? since,
  }) async {
    final query = <String, String>{'chatId': chatId};
    if (since != null) query['since'] = since.toString();
    final uri = Uri.parse('$baseUrl/api/chat/thread').replace(queryParameters: query);
    try {
      _log('[MailBridge] GET $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: _kTimeoutSeconds));

      if (res.body.isEmpty) {
        _log('[MailBridge] thread empty response status=${res.statusCode}');
        if (res.statusCode == 200) {
          return ThreadResponse(success: true, chatId: chatId, messages: []);
        }
        return ThreadResponse(success: false, error: _classifyError(Exception('empty'), res.statusCode, res.body));
      }

      Map<String, dynamic>? body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>?;
      } catch (_) {
        _log('[MailBridge] thread parse error body=${res.body}');
        return ThreadResponse(success: false, error: 'JSONパース失敗');
      }

      _log('[MailBridge] thread status=${res.statusCode} body=$body');

      if (res.statusCode == 404) {
        return ThreadResponse(success: false, error: 'スレッドAPIがありません(404)。サーバーを最新にデプロイしてください。');
      }
      if (res.statusCode == 200 && body != null) {
        final list = body['messages'];
        if (list == null) {
          return ThreadResponse(success: true, chatId: body['chatId'] as String? ?? chatId, messages: []);
        }
        final messages = (list as List<dynamic>)
            .map((m) => BridgeChatMessage(
                  id: m['id'] as int? ?? 0,
                  role: m['role'] as String? ?? 'user',
                  text: m['text'] as String? ?? '',
                  createdAt: m['createdAt'] is int ? m['createdAt'] as int : 0,
                ))
            .toList();
        messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return ThreadResponse(
          success: true,
          chatId: body['chatId'] as String? ?? chatId,
          messages: messages,
        );
      }
      final err = body?['error']?.toString() ?? 'HTTP ${res.statusCode}';
      return ThreadResponse(success: false, error: err);
    } catch (e, st) {
      final classified = _classifyError(e);
      _log('[MailBridge] thread exception: $classified');
      if (kDebugMode) debugPrint('[MailBridge] $st');
      return ThreadResponse(
        success: false,
        error: classified.startsWith('エラー') ? classified : 'ネットワークエラー: $classified',
      );
    }
  }
}

class BridgeChatMessage {
  final int id;
  final String role;
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

  /// サーバーが返す場合のみ。false のときは Gmail 通知に失敗（チャット保存は成功していることが多い）。
  final bool? mailSent;

  /// mailSent==false のときサーバーから返るメール失敗理由（例: Resend 未設定）。
  final String? mailError;

  SendChatResponse({
    required this.success,
    this.chatId,
    this.messageId,
    this.error,
    this.mailSent,
    this.mailError,
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
