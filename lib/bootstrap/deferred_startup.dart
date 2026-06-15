import 'dart:async';

import 'package:flutter/foundation.dart';

/// [runApp] 前に重い初期化を待たず、起動後にバックグラウンドで走らせるための単一 Future。
class DeferredStartup {
  DeferredStartup._();

  static Future<void>? _future;

  /// 初回のみ [work] を起動する（二度目以降は無視）。
  static void begin(Future<void> Function() work) {
    _future ??= () async {
      try {
        await work();
        debugPrint('[DeferredStartup] init complete');
      } catch (e, st) {
        debugPrint('[DeferredStartup] init failed: $e\n$st');
      }
    }();
  }

  /// スプラッシュ終了時など、初期化完了を待つ（タイムアウト付き）。
  static Future<void> awaitReady({Duration timeout = const Duration(seconds: 10)}) async {
    final f = _future ?? Future<void>.value();
    try {
      await f.timeout(timeout);
    } on TimeoutException {
      debugPrint('[DeferredStartup] awaitReady timeout after ${timeout.inSeconds}s — continuing');
    }
  }
}
