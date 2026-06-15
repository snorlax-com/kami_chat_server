import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/services/bridge_thread_local_store.dart';
import 'package:kami_face_oracle/services/consultation_chat_id.dart';
import 'package:kami_face_oracle/services/consultation_unified_thread.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/services/diagnosis_api_service.dart';

/// 占い相談で開くスレッド ID を「最新の相談」に揃える。
class ConsultationActiveThreadResolver {
  ConsultationActiveThreadResolver._();

  /// `consultation_{userId}_{ms}` / `consultation_new_{userId}_{ms}` の末尾タイムスタンプ。
  static int? timestampFromChatId(String chatId) => ConsultationChatId.timestampMs(chatId);

  static bool chatIdBelongsToUser(String chatId, String bridgeUserId) =>
      ConsultationChatId.belongsToUser(chatId, bridgeUserId);

  /// 相談 ID の作成時刻（末尾 ms）だけで最新スレッドを選ぶ（古い長いスレッドの最新返信で勝たない）。
  static Future<String?> resolveLatestChatId({
    required String bridgeUserId,
  }) async {
    final scores = <String, int>{};

    void consider(String? chatId, int scoreMs) {
      if (chatId == null || chatId.trim().isEmpty) return;
      final id = chatId.trim();
      if (!id.startsWith('consultation')) return;
      if (!chatIdBelongsToUser(id, bridgeUserId)) return;
      final ts = timestampFromChatId(id) ?? scoreMs;
      final prev = scores[id] ?? 0;
      if (ts > prev) scores[id] = ts;
    }

    final mailBridgeOnly = await ConsultationUnifiedThread.mailBridgeOnlyChatIds();

    void considerDisplay(String? chatId, int scoreMs) {
      if (chatId == null || chatId.trim().isEmpty) return;
      final id = chatId.trim();
      if (mailBridgeOnly.contains(id)) return;
      consider(id, scoreMs);
    }

    final active = await DeveloperChatPref.getActiveChatId();
    considerDisplay(active, timestampFromChatId(active ?? '') ?? 0);

    final cachedIds = await BridgeThreadLocalStore.listCachedChatIds();
    for (final id in cachedIds) {
      considerDisplay(id, timestampFromChatId(id) ?? 0);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        final token = await user.getIdToken();
        if (token != null && token.isNotEmpty) {
          final threads = await DiagnosisApiService.fetchMyThreads(idToken: token);
          for (final t in threads) {
            final id = t['id']?.toString();
            if (id == null || id.isEmpty) continue;
            var score = timestampFromChatId(id) ?? 0;
            final updated = t['updatedAt']?.toString();
            if (updated != null && updated.isNotEmpty) {
              final parsed = DateTime.tryParse(updated);
              if (parsed != null) {
                final ms = parsed.millisecondsSinceEpoch;
                if (ms > score) score = ms;
              }
            }
            considerDisplay(id, score);
          }
        }
      } catch (e) {
        debugPrint('[ConsultationActiveThreadResolver] threads/me failed: $e');
      }
    }

    if (scores.isEmpty) return null;

    var bestId = scores.keys.first;
    var bestScore = scores[bestId]!;
    for (final e in scores.entries) {
      if (e.value > bestScore) {
        bestId = e.key;
        bestScore = e.value;
      }
    }
    debugPrint('[ConsultationActiveThreadResolver] latest=$bestId score=$bestScore candidates=${scores.length}');
    return bestId;
  }

  /// 解決した chatId を prefs に保存。ピン留め中はより新しい相談 ID があるときだけ切替。
  static Future<void> applyLatestAsActive({
    required String bridgeUserId,
  }) async {
    final latest = await resolveLatestChatId(bridgeUserId: bridgeUserId);
    if (latest == null || latest.isEmpty) return;

    final pinned = await DeveloperChatPref.getPinnedChatId();
    if (pinned != null && pinned.isNotEmpty) {
      final pinnedTs = timestampFromChatId(pinned) ?? 0;
      final latestTs = timestampFromChatId(latest) ?? 0;
      if (latestTs <= pinnedTs) {
        final type = await DeveloperChatPref.getActiveConsultationType();
        await DeveloperChatPref.setActiveChatId(
          pinned,
          consultationType: type ?? ConsultationMailType.normal,
        );
        debugPrint('[ConsultationActiveThreadResolver] keep pinned=$pinned');
        return;
      }
      await DeveloperChatPref.clearPinnedChatId();
    }

    final active = await DeveloperChatPref.getActiveChatId();
    if (active == latest) return;

    final type = await DeveloperChatPref.getActiveConsultationType();
    await DeveloperChatPref.setActiveChatId(
      latest,
      consultationType: type ?? ConsultationMailType.normal,
    );
    debugPrint('[ConsultationActiveThreadResolver] active $active -> $latest');
  }
}
