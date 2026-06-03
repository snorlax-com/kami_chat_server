import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';

/// 初回ホーム表示時などに、通知がオフなら案内ダイアログを出す。
class NotificationPermissionPrompt {
  NotificationPermissionPrompt._();

  static const _prefsKeyLastPromptMs = 'notification_prompt_last_ms_v1';

  /// integration_test では表示しない。
  static bool suppressForIntegrationTest = false;

  /// 通知がオフのとき、案内ダイアログを表示（24時間に1回まで）。
  static Future<void> maybeShow(BuildContext context) async {
    if (suppressForIntegrationTest) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    await PushNotificationService.instance.ensureLocalReady();

    final enabled = await PushNotificationService.instance.areSystemNotificationsEnabled();
    if (enabled) return;

    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_prefsKeyLastPromptMs) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastMs < const Duration(hours: 24).inMilliseconds) return;

    if (!context.mounted) return;

    await prefs.setInt(_prefsKeyLastPromptMs, now);

    final sdk = await PushNotificationService.instance.androidSdkInt();
    final isLegacyAndroid = Platform.isAndroid && sdk != null && sdk < 33;

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('通知の許可'),
        content: Text(
          isLegacyAndroid
              ? '開発者からの占い相談への返信をお知らせするには、端末の設定で AuraFace の「通知」をオンにしてください。\n\n'
                  '（この端末では設定アプリから通知を有効にする必要があります）'
              : '開発者からの占い相談への返信をお知らせするため、通知の許可が必要です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('あとで'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (isLegacyAndroid) {
                await PushNotificationService.instance.openSystemSettings();
              } else {
                await PushNotificationService.instance.ensureNotificationPermission();
              }
            },
            child: Text(isLegacyAndroid ? '設定を開く' : '許可する'),
          ),
        ],
      ),
    );
  }
}
