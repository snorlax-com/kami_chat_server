import 'dart:async';

import 'package:video_player/video_player.dart';

/// 起動直後からオープニング動画のデコードを始め、[SplashVideoPage] 表示時には初期化済みになりやすくする。
class OpeningVideoPreload {
  OpeningVideoPreload._();

  static const String assetPath = 'assets/videos/opening_animation.mp4';

  static Future<VideoPlayerController?>? _future;

  static void start() {
    _future ??= _load();
  }

  static Future<VideoPlayerController?> _load() async {
    try {
      final c = VideoPlayerController.asset(assetPath);
      await c.initialize();
      c.setLooping(false);
      c.setVolume(0.0);
      return c;
    } catch (_) {
      return null;
    }
  }

  /// 事前 [start] 済みなら共有の初期化結果を返し、以降は新規プリロード可能にする。
  static Future<VideoPlayerController?> take() async {
    start();
    final f = _future;
    if (f == null) return null;
    final c = await f;
    _future = null;
    return c;
  }
}
