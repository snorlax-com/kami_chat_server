import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/portrait_lock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kami_face_oracle/app_widgets.dart';
import 'package:kami_face_oracle/bootstrap/deferred_startup.dart';
import 'package:kami_face_oracle/bootstrap/opening_video_preload.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/core/integration_test_flags.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/services/notification_launch_router.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';
import 'package:kami_face_oracle/services/guest_session_service.dart';
import 'package:kami_face_oracle/services/remote_config_service.dart';
import 'package:kami_face_oracle/services/billing_log.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/core/personality_mapping_table.dart';
import 'package:hive_flutter/hive_flutter.dart';

bool get _integrationTestConsultation => IntegrationTestFlags.bypassConsultationFirebaseAuth;

/// 占い相談の統合テストだけ [runApp] 前に初期化完了を待つ（メール送信に Firebase 等が必要）。
/// カメラ E2E は疑似撮影のみなので待たず UI を先に出し、初期化はバックグラウンド継続。
bool _awaitDeferredInitBeforeRunApp() {
  return E2E.isEnabled && _integrationTestConsultation;
}

Future<void> _runDeferredInitIo() async {
  await PushNotificationService.instance.ensureLocalReady();
  await CloudService.init();
  await PushNotificationService.instance.init();
  await GuestSessionService.ensureGuestSessionId();
  await RemoteConfigService.instance.init();
  BillingLog.info('deferred init: starting IAP');
  await IAPService.instance.init();
  await BackgroundMusicService().initialize();
  await PersonalityMappingTable.initialize();
}

Future<void> runAppAsync() async {
  WidgetsFlutterBinding.ensureInitialized();
  // integration_test の prefs フラグは dart-define より先に読む
  await IntegrationTestFlags.loadRuntimeFlags();
  await lockPortraitOrientation();

  try {
    await Hive.initFlutter();
  } catch (e, st) {
    debugPrint('[Hive] initFlutter failed: $e\n$st');
  }

  // 通知タップ起動: ローカル／FCM を runApp 前に検知してスプラッシュを省略
  await PushNotificationService.instance.ensureLocalReady();
  await PushNotificationService.instance.consumeColdStartNotificationTap();
  await CloudService.init();
  await PushNotificationService.instance.consumeFcmInitialMessageIfAny();

  // 動画デコードと各種 init を runApp より前に待たず並列化し、黒い待ち時間を短くする。
  OpeningVideoPreload.start();
  DeferredStartup.begin(_runDeferredInitIo);

  if (_awaitDeferredInitBeforeRunApp()) {
    await DeferredStartup.awaitReady();
  }

  runApp(const ProviderScope(child: AuraFaceApp()));

  // 通知タップで chatId があるときだけ再遷移（スプラッシュ省略のみでは RootGate が既に占い相談を開く）
  if (NotificationLaunchRouter.skipOpeningSplash && AppNavigation.hasPendingConsultationChat) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AppNavigation.openConsultationChat());
    });
  }
}
