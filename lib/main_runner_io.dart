import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/portrait_lock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kami_face_oracle/app_widgets.dart';
import 'package:kami_face_oracle/bootstrap/deferred_startup.dart';
import 'package:kami_face_oracle/bootstrap/opening_video_preload.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/services/notification_launch_router.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';
import 'package:kami_face_oracle/services/guest_session_service.dart';
import 'package:kami_face_oracle/services/remote_config_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/core/personality_mapping_table.dart';
import 'package:hive_flutter/hive_flutter.dart';

bool get _integrationTestConsultation =>
    bool.fromEnvironment('INTEGRATION_TEST_CONSULTATION', defaultValue: false);

/// スプラッシュ動画を出さない E2E 経路では、従来どおり初期化完了まで待ってから [runApp] する。
bool _skipOpeningSplashAwaitDeferredFirst() {
  if (!E2E.isEnabled) return false;
  if (_integrationTestConsultation) return true;
  try {
    final qp = Uri.base.queryParameters;
    return qp['route'] == 'camera' || qp['camera'] == '1';
  } catch (_) {
    return false;
  }
}

Future<void> _runDeferredInitIo() async {
  await PushNotificationService.instance.ensureLocalReady();
  await CloudService.init();
  await PushNotificationService.instance.init();
  await GuestSessionService.ensureGuestSessionId();
  await RemoteConfigService.instance.init();
  await IAPService.instance.init();
  await BackgroundMusicService().initialize();
  await PersonalityMappingTable.initialize();
  await Hive.openBox<Map>('skin_daily_records');
}

Future<void> runAppAsync() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  if (_skipOpeningSplashAwaitDeferredFirst()) {
    await DeferredStartup.awaitReady();
  }

  runApp(const ProviderScope(child: AuraFaceApp()));

  if (NotificationLaunchRouter.skipOpeningSplash) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AppNavigation.openConsultationChat());
    });
  }
}
