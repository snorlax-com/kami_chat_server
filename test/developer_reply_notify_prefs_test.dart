import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/developer_reply_notify_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('wasNotified returns false until marked', () async {
    expect(
      await DeveloperReplyNotifyPrefs.wasNotified(
        chatId: 'chat_a',
        messageCreatedAt: 1000,
      ),
      isFalse,
    );
  });

  test('multiple chat threads do not overwrite each other', () async {
    await DeveloperReplyNotifyPrefs.markNotified(
      chatId: 'chat_a',
      messageCreatedAt: 1000,
    );
    await DeveloperReplyNotifyPrefs.markNotified(
      chatId: 'chat_b',
      messageCreatedAt: 2000,
    );

    expect(
      await DeveloperReplyNotifyPrefs.wasNotified(
        chatId: 'chat_a',
        messageCreatedAt: 1000,
      ),
      isTrue,
    );
    expect(
      await DeveloperReplyNotifyPrefs.wasNotified(
        chatId: 'chat_b',
        messageCreatedAt: 2000,
      ),
      isTrue,
    );
  });

  test('markNotified is idempotent', () async {
    await DeveloperReplyNotifyPrefs.markNotified(
      chatId: 'chat_a',
      messageCreatedAt: 1000,
    );
    await DeveloperReplyNotifyPrefs.markNotified(
      chatId: 'chat_a',
      messageCreatedAt: 1000,
    );

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList('dev_reply_local_notify_keys_v3') ?? [];
    expect(keys.where((k) => k == 'chat_a:1000').length, 1);
  });
}
