import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';

void main() {
  const founder = '創設者（占い師）';

  test('notification body uses founder fortune teller label', () {
    expect(
      PushNotificationService.notificationBody,
      '$founderから返信が届いています。タップして確認してください。',
    );
    expect(
      PushNotificationService.notificationBody,
      isNot(contains('開発者')),
    );
  });

  test('mail and notification user strings do not contain 開発者', () {
    const mailRelatedStrings = [
      PushNotificationService.notificationBody,
      '創設者（占い師）にメールで通知しました。',
      '創設者（占い師）へのGmail通知に失敗した可能性があります。',
      '相談は送信しましたが、創設者（占い師）へのGmail通知に失敗しました。',
      '創設者（占い師）から占い相談への返信があったとき、お知らせします。',
      '通知が許可されました。創設者（占い師）からの返信をお知らせします。',
    ];

    for (final s in mailRelatedStrings) {
      expect(s, isNot(contains('開発者')), reason: s);
      expect(s, contains(founder), reason: s);
    }
  });
}
