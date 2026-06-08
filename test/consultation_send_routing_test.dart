import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/services/consultation_access_service.dart';
import 'package:kami_face_oracle/services/consultation_send_routing.dart';

ConsultationAccessState _state({int normal = 0, int urgent = 0}) {
  return ConsultationAccessState(
    isSubscribed: true,
    normalTickets: normal,
    urgentTickets: urgent,
  );
}

void main() {
  test('新規相談・至急選択は first API + urgent', () {
    final r = ConsultationSendRouting.resolve(
      showConsultationChat: false,
      threadOpensWithPriority: false,
      preference: ConsultationSendTicketKind.urgent,
      state: _state(urgent: 1),
    );
    expect(r?.useFirstConsultationApi, isTrue);
    expect(r?.urgent, isTrue);
    expect(r?.ticketKind, ConsultationSendTicketKind.urgent);
  });

  test('通常スレッド追記は followUp + normal', () {
    final r = ConsultationSendRouting.resolve(
      showConsultationChat: true,
      threadOpensWithPriority: false,
      preference: ConsultationSendTicketKind.normal,
      state: _state(normal: 1),
    );
    expect(r?.useFirstConsultationApi, isFalse);
    expect(r?.urgent, isFalse);
  });

  test('通常スレッドで至急選択は新規スレッド + urgent', () {
    final r = ConsultationSendRouting.resolve(
      showConsultationChat: true,
      threadOpensWithPriority: false,
      preference: ConsultationSendTicketKind.urgent,
      state: _state(urgent: 1),
    );
    expect(r?.useFirstConsultationApi, isTrue);
    expect(r?.urgent, isTrue);
    expect(r?.ticketKind, ConsultationSendTicketKind.urgent);
  });

  test('至急スレッド追記は followUp + urgent', () {
    final r = ConsultationSendRouting.resolve(
      showConsultationChat: true,
      threadOpensWithPriority: true,
      preference: ConsultationSendTicketKind.normal,
      state: _state(urgent: 1),
    );
    expect(r?.useFirstConsultationApi, isFalse);
    expect(r?.urgent, isTrue);
  });

  test('至急スレッドでも通常券選択時は followUp + normal', () {
    final r = ConsultationSendRouting.resolve(
      showConsultationChat: true,
      threadOpensWithPriority: true,
      preference: ConsultationSendTicketKind.normal,
      state: _state(normal: 1, urgent: 0),
    );
    expect(r?.useFirstConsultationApi, isFalse);
    expect(r?.urgent, isFalse);
    expect(r?.ticketKind, ConsultationSendTicketKind.normal);
  });

  test('至急スレッドで至急券なし・通常券のみは preference 不問で normal', () {
    final r = ConsultationSendRouting.resolve(
      showConsultationChat: true,
      threadOpensWithPriority: true,
      preference: ConsultationSendTicketKind.urgent,
      state: _state(normal: 1, urgent: 0),
    );
    expect(r?.useFirstConsultationApi, isFalse);
    expect(r?.urgent, isFalse);
    expect(r?.ticketKind, ConsultationSendTicketKind.normal);
  });
}
