import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/services/consultation_chat_id.dart';

void main() {
  const userA = 'gAddIP7VZ3eEY6kKe1eiwuEyfYh1';
  const userB = 'anotherFirebaseUid123';

  test('belongsToUser は自分の consultation chatId のみ true', () {
    final own = 'consultation_${userA}_1780906322780';
    expect(ConsultationChatId.belongsToUser(own, userA), isTrue);
    expect(ConsultationChatId.belongsToUser(own, userB), isFalse);
  });

  test('belongsToUser は consultation_new 形式も判定する', () {
    final id = 'consultation_new_${userB}_1780906322781';
    expect(ConsultationChatId.belongsToUser(id, userB), isTrue);
    expect(ConsultationChatId.belongsToUser(id, userA), isFalse);
  });

  test('timestampMs は末尾の ms を返す', () {
    expect(
      ConsultationChatId.timestampMs('consultation_${userA}_1780906322780'),
      1780906322780,
    );
  });
}
