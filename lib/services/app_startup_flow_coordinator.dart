import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/features/consent/widgets/cookie_consent_banner.dart';
import 'package:kami_face_oracle/services/first_launch_tutorial_launcher.dart';

/// 起動直後フロー（許可→年齢確認→チュートリアル）の重複実行を防ぐ。
class AppStartupFlowCoordinator {
  AppStartupFlowCoordinator._();

  static bool _tutorialScheduleStarted = false;

  /// ホーム表示の準備が整ったあと、1回だけチュートリアル自動起動を試行する。
  static void scheduleTutorialLaunchOnce() {
    if (_tutorialScheduleStarted) return;
    _tutorialScheduleStarted = true;
    debugPrint('[StartupFlow] schedule tutorial launch (no startup permission screen)');
    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(_launchTutorialWithRetries());
    });
  }

  static Future<void> _launchTutorialWithRetries() async {
    await _waitUntilCookieConsentSettled();
    for (var attempt = 0; attempt < 6; attempt++) {
      await FirstLaunchTutorialLauncher.maybeLaunch();
      if (FirstLaunchTutorialLauncher.launchedThisSession) {
        debugPrint('[StartupFlow] tutorial launched attempt=$attempt');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    debugPrint('[StartupFlow] tutorial launch gave up after retries');
  }

  /// Cookie 同意シート表示中はチュートリアルを重ねない（起動直後の不安定化対策）。
  static Future<void> _waitUntilCookieConsentSettled() async {
    if (E2E.isEnabled) return;
    for (var i = 0; i < 120; i++) {
      final need = await CookieConsentBanner.needToShow();
      if (!need) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    debugPrint('[StartupFlow] cookie consent wait timeout — proceed tutorial');
  }
}
