import 'dart:convert';
import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';

/// メールブリッジのチャットスレッドを **端末に保存**（オフライン閲覧・サーバー揮発時の復元）。
///
/// - **iOS / Android**: アプリのドキュメント領域に JSON ファイル（容量制限に強い）。
/// - **Web**: `SharedPreferences` のみ（従来キー）。
/// - サーバーと同様 **90 日**より古いメッセージは破棄。
class BridgeThreadLocalStore {
  BridgeThreadLocalStore._();

  static const int retentionMs = 90 * 24 * 60 * 60 * 1000;
  static const String _prefsKeyPrefix = 'bridge_thread_cache_v1_';
  static const String _subdir = 'auraface_bridge_chat';

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  static List<BridgeChatMessage> pruneByRetention(Iterable<BridgeChatMessage> list) {
    final now = _nowMs();
    return list.where((m) => now - m.createdAt <= retentionMs).toList();
  }

  static String _normalizeText(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// サーバーが古いメッセージを `normal` 既定で返しても、端末側の `priority_guidance` を潰さない。
  static BridgeChatMessage _mergeConsultationType(
    BridgeChatMessage primary,
    BridgeChatMessage? secondary,
  ) {
    final a = primary.consultationType?.trim();
    final b = secondary?.consultationType?.trim();
    if (a == ConsultationMailType.priorityGuidance ||
        b == ConsultationMailType.priorityGuidance) {
      return BridgeChatMessage(
        id: primary.id,
        role: primary.role,
        text: primary.text,
        createdAt: primary.createdAt,
        consultationType: ConsultationMailType.priorityGuidance,
      );
    }
    return primary;
  }

  /// ローカル先行表示とサーバー取得の同一メッセージを統合（messageId 優先）。
  static List<BridgeChatMessage> merge(
    List<BridgeChatMessage> local,
    List<BridgeChatMessage> server,
  ) {
    final byId = <int, BridgeChatMessage>{};
    final orphans = <BridgeChatMessage>[];

    void put(BridgeChatMessage m, {required bool serverWins}) {
      if (m.id > 0) {
        final prev = byId[m.id];
        if (prev == null) {
          byId[m.id] = m;
        } else if (serverWins) {
          byId[m.id] = _mergeConsultationType(m, prev);
        } else {
          byId[m.id] = _mergeConsultationType(m, prev);
        }
        return;
      }
      orphans.add(m);
    }

    for (final m in local) {
      put(m, serverWins: false);
    }
    for (final m in server) {
      put(m, serverWins: true);
    }

    final out = <BridgeChatMessage>[...byId.values];
    for (final m in orphans) {
      final norm = _normalizeText(m.text);
      final duplicate = out.any(
        (o) => o.role == m.role && _normalizeText(o.text) == norm,
      );
      if (!duplicate) out.add(m);
    }

    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pruneByRetention(out);
  }

  /// 送信直後など、サーバー GET 前にユーザー発言を端末に残す。
  static Future<void> appendUserMessage({
    required String chatId,
    required String text,
    required String consultationType,
    int? messageId,
    int? createdAtMs,
  }) async {
    if (chatId.isEmpty) return;
    final existing = await load(chatId);
    final mid = messageId;
    if (mid != null && mid > 0 && existing.any((e) => e.id == mid)) {
      return;
    }
    final ts = createdAtMs ?? _nowMs();
    final m = BridgeChatMessage(
      id: mid != null && mid > 0 ? mid : ts,
      role: 'user',
      text: text,
      createdAt: ts,
      consultationType: consultationType,
    );
    final norm = _normalizeText(text);
    if (mid == null || mid <= 0) {
      final dup = existing.any(
        (e) => e.role == 'user' && _normalizeText(e.text) == norm,
      );
      if (dup) return;
    }
    await save(chatId, merge(existing, [m]));
  }

  static String _prefsLegacyKey(String chatId) => '$_prefsKeyPrefix$chatId';

  static String _fileBaseName(String chatId) {
    final enc = base64Url.encode(utf8.encode(chatId));
    return enc.length <= 200 ? enc : '${chatId.hashCode.abs()}.b64';
  }

  static Future<io.Directory?> _mobileCacheDir() async {
    if (kIsWeb) return null;
    try {
      final root = await getApplicationDocumentsDirectory();
      final dir = io.Directory('${root.path}/$_subdir');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<io.File?> _fileFor(String chatId) async {
    final dir = await _mobileCacheDir();
    if (dir == null) return null;
    return io.File('${dir.path}/${_fileBaseName(chatId)}.json');
  }

  /// 端末にキャッシュされている相談スレッド ID 一覧。
  static Future<List<String>> listCachedChatIds() async {
    final ids = <String>{};

    if (!kIsWeb) {
      final dir = await _mobileCacheDir();
      if (dir != null && await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is! io.File || !entity.path.endsWith('.json')) continue;
          final base = entity.uri.pathSegments.last.replaceAll('.json', '');
          try {
            final decoded = utf8.decode(base64Url.decode(base));
            if (decoded.isNotEmpty) ids.add(decoded);
          } catch (_) {
            // hash ファイル名などはスキップ
          }
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_prefsKeyPrefix)) {
        final id = key.substring(_prefsKeyPrefix.length);
        if (id.isNotEmpty) ids.add(id);
      }
    }

    return ids.toList();
  }

  static List<BridgeChatMessage> _decodeList(String raw) {
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) {
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
    } catch (_) {
      return [];
    }
  }

  static Future<List<BridgeChatMessage>> load(String chatId) async {
    if (chatId.isEmpty) return [];

    if (!kIsWeb) {
      final f = await _fileFor(chatId);
      if (f != null && await f.exists()) {
        try {
          final raw = await f.readAsString();
          if (raw.isNotEmpty) {
            return pruneByRetention(_decodeList(raw));
          }
        } catch (_) {}
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_prefsLegacyKey(chatId));
    if (legacy != null && legacy.isNotEmpty) {
      final list = pruneByRetention(_decodeList(legacy));
      await save(chatId, list);
      await prefs.remove(_prefsLegacyKey(chatId));
      return list;
    }

    return [];
  }

  static Future<void> save(String chatId, List<BridgeChatMessage> messages) async {
    if (chatId.isEmpty) return;
    final pruned = pruneByRetention(messages);
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

    if (!kIsWeb) {
      final f = await _fileFor(chatId);
      if (f != null) {
        try {
          if (pruned.isEmpty) {
            if (await f.exists()) await f.delete();
            return;
          }
          final tmp = io.File('${f.path}.tmp');
          await tmp.writeAsString(encoded);
          if (await f.exists()) await f.delete();
          await tmp.rename(f.path);
          return;
        } catch (_) {}
      }
    }

    final prefs = await SharedPreferences.getInstance();
    if (pruned.isEmpty) {
      await prefs.remove(_prefsLegacyKey(chatId));
      return;
    }
    await prefs.setString(_prefsLegacyKey(chatId), encoded);
  }

  static Future<void> clear(String chatId) async {
    if (chatId.isEmpty) return;
    if (!kIsWeb) {
      final f = await _fileFor(chatId);
      try {
        if (f != null && await f.exists()) await f.delete();
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsLegacyKey(chatId));
  }
}
