// lib/services/support_chat_service.dart
// サポートチャットサービス（メールベース、Firestore無し）

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kami_face_oracle/services/server_personality_service.dart';

class SupportChatService {
  static const String _defaultApiUrl = 'http://45.77.26.42:8000';
  static const String _apiKey = 'CHANGE_ME_SUPER_SECRET'; // TODO: 環境変数やRemote Configから取得

  String? _apiUrl;

  SupportChatService({String? apiUrl}) {
    _apiUrl = apiUrl ?? _defaultApiUrl;
  }

  /// サポート相談を送信
  Future<SendSupportResponse> sendSupport({
    required String userId,
    required Map<String, dynamic> diagnosis,
    required List<ChatMessage> chat,
    String? cid,
    Map<String, dynamic>? meta,
  }) async {
    try {
      final url = Uri.parse('$_apiUrl/v1/support/send');

      final payload = {
        'user_id': userId,
        if (cid != null) 'cid': cid,
        'diagnosis': diagnosis,
        'chat': chat.map((m) => m.toJson()).toList(),
        if (meta != null) 'meta': meta,
      };

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': _apiKey,
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return SendSupportResponse(
          success: true,
          cid: json['cid'] as String,
        );
      } else {
        return SendSupportResponse(
          success: false,
          error: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      return SendSupportResponse(
        success: false,
        error: 'ネットワークエラー: $e',
      );
    }
  }

  /// チャットメッセージを取得（ポーリング用）
  Future<GetChatResponse> getChat({
    required String cid,
    int? sinceId,
  }) async {
    try {
      final uri = Uri.parse('$_apiUrl/v1/chat/$cid').replace(
        queryParameters: sinceId != null ? {'since_id': sinceId.toString()} : null,
      );

      final response = await http.get(
        uri,
        headers: {
          'x-api-key': _apiKey,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final messages = (json['messages'] as List).map((m) => ChatMessage.fromJson(m)).toList();

        return GetChatResponse(
          success: true,
          cid: json['cid'] as String,
          messages: messages,
        );
      } else {
        return GetChatResponse(
          success: false,
          error: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      return GetChatResponse(
        success: false,
        error: 'ネットワークエラー: $e',
      );
    }
  }
}

class ChatMessage {
  final String role;
  final String text;
  final String? ts;
  final int? id;
  final String? source;
  final String? createdAt;

  ChatMessage({
    required this.role,
    required this.text,
    this.ts,
    this.id,
    this.source,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        if (ts != null) 'ts': ts,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] ?? 'user',
      text: json['text'] ?? '',
      ts: json['ts']?.toString(),
      id: json['id'] as int?,
      source: json['source']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

class SendSupportResponse {
  final bool success;
  final String? cid;
  final String? error;

  SendSupportResponse({
    required this.success,
    this.cid,
    this.error,
  });
}

class GetChatResponse {
  final bool success;
  final String? cid;
  final List<ChatMessage> messages;
  final String? error;

  GetChatResponse({
    required this.success,
    this.cid,
    this.messages = const [],
    this.error,
  });
}
