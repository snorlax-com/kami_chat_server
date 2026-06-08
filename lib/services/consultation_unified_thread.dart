import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/bridge_thread_local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アプリ内では1つの占い相談タイムラインに統合し、
/// 至急メールだけ別 chatId（サーバー）で送るための紐付け。
class ConsultationUnifiedThread {
  ConsultationUnifiedThread._();

  static String _linkedKey(String displayChatId) =>
      'developer_chat_mail_bridge_ids_v1_$displayChatId';

  static const _mailBridgeOnlyKey = 'developer_chat_mail_bridge_only_ids_v1';

  static Future<void> linkMailBridgeChatId({
    required String displayChatId,
    required String mailBridgeChatId,
  }) async {
    if (displayChatId.isEmpty || mailBridgeChatId.isEmpty) return;
    if (displayChatId == mailBridgeChatId) return;

    final sp = await SharedPreferences.getInstance();
    final linked = {...?(sp.getStringList(_linkedKey(displayChatId)))};
    linked.add(mailBridgeChatId);
    await sp.setStringList(_linkedKey(displayChatId), linked.toList());

    final global = {...?(sp.getStringList(_mailBridgeOnlyKey))};
    global.add(mailBridgeChatId);
    await sp.setStringList(_mailBridgeOnlyKey, global.toList());
  }

  static Future<List<String>> mailBridgeChatIdsFor(String displayChatId) async {
    if (displayChatId.isEmpty) return const [];
    final sp = await SharedPreferences.getInstance();
    return sp.getStringList(_linkedKey(displayChatId)) ?? const [];
  }

  static Future<Set<String>> mailBridgeOnlyChatIds() async {
    final sp = await SharedPreferences.getInstance();
    return {...?(sp.getStringList(_mailBridgeOnlyKey))};
  }

  static Future<bool> isMailBridgeOnlyChatId(String chatId) async {
    if (chatId.isEmpty) return false;
    final set = await mailBridgeOnlyChatIds();
    return set.contains(chatId);
  }

  /// 表示用 chatId のローカル＋サーバーと、紐付く至急メール用 chatId を時系列統合。
  static Future<List<BridgeChatMessage>> loadUnifiedMessages({
    required AuraFaceChatMailService service,
    required String displayChatId,
  }) async {
    final local = await BridgeThreadLocalStore.load(displayChatId);
    final primary = await service.getThread(chatId: displayChatId);
    var merged = BridgeThreadLocalStore.merge(
      local,
      primary.success ? primary.messages : const [],
    );

    for (final mailId in await mailBridgeChatIdsFor(displayChatId)) {
      final mailLocal = await BridgeThreadLocalStore.load(mailId);
      final mailRes = await service.getThread(chatId: mailId);
      final mailMerged = BridgeThreadLocalStore.merge(
        mailLocal,
        mailRes.success ? mailRes.messages : const [],
      );
      merged = BridgeThreadLocalStore.merge(merged, mailMerged);
    }

    await BridgeThreadLocalStore.save(displayChatId, merged);
    return merged;
  }
}
