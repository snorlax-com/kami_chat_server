import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kami_face_oracle/services/developer_reply_notify_service.dart';

/// バックグラウンド時の開発者返信ポーリング（既読にしない専用サービスへ委譲）。
class DeveloperReplyNotificationWatchdog {
  DeveloperReplyNotificationWatchdog._();

  static final DeveloperReplyNotificationWatchdog instance =
      DeveloperReplyNotificationWatchdog._();

  Timer? _timer;

  void onLifecycleChange(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _stop();
      unawaited(DeveloperReplyNotifyService.pollAndNotify());
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(DeveloperReplyNotifyService.pollAndNotify());
    });
    unawaited(DeveloperReplyNotifyService.pollAndNotify());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> checkNow() => DeveloperReplyNotifyService.pollAndNotify();
}
