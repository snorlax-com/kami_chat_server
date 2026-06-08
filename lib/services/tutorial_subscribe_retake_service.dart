import 'package:flutter/foundation.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/services/tutorial_diagnosis_local_store.dart';

/// ログインせずにチュートリアルを終了したユーザーが、初回サブスク加入時に性格診断をやり直す。
class TutorialSubscribeRetakeService {
  TutorialSubscribeRetakeService._();

  static bool _launchInFlight = false;

  /// 加入が「未加入 → 加入」に変わった直後に呼ぶ。
  static Future<void> onSubscriptionActivated({
    required bool wasSubscribedBefore,
  }) async {
    if (wasSubscribedBefore) return;
    if (_launchInFlight) return;

    final guestExit = await TutorialDiagnosisLocalStore.didGuestExitWithoutLogin();
    if (!guestExit) return;

    _launchInFlight = true;
    try {
      debugPrint('[TutorialSubscribeRetake] launch personality diagnosis after subscribe');
      await TutorialDiagnosisLocalStore.prepareForRetakeDiagnosis();
      await Storage.clearTutorialDeity();
      await AppNavigation.pushTutorialPersonalityDiagnosisWhenReady(
        message: 'サブスクにご加入ありがとうございます。性格診断をもう一度受けてください。',
        force: true,
      );
    } finally {
      Future<void>.delayed(const Duration(seconds: 2), () {
        _launchInFlight = false;
      });
    }
  }
}
