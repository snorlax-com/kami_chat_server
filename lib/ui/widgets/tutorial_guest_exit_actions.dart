import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/services/auraface_auth_service.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/tutorial_diagnosis_local_store.dart';
import 'package:kami_face_oracle/ui/pages/main_tab_shell.dart';
import 'package:kami_face_oracle/ui/widgets/tutorial_guest_exit_confirm_dialog.dart';

/// チュートリアル性格診断で、Google ログイン前に戻る／終了するときの共通処理。
class TutorialGuestExitActions {
  TutorialGuestExitActions._();

  static bool _busy = false;
  static int _lastPromptAtMs = 0;

  /// Google（非匿名）ログイン完了までは確認ダイアログを出す。
  static bool shouldConfirmExit({bool tutorialFlow = false}) {
    if (!CloudService.isFirebaseAppReady) return true;
    final u = FirebaseAuth.instance.currentUser;
    return u == null || u.isAnonymous;
  }

  static const exitDialogRouteName = 'tutorial_guest_exit_dialog';

  /// 前面に残った終了確認ダイアログを閉じる（busy 復旧用）。
  static void dismissExitDialogIfOpen() {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((route) {
      return route.settings.name != exitDialogRouteName || route.isFirst;
    });
    _busy = false;
  }

  static Future<void> finishWithoutLogin(BuildContext context) async {
    await TutorialDiagnosisLocalStore.markGuestExitedWithoutLogin();
    final rootNav = appNavigatorKey.currentState;
    if (rootNav != null) {
      // ignore: avoid_print
      print('[GuestExit] finishWithoutLogin via root navigator');
      await rootNav.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const MainTabShell()),
        (route) => false,
      );
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MainTabShell()),
      (route) => false,
    );
  }

  static Future<void> signInWithGoogleOnly() async {
    if (!CloudService.isFirebaseAppReady) return;
    await AurafaceAuthService.signInWithGoogle();
  }

  /// 進行中のログイン等で [ _busy ] が立っていても確認ダイアログを出す（明示的な終了操作向け）。
  static void clearBusyForExplicitExit() {
    if (_busy) {
      // ignore: avoid_print
      print('[GuestExit] clear busy for explicit exit');
    }
    _busy = false;
  }

  /// 戻る／終了リンク／Android 戻る（重複呼び出しは無視）。
  static Future<void> promptExitIfNeeded(
    BuildContext context, {
    Future<void> Function()? onLogin,
    Future<void> Function()? onExitWithoutLogin,
    bool tutorialFlow = false,
    bool forcePrompt = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_busy) {
      if (forcePrompt) {
        clearBusyForExplicitExit();
      } else {
        // ignore: avoid_print
        print('[GuestExit] prompt skipped (busy)');
        return;
      }
    }
    if (!forcePrompt && now - _lastPromptAtMs < 400) {
      // ignore: avoid_print
      print('[GuestExit] prompt skipped (debounce)');
      return;
    }

    if (!shouldConfirmExit(tutorialFlow: tutorialFlow)) {
      if (context.mounted) Navigator.of(context).maybePop();
      return;
    }

    if (!context.mounted) return;

    _busy = true;
    _lastPromptAtMs = now;
    try {
      // ignore: avoid_print
      print('[GuestExit] prompt → dialog tutorial=$tutorialFlow force=$forcePrompt');
      final choice = await TutorialGuestExitConfirmDialog.show(context);
      // ignore: avoid_print
      print('[GuestExit] prompt result=$choice');
      if (!context.mounted || choice == null) return;

      // 長い Google ログイン中も終了操作をブロックしない
      _busy = false;

      if (choice == TutorialGuestExitChoice.login) {
        if (onLogin != null) {
          await onLogin();
        } else {
          await signInWithGoogleOnly();
        }
        return;
      }

      if (onExitWithoutLogin != null) {
        await onExitWithoutLogin();
      } else {
        await finishWithoutLogin(context);
      }
    } finally {
      _busy = false;
    }
  }
}
