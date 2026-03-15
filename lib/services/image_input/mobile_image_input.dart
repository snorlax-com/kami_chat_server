import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'image_input.dart';

/// Mobile: image_picker + Intent（既存の MethodChannel 名に合わせる）
class ImageInputImpl implements ImageInput {
  static const _intentChannel = MethodChannel('com.auraface.kami_face_oracle/intent');
  final ImagePicker _picker = ImagePicker();

  @override
  Future<PickedImage?> pick({required bool preferCamera}) async {
    final source = preferCamera ? ImageSource.camera : ImageSource.gallery;
    final xfile = await _picker.pickImage(source: source);
    if (xfile == null) return null;
    final bytes = await xfile.readAsBytes();
    final name = xfile.name.isNotEmpty ? xfile.name : 'upload.jpg';
    return PickedImage(
      bytes: bytes,
      filename: name,
      mimeType: _guessMimeFromName(name),
    );
  }

  @override
  Future<PickedImage?> pickFromExternalPathOrIntentIfAvailable() async {
    try {
      final externalCacheDirs = await getExternalCacheDirectories();
      if (externalCacheDirs != null && externalCacheDirs.isNotEmpty) {
        for (final dir in externalCacheDirs) {
          final f = File('${dir.path}/auto_input.png');
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            return PickedImage(
              bytes: bytes,
              filename: 'auto_input.png',
              mimeType: 'image/png',
            );
          }
        }
      }
    } catch (_) {}

    const candidates = [
      '/storage/emulated/0/Android/data/com.auraface.kami_face_oracle/cache/auto_input.png',
      '/sdcard/Android/data/com.auraface.kami_face_oracle/cache/auto_input.png',
    ];
    for (final p in candidates) {
      final f = File(p);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        return PickedImage(bytes: bytes, filename: 'auto_input.png', mimeType: 'image/png');
      }
    }

    try {
      final extra = await _intentChannel.invokeMethod<Map<dynamic, dynamic>>('getIntentExtra');
      final path = extra?['image_path'] as String? ?? extra?['cache_auto_input'] as String?;
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          final name = path.split('/').last;
          return PickedImage(
            bytes: bytes,
            filename: name,
            mimeType: _guessMimeFromName(name),
          );
        }
      }
    } catch (_) {}

    return null;
  }

  static String _guessMimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
