import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/bridge_thread_local_store.dart';

void main() {
  test('merge: サーバー normal でもローカル priority_guidance を維持', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    const id = 42;
    const text = '（緊急）テスト';
    final local = [
      BridgeChatMessage(
        id: id,
        role: 'user',
        text: text,
        createdAt: now,
        consultationType: ConsultationMailType.priorityGuidance,
      ),
    ];
    final server = [
      BridgeChatMessage(
        id: id,
        role: 'user',
        text: text,
        createdAt: now,
        consultationType: ConsultationMailType.normal,
      ),
    ];
    final merged = BridgeThreadLocalStore.merge(local, server);
    expect(merged, hasLength(1));
    expect(merged.first.consultationType, ConsultationMailType.priorityGuidance);
  });
}
