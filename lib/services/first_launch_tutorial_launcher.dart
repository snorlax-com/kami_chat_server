import 'package:flutter/foundation.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/services/notification_launch_router.dart';
import 'package:kami_face_oracle/services/tutorial_diagnosis_local_store.dart';

/// 初回のみ: オープニング動画・年齢確認のあと性格診断チュートリアルを自動起動する。
class FirstLaunchTutorialLauncher {
  FirstLaunchTutorialLauncher._();

  static bool _launchInFlight = false;
  static bool _launchedThisSession = false;

  static bool get launchedThisSession => _launchedThisSession;

  static Future<void> maybeLaunch() async {
    if (E2E.isEnabled) return;
    if (NotificationLaunchRouter.skipOpeningSplash) return;
    if (_launchedThisSession) return;
    if (_launchInFlight) return;

    if (await TutorialDiagnosisLocalStore.shouldSkipAutoTutorialLaunch()) {
      debugPrint('[FirstLaunchTutorial] skip: tutorial diagnosis already used');
      return;
    }

    _launchInFlight = true;
    try {
      debugPrint('[FirstLaunchTutorial] launch tutorial');
      final ok = await AppNavigation.pushTutorialPersonalityDiagnosisWhenReady();
      if (ok) {
        _launchedThisSession = true;
        debugPrint('[FirstLaunchTutorial] launch ok');
      } else {
        debugPrint('[FirstLaunchTutorial] launch failed (navigator not ready)');
      }
    } finally {
      _launchInFlight = false;
    }
  }
}
