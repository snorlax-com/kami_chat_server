import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kami_face_oracle/app_widgets.dart';
import 'package:kami_face_oracle/bootstrap/deferred_startup.dart';
import 'package:kami_face_oracle/bootstrap/opening_video_preload.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/feature/web_shutter/web_shutter_camera_view.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/guest_session_service.dart';
import 'package:kami_face_oracle/services/remote_config_service.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/core/personality_mapping_table.dart';
import 'package:hive_flutter/hive_flutter.dart';

bool get _integrationTestConsultation =>
    bool.fromEnvironment('INTEGRATION_TEST_CONSULTATION', defaultValue: false);

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

Future<void> _runDeferredInitWeb() async {
  registerWebShutterViewFactory();
  await CloudService.init();
  await GuestSessionService.ensureGuestSessionId();
  await RemoteConfigService.instance.init();
  await BackgroundMusicService().initialize();
  await PersonalityMappingTable.initialize();
  try {
    await Hive.initFlutter();
    await Hive.openBox<Map>('skin_daily_records');
  } catch (_) {}
}

Future<void> runAppAsync() async {
  WidgetsFlutterBinding.ensureInitialized();

  OpeningVideoPreload.start();
  DeferredStartup.begin(_runDeferredInitWeb);

  if (_skipOpeningSplashAwaitDeferredFirst()) {
    await DeferredStartup.awaitReady();
  }

  runApp(const ProviderScope(child: AuraFaceApp()));
}
