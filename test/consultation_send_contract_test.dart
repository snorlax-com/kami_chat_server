import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/config/consultation_send_contract.dart';

void main() {
  test('至急新規送信の consultationType / priority / urgent が揃う', () {
    expect(
      ConsultationSendContract.consultationTypeForNewSend(urgent: true),
      ConsultationMailType.priorityGuidance,
    );
    expect(
      ConsultationSendContract.consultationPriorityForType(ConsultationMailType.priorityGuidance),
      2,
    );
    expect(
      ConsultationSendContract.urgentFieldForType(ConsultationMailType.priorityGuidance),
      isTrue,
    );
  });

  test('通常新規送信は normal / priority 1 / urgent false', () {
    expect(
      ConsultationSendContract.consultationTypeForNewSend(urgent: false),
      ConsultationMailType.normal,
    );
    expect(
      ConsultationSendContract.consultationPriorityForType(ConsultationMailType.normal),
      1,
    );
    expect(
      ConsultationSendContract.urgentFieldForType(ConsultationMailType.normal),
      isFalse,
    );
  });
}
