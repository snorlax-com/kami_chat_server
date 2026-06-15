import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/push/developer_reply_notification_id.dart';

void main() {
  test('different chatIds with same createdAt get different notification ids', () {
    const ts = 1781427537567;
    final idA = developerReplyNotificationId(
      chatId: 'consultation_userA_123',
      messageCreatedAt: ts,
    );
    final idB = developerReplyNotificationId(
      chatId: 'consultation_userA_456',
      messageCreatedAt: ts,
    );
    expect(idA, isNot(equals(idB)));
  });

  test('same chatId and createdAt is stable', () {
    const chatId = 'consultation_userA_123';
    const ts = 1781427537567;
    final id1 = developerReplyNotificationId(chatId: chatId, messageCreatedAt: ts);
    final id2 = developerReplyNotificationId(chatId: chatId, messageCreatedAt: ts);
    expect(id1, equals(id2));
  });
}
