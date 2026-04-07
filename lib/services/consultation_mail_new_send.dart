import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';

/// 実機の「新規相談」送信のみ。至急/通常を bool だけで固定し、consultationType の取り違えを防ぐ。
class ConsultationMailNewSend {
  ConsultationMailNewSend._();

  /// [urgent]==true のとき必ず priority_guidance 系フィールド一式になる。
  static Future<SendChatResponse> send({
    required AuraFaceChatMailService mailService,
    required String userId,
    required String chatId,
    required String message,
    required String sendSource,
    required bool urgent,
    String? userEmail,
    String? userName,
  }) {
    return mailService.sendLockedNewConsultation(
      userId: userId,
      chatId: chatId,
      message: message,
      sendSource: sendSource,
      urgent: urgent,
      userEmail: userEmail,
      userName: userName,
    );
  }

  static String consultationTypeForPref({required bool urgent}) =>
      urgent ? ConsultationMailType.priorityGuidance : ConsultationMailType.normal;
}
