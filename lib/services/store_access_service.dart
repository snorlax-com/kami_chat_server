import 'package:kami_face_oracle/services/consultation_access_service.dart';

/// ストアタブ・ストア画面へのアクセス可否。
class StoreAccessService {
  StoreAccessService._();

  static Future<bool> canOpenStore() async {
    final state = await ConsultationAccessService.loadState();
    return state.isSubscribed;
  }
}
