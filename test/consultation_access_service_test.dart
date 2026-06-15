import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/services/consultation_access_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';

ConsultationAccessState _state({int normal = 0, int urgent = 0, bool subscribed = true}) {
  return ConsultationAccessState(
    isSubscribed: subscribed,
    normalTickets: normal,
    urgentTickets: urgent,
  );
}

void main() {
  test('resolveSendTicketKind は通常券を優先する', () {
    final kind = ConsultationAccessService.resolveSendTicketKind(
      _state(normal: 2, urgent: 1),
    );
    expect(kind, ConsultationSendTicketKind.normal);
  });

  test('resolveFirstSendTicketKind は至急選択時に至急券を使う', () {
    final kind = ConsultationAccessService.resolveFirstSendTicketKind(
      _state(normal: 2, urgent: 1),
      preference: ConsultationSendTicketKind.urgent,
    );
    expect(kind, ConsultationSendTicketKind.urgent);
  });

  test('resolveFirstSendTicketKind は通常選択時に通常券を使う', () {
    final kind = ConsultationAccessService.resolveFirstSendTicketKind(
      _state(normal: 2, urgent: 1),
      preference: ConsultationSendTicketKind.normal,
    );
    expect(kind, ConsultationSendTicketKind.normal);
  });

  test('至急券のみのときは至急になる', () {
    final kind = ConsultationAccessService.resolveFirstSendTicketKind(
      _state(normal: 0, urgent: 1),
      preference: ConsultationSendTicketKind.normal,
    );
    expect(kind, ConsultationSendTicketKind.urgent);
  });

  test('券不足時は null', () {
    final kind = ConsultationAccessService.resolveFirstSendTicketKind(
      _state(normal: 0, urgent: 0),
      preference: ConsultationSendTicketKind.urgent,
    );
    expect(kind, isNull);
  });

  test('通常券と至急券が両方あるとき自動選択は通常（旧挙動の再現）', () {
    final state = _state(normal: 1, urgent: 1);
    expect(
      ConsultationAccessService.resolveSendTicketKind(state),
      ConsultationSendTicketKind.normal,
    );
    expect(
      ConsultationAccessService.resolveFirstSendTicketKind(
        state,
        preference: ConsultationSendTicketKind.urgent,
      ),
      ConsultationSendTicketKind.urgent,
    );
  });

  test('canChooseUrgentSend は至急券1枚以上で true', () {
    expect(
      ConsultationAccessService.canChooseUrgentSend(_state(urgent: 1)),
      isTrue,
    );
    expect(
      ConsultationAccessService.canChooseUrgentSend(_state(urgent: 0)),
      isFalse,
    );
    expect(
      ConsultationAccessService.canChooseUrgentSend(
        _state(urgent: ConsultationTicketService.priorityCostPerSend),
      ),
      isTrue,
    );
  });
}
