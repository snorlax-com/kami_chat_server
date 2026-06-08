import 'dart:async';

import 'package:kami_face_oracle/services/notification_launch_router.dart';
import 'package:kami_face_oracle/services/notification_permission_prompt.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// integration_test 専用の dart-define フラグ。
class IntegrationTestFlags {
  IntegrationTestFlags._();

  static const _prefsForceCameraRoute = 'integration_test_force_camera_route_v1';
  static const _prefsConsultationMailTest = 'integration_test_consultation_mail_v1';

  static bool? _runtimeCameraRoute;
  static bool? _runtimeConsultationMailTest;

  static Future<void> enableConsultationMailTestMode() async {
    NotificationLaunchRouter.skipOpeningSplash = true;
    NotificationPermissionPrompt.suppressForIntegrationTest = true;
    PushNotificationService.suppressForIntegrationTest = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsConsultationMailTest, true);
    _runtimeConsultationMailTest = true;
  }

  /// true のとき占い相談画面を直起動し、Firebase 認証をバイパスしてメール送信を検証する。
  static bool get bypassConsultationFirebaseAuth =>
      _runtimeConsultationMailTest == true ||
      String.fromEnvironment('INTEGRATION_TEST_CONSULTATION', defaultValue: 'false') == 'true';

  /// integration_test 開始前に呼ぶ（端末プロセスへ SharedPreferences 経由で伝える）。
  static Future<void> enableCameraRouteForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsForceCameraRoute, true);
    _runtimeCameraRoute = true;
  }

  /// アプリ起動直前に呼び、integration_test のランタイムフラグを読み込む。
  static Future<void> loadRuntimeFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getBool(_prefsForceCameraRoute) ?? false;
    final fromDefine =
        String.fromEnvironment('INTEGRATION_TEST_CAMERA_ROUTE', defaultValue: 'false') ==
            'true';
    _runtimeCameraRoute = fromPrefs || fromDefine;

    final consultationFromPrefs = prefs.getBool(_prefsConsultationMailTest) ?? false;
    final consultationFromDefine =
        String.fromEnvironment('INTEGRATION_TEST_CONSULTATION', defaultValue: 'false') == 'true';
    _runtimeConsultationMailTest = consultationFromPrefs || consultationFromDefine;
  }

  static Future<void> clearRuntimeFlags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsForceCameraRoute);
    await prefs.remove(_prefsConsultationMailTest);
    _runtimeCameraRoute = false;
    _runtimeConsultationMailTest = false;
  }

  /// true のとき sideload 判定・テスト購入ダイアログを無効化し Play 課金経路を強制する。
  static bool get forcePlayBilling =>
      String.fromEnvironment('INTEGRATION_TEST_FORCE_PLAY_BILLING', defaultValue: 'false') ==
      'true';

  /// true のとき起動直後に E2E カメラ（疑似撮影→Reveal→結果）へ入る。
  static bool get cameraRoute =>
      _runtimeCameraRoute == true ||
      String.fromEnvironment('INTEGRATION_TEST_CAMERA_ROUTE', defaultValue: 'false') == 'true';

  static Completer<void>? _googleSignInHang;

  /// integration_test: Google ログインを意図的に待機させ、戻るキャンセルを検証する。
  static Future<void> armGoogleSignInHangForTest() async {
    _googleSignInHang = Completer<void>();
  }

  static bool get hasGoogleSignInHang => _googleSignInHang != null;

  static Future<void> waitGoogleSignInHangGate() async {
    final gate = _googleSignInHang;
    if (gate == null) return;
    await gate.future;
  }

  static void cancelGoogleSignInHangForTest() {
    final gate = _googleSignInHang;
    if (gate != null && !gate.isCompleted) {
      gate.completeError(StateError('integration_test_google_sign_in_cancelled'));
    }
    _googleSignInHang = null;
  }
}
