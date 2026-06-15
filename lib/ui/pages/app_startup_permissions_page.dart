import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/bootstrap/deferred_startup.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/core/permission_service.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// オープニング動画の直後: チュートリアル前にカメラ・通知の許可を案内する。
class AppStartupPermissionsPage extends StatefulWidget {
  const AppStartupPermissionsPage({super.key, required this.next});

  static const _kIntroShown = 'startup_permissions_intro_shown_v1';

  final Widget next;

  @override
  State<AppStartupPermissionsPage> createState() => _AppStartupPermissionsPageState();
}

class _AppStartupPermissionsPageState extends State<AppStartupPermissionsPage> {
  bool _checking = true;
  bool _requesting = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (E2E.isEnabled || kIsWeb) {
      await _finishAndGoNext(skipped: true);
      return;
    }

    await DeferredStartup.awaitReady(timeout: const Duration(seconds: 12));
    if (!mounted) return;

    final introShown = await _isIntroShown();
    final needs = await _needsPermissionFlow();
    if (introShown && !needs) {
      debugPrint('[StartupPermissions] skip: intro shown and permissions ok');
      await _finishAndGoNext(skipped: true);
      return;
    }

    if (mounted) setState(() => _checking = false);
  }

  static Future<bool> _isIntroShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppStartupPermissionsPage._kIntroShown) ?? false;
  }

  static Future<void> _markIntroShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppStartupPermissionsPage._kIntroShown, true);
  }

  static Future<bool> _needsPermissionFlow() async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final camera = await PermissionService.instance.cameraStatus;
    if (camera != PermissionStatus.granted) return true;

    await PushNotificationService.instance.ensureLocalReady();
    final notifications = await PushNotificationService.instance.areSystemNotificationsEnabled();
    return !notifications;
  }

  Future<void> _finishAndGoNext({required bool skipped}) async {
    if (_navigating) return;
    _navigating = true;
    await _markIntroShown();
    debugPrint('[StartupPermissions] continue skipped=$skipped');
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => widget.next),
    );
  }

  Future<void> _requestCamera() async {
    final status = await PermissionService.instance.cameraStatus;
    if (status == PermissionStatus.granted) return;
    debugPrint('[StartupPermissions] request camera');
    await PermissionService.instance.requestCamera();
  }

  Future<void> _requestNotification() async {
    await PushNotificationService.instance.ensureLocalReady();
    final enabled = await PushNotificationService.instance.areSystemNotificationsEnabled();
    if (enabled) return;

    if (!mounted) return;
    final sdk = await PushNotificationService.instance.androidSdkInt();
    final isLegacyAndroid = Platform.isAndroid && sdk != null && sdk < 33;

    if (isLegacyAndroid) {
      final goSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('通知の許可'),
          content: const Text(
            '創設者（占い師）からの占い相談への返信をお知らせするには、'
            '端末の設定で AuraFace の「通知」をオンにしてください。\n\n'
            '「設定を開く」をタップして通知を有効にしたあと、このアプリに戻ってください。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('あとで'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('設定を開く'),
            ),
          ],
        ),
      );
      if (goSettings == true) {
        debugPrint('[StartupPermissions] open notification settings (legacy Android)');
        await PushNotificationService.instance.openSystemSettings();
      }
      return;
    }

    debugPrint('[StartupPermissions] request notification');
    await PushNotificationService.instance.ensureNotificationPermission();
  }

  Future<void> _requestAndContinue() async {
    if (_requesting || _navigating) return;
    setState(() => _requesting = true);
    try {
      await _requestCamera();
      if (!mounted) return;
      await _requestNotification();
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
    await _finishAndGoNext(skipped: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text(
                'アプリの利用に必要な許可',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '性格診断チュートリアルと占い相談の返信通知のために、次の許可が必要です。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), height: 1.5),
              ),
              const SizedBox(height: 28),
              const _PermissionCard(
                icon: Icons.photo_camera_outlined,
                title: 'カメラ',
                body: '顔写真から性格診断を行うために使用します。撮影した写真は診断にのみ使います。',
              ),
              const SizedBox(height: 16),
              const _PermissionCard(
                icon: Icons.notifications_outlined,
                title: '通知',
                body: '創設者（占い師）からの占い相談への返信をお知らせするために使用します。',
              ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: (_requesting || _navigating)
                      ? null
                      : () => unawaited(_requestAndContinue()),
                  child: _requesting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('許可して続ける', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: (_requesting || _navigating)
                      ? null
                      : () => unawaited(_finishAndGoNext(skipped: true)),
                  child: const Text('あとで'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFC084FC), size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.78), height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
