import 'package:shared_preferences/shared_preferences.dart';

/// 創設者（占い師）返信の通知済み状態（FCM・ポーリング共通）。
class DeveloperReplyNotifyPrefs {
  DeveloperReplyNotifyPrefs._();

  static const _prefsKeyNotifiedKeys = 'dev_reply_local_notify_keys_v3';
  static const _maxStoredKeys = 300;

  static String notifyKey(String chatId, int messageCreatedAt) =>
      '$chatId:$messageCreatedAt';

  static Future<Set<String>> _loadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_prefsKeyNotifiedKeys)?.toSet() ?? {};
  }

  static Future<void> _saveKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKeyNotifiedKeys, keys.toList());
  }

  static Future<bool> wasNotified({
    required String chatId,
    required int messageCreatedAt,
  }) async {
    if (messageCreatedAt <= 0) return true;
    final keys = await _loadKeys();
    return keys.contains(notifyKey(chatId, messageCreatedAt));
  }

  static Future<void> markNotified({
    required String chatId,
    required int messageCreatedAt,
  }) async {
    if (messageCreatedAt <= 0) return;
    final key = notifyKey(chatId, messageCreatedAt);
    final keys = await _loadKeys();
    if (keys.contains(key)) return;
    keys.add(key);
    if (keys.length > _maxStoredKeys) {
      final overflow = keys.length - _maxStoredKeys;
      keys.removeAll(keys.take(overflow));
    }
    await _saveKeys(keys);
  }
}
