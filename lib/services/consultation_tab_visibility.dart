/// 占い相談タブをユーザーが実際に見ているか（既読・通知判定用）。
class ConsultationTabVisibility {
  ConsultationTabVisibility._();

  static bool tabSelected = false;
  static bool appResumed = true;

  static bool get userIsViewingConsultation => tabSelected && appResumed;
}
