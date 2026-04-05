import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';

/// ホームの赤丸バッジ用。開発者（role=dev）メッセージで未読があるか。
class DeveloperChatUnreadService {
  DeveloperChatUnreadService._();

  static Future<bool> hasUnreadReply() async {
    final chatId = await DeveloperChatPref.getActiveChatId();
    if (chatId == null || chatId.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(AuraFaceChatMailService.prefKeyBaseUrl);
    final bridgeUrl = AuraFaceChatMailService.consultationSendBaseUrl(savedUrl);
    try {
      final service = AuraFaceChatMailService(baseUrl: bridgeUrl);
      final res = await service.getThread(chatId: chatId);
      if (!res.success) return false;
      final lastSeen = await DeveloperChatPref.getLastSeenDevCreatedAt();
      for (final m in res.messages) {
        if (m.isFromDev && m.createdAt > lastSeen) return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }
}
