/// 創設者（占い師）返信ローカル通知 ID（FCM 前景/背景・Watchdog 共通）。
int developerReplyNotificationId({
  required String chatId,
  int? messageCreatedAt,
  int? messageId,
}) {
  if (messageCreatedAt != null && messageCreatedAt > 0) {
    return Object.hash(chatId, messageCreatedAt) & 0x7FFFFFFF;
  }
  if (messageId != null && messageId > 0) {
    return Object.hash(chatId, messageId) & 0x7FFFFFFF;
  }
  return DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
}

int? parseDevReplyCreatedAt(Map<String, dynamic> data) {
  final raw = data['createdAt'];
  if (raw == null) return null;
  return int.tryParse(raw.toString());
}

int? parseDevReplyMessageId(Map<String, dynamic> data) {
  final raw = data['messageId'];
  if (raw == null) return null;
  return int.tryParse(raw.toString());
}
