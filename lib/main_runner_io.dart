import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kami_face_oracle/app_widgets.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/remote_config_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/core/personality_mapping_table.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _intentChannel = MethodChannel('com.auraface.kami_face_oracle/intent');

Future<String?> _resolveAutoInputPathForAutoMode() async {
  try {
    final externalCacheDirs = await getExternalCacheDirectories();
    if (externalCacheDirs != null && externalCacheDirs.isNotEmpty) {
      for (final dir in externalCacheDirs) {
        final f = File('${dir.path}/auto_input.png');
        if (await f.exists()) return f.path;
      }
    }
  } catch (_) {}
  const candidates = [
    '/storage/emulated/0/Android/data/com.auraface.kami_face_oracle/cache/auto_input.png',
    '/sdcard/Android/data/com.auraface.kami_face_oracle/cache/auto_input.png',
  ];
  for (final p in candidates) {
    final f = File(p);
    if (await f.exists()) return f.path;
  }
  try {
    final extra = await _intentChannel.invokeMethod<Map<dynamic, dynamic>>('getIntentExtra');
    final path = extra?['image_path'] as String?;
    if (path != null && path.isNotEmpty) {
      final f = File(path);
      if (await f.exists()) return f.path;
    }
  } catch (_) {}
  return null;
}

Future<void> runAppAsync() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CloudService.init();
  await RemoteConfigService.instance.init();
  await IAPService.instance.init();
  await BackgroundMusicService().initialize();
  await PersonalityMappingTable.initialize();
  await Hive.initFlutter();
  await Hive.openBox<Map>('skin_daily_records');

  bool intentAutoMode = false;
  try {
    final extra = await _intentChannel.invokeMethod<Map<dynamic, dynamic>>('getIntentExtra');
    intentAutoMode = (extra?['auto_mode'] as bool?) ?? false;
  } catch (_) {}

  if (intentAutoMode) {
    final resolvedPath = await _resolveAutoInputPathForAutoMode();
    if (resolvedPath != null) {
      runApp(ProviderScope(child: AuraFaceAutoApp(initialImagePath: resolvedPath)));
      return;
    }
  }
  runApp(const ProviderScope(child: AuraFaceApp()));
}
