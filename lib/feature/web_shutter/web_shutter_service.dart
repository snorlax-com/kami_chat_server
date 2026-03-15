import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'web_shutter_bridge.dart';
import 'web_shutter_state.dart';

/// Web 向け自動シャッターの状態管理・ポーリング
class WebShutterService {
  WebShutterService._();
  static final WebShutterService instance = WebShutterService._();

  Timer? _pollTimer;
  static const _pollInterval = Duration(milliseconds: 200);

  final ValueNotifier<WebShutterState?> state = ValueNotifier<WebShutterState?>(null);

  bool get isRunning => _pollTimer?.isActive ?? false;

  int _pollCount = 0;

  void startPolling() {
    if (!WebShutterBridge.isSupported) return;
    _pollTimer?.cancel();
    _pollCount = 0;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      try {
        final jsonStr = WebShutterBridge.getShutterStateJson();
        final map = json.decode(jsonStr) as Map<String, dynamic>;
        state.value = WebShutterState.fromJson(map);
        _pollCount++;
        final ws = state.value;
        if (ws != null && _pollCount % 5 == 0) {
          final reason = ws.reason;
          final fc = ws.debug['faceCount'] as int? ?? 0;
          debugPrint(
              '[WebShutterService] poll: face=$fc reason=${reason.isEmpty ? "OK" : reason} stable=${ws.stableCount}/${ws.stableFramesRequired}');
        }
      } catch (e) {
        debugPrint('[WebShutterService] poll error: $e');
      }
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    state.value = null;
  }
}
