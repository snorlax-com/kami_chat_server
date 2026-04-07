import 'package:kami_face_oracle/config/consultation_mail_types.dart';

/// 占い相談メール送信の呼び出し元（実機 logcat `AuraFaceMailSend` で追跡）
class ConsultationSendSource {
  ConsultationSendSource._();

  static const consultationPage = 'consultation_page';
  static const consultationPageNew = 'consultation_page_new';
  static const developerChatFollowUp = 'developer_chat_follow_up';
  static const pillarChatTutorial = 'pillar_chat_tutorial';
  static const mailBridgeTestPage = 'consultation_mail_bridge_test_page';
}

/// 新規送信時の consultationType をボタン押下だけで決める（保存済み Pref は使わない）
class ConsultationSendContract {
  ConsultationSendContract._();

  static String consultationTypeForNewSend({required bool urgent}) =>
      urgent ? ConsultationMailType.priorityGuidance : ConsultationMailType.normal;

  static bool isPriorityType(String consultationType) =>
      consultationType == ConsultationMailType.priorityGuidance;

  static int consultationPriorityForType(String consultationType) =>
      isPriorityType(consultationType) ? 2 : 1;

  static bool urgentFieldForType(String consultationType) => isPriorityType(consultationType);
}
