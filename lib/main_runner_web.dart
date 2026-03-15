import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kami_face_oracle/app_widgets.dart';
import 'package:kami_face_oracle/feature/web_shutter/web_shutter_camera_view.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/remote_config_service.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/core/personality_mapping_table.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> runAppAsync() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerWebShutterViewFactory();
  await CloudService.init();
  await RemoteConfigService.instance.init();
  await BackgroundMusicService().initialize();
  await PersonalityMappingTable.initialize();
  try {
    await Hive.initFlutter();
    await Hive.openBox<Map>('skin_daily_records');
  } catch (_) {}
  runApp(const ProviderScope(child: AuraFaceApp()));
}
