/// 占い相談 chatId の形式判定（`consultation_{userId}_{ms}` 等）。
class ConsultationChatId {
  ConsultationChatId._();

  static int? timestampMs(String chatId) {
    final m = RegExp(r'_(\d{13,})$').firstMatch(chatId.trim());
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// スレッド ID が指定ユーザーのものか（他アカウントのスレッドを開かない）。
  static bool belongsToUser(String chatId, String bridgeUserId) {
    final id = chatId.trim();
    final u = bridgeUserId.trim();
    if (!id.startsWith('consultation') || u.isEmpty) return false;
    return RegExp('^consultation(_new)?_${RegExp.escape(u)}_').hasMatch(id);
  }
}
