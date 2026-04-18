import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';

/// チャットスレッドを端末にキャッシュ（オフライン閲覧用）。
/// サーバーと同様 **90 日**より古いメッセージは保存・表示対象から外す。
class BridgeThreadLocalStore {
  BridgeThreadLocalStore._();

  static const int retentionMs = 90 * 24 * 60 * 60 * 1000;

  static String _key(String chatId) => 'bridge_thread_cache_v1_$chatId';

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  static List<BridgeChatMessage> pruneByRetention(Iterable<BridgeChatMessage> list) {
    final now = _nowMs();
    return list.where((m) => now - m.createdAt <= retentionMs).toList();
  }

  static List<BridgeChatMessage> merge(
    List<BridgeChatMessage> local,
    List<BridgeChatMessage> server,
  ) {
    final seen = <String>{};
    final out = <BridgeChatMessage>[];
    void add(BridgeChatMessage m) {
      final k = '${m.createdAt}|${m.role}|${m.text.hashCode}';
      if (seen.add(k)) out.add(m);
    }
    for (final m in local) {
      add(m);
    }
    for (final m in server) {
      add(m);
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pruneByRetention(out);
  }

  static Future<List<BridgeChatMessage>> load(String chatId) async {
    if (chatId.isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(chatId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = decoded.map((e) {
        final m = e as Map<String, dynamic>;
        final id = m['id'];
        final ct = m['consultationType'];
        return BridgeChatMessage(
          id: id is int ? id : (id is num ? id.toInt() : 0),
          role: m['role'] as String? ?? 'user',
          text: m['text'] as String? ?? '',
          createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
          consultationType: ct is String ? ct : ct?.toString(),
        );
      }).toList();
      return pruneByRetention(list);
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String chatId, List<BridgeChatMessage> messages) async {
    if (chatId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final pruned = pruneByRetention(messages);
    if (pruned.isEmpty) {
      await prefs.remove(_key(chatId));
      return;
    }
    final encoded = jsonEncode(
      pruned
          .map(
            (m) => {
              'id': m.id,
              'role': m.role,
              'text': m.text,
              'createdAt': m.createdAt,
              if (m.consultationType != null) 'consultationType': m.consultationType,
            },
          )
          .toList(),
    );
    await prefs.setString(_key(chatId), encoded);
  }

  static Future<void> clear(String chatId) async {
    if (chatId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(chatId));
  }
}
