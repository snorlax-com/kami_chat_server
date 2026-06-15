import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/services/consultation_access_service.dart';

/// 占い相談の送信経路（追記 vs 新規スレッド / 至急メール種別）。
class ConsultationSendRouting {
  ConsultationSendRouting._();

  static ({
    ConsultationSendTicketKind ticketKind,
    bool useFirstConsultationApi,
    bool urgent,
  })? resolve({
    required bool showConsultationChat,
    required bool threadOpensWithPriority,
    required ConsultationSendTicketKind preference,
    required ConsultationAccessState state,
  }) {
    if (showConsultationChat && threadOpensWithPriority) {
      final canNormal = ConsultationAccessService.canChooseNormalSend(state);
      final canUrgent = ConsultationAccessService.canChooseUrgentSend(state);

      // 至急券がなく通常券だけあるときは、UI 選択に関係なく通常追記へ。
      if (!canUrgent && canNormal) {
        return (
          ticketKind: ConsultationSendTicketKind.normal,
          useFirstConsultationApi: false,
          urgent: false,
        );
      }
      if (preference == ConsultationSendTicketKind.normal && canNormal) {
        return (
          ticketKind: ConsultationSendTicketKind.normal,
          useFirstConsultationApi: false,
          urgent: false,
        );
      }
      if (canUrgent) {
        return (
          ticketKind: ConsultationSendTicketKind.urgent,
          useFirstConsultationApi: false,
          urgent: true,
        );
      }
      return null;
    }

    final kind = ConsultationAccessService.resolveFirstSendTicketKind(
      state,
      preference: preference,
    );
    if (kind == null) return null;

    final urgent = kind == ConsultationSendTicketKind.urgent;
    if (!showConsultationChat) {
      return (
        ticketKind: kind,
        useFirstConsultationApi: true,
        urgent: urgent,
      );
    }

    if (urgent) {
      // 通常スレッド上で至急を選んだときはメール用に別 chatId へ送る（表示は同一タイムライン）。
      return (
        ticketKind: kind,
        useFirstConsultationApi: true,
        urgent: true,
      );
    }

    return (
      ticketKind: kind,
      useFirstConsultationApi: false,
      urgent: false,
    );
  }
}
