import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kami_face_oracle/services/auraface_auth_service.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/notification_permission_prompt.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';
import 'package:kami_face_oracle/ui/pages/subscription_cancellation_guide_page.dart';
import 'package:kami_face_oracle/ui/widgets/auraface_auth_sheet.dart';

/// ホームから開くアカウント設定（ログイン / ログアウト / 通知）
class HomeAccountSettingsPage extends StatefulWidget {
  const HomeAccountSettingsPage({super.key});

  @override
  State<HomeAccountSettingsPage> createState() => _HomeAccountSettingsPageState();
}

class _HomeAccountSettingsPageState extends State<HomeAccountSettingsPage>
    with WidgetsBindingObserver {
  NotificationPermissionStatus? _notifyStatus;
  bool _notifyLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint(
      '[Settings] HomeAccountSettingsPage init '
      'android=${!kIsWeb && Platform.isAndroid}',
    );
    _loadNotificationStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PushNotificationService.instance.ensureLocalReady();
      if (!mounted) return;
      await NotificationPermissionPrompt.maybeShow(context);
      await _loadNotificationStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadNotificationStatus();
    }
  }

  void _openCancellationGuide() {
    debugPrint('[Settings] open 解約手順について');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SubscriptionCancellationGuidePage(),
      ),
    );
  }

  /// Google Play 解約手順（Android のみ・サブスク読込状態に依存しない）。
  Widget _cancellationGuideTile(BuildContext context) {
    if (kIsWeb || !Platform.isAndroid) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.help_outline, color: Color(0xFF8B5CF6)),
        title: const Text('解約手順について'),
        subtitle: const Text(
          'Google Play での定期購入の解約方法',
          style: TextStyle(fontSize: 13),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _openCancellationGuide,
      ),
    );
  }

  Future<void> _loadNotificationStatus() async {
    setState(() => _notifyLoading = true);
    final s = await PushNotificationService.instance.getPermissionStatus();
    if (mounted) {
      setState(() {
        _notifyStatus = s;
        _notifyLoading = false;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    final ok = await PushNotificationService.instance.ensureNotificationPermission();
    if (!mounted) return;
    if (ok) {
      await PushNotificationService.instance.syncTokenNow();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('通知が許可されました。創設者（占い師）からの返信をお知らせします。')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知が許可されていません。下の「システム設定を開く」からオンにできます。'),
        ),
      );
    }
    await _loadNotificationStatus();
  }

  Future<void> _openLoginSheet(BuildContext context) async {
    if (!CloudService.isFirebaseAppReady) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Firebase が未設定のためログインできません。'),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1F2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: AurafaceAuthSheet(
          title: 'ログイン',
          subtitle: 'Google でサインインすると、診断の保存や相談機能で本人確認に使えます。',
          onAuthenticated: (user) {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  user.email != null && user.email!.isNotEmpty
                      ? 'ログインしました: ${user.email}'
                      : 'ログインしました',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('アカウントからログアウトし、匿名セッションに戻ります。よろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    await AurafaceAuthService.signOutFromAccount();
    final u = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    if (u != null) {
      await prefs.setString('user_id', u.uid);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ログアウトしました')),
    );
  }

  Widget _notificationSection(BuildContext context) {
    final status = _notifyStatus;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  status?.granted == true ? Icons.notifications_active : Icons.notifications_off_outlined,
                  color: status?.granted == true ? const Color(0xFF8B5CF6) : Colors.orangeAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'プッシュ通知',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '創設者（占い師）から占い相談への返信があったとき、お知らせします。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
            ),
            const SizedBox(height: 12),
            if (_notifyLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ))
            else
              Text(
                '状態: ${status?.label ?? "—"}',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            const SizedBox(height: 12),
            if (status != null && !status.granted && status.canRequestInApp)
              FilledButton.icon(
                onPressed: _requestNotificationPermission,
                icon: const Icon(Icons.notifications),
                label: const Text('通知を許可する'),
              ),
            if (status != null && !status.granted && status.needsSystemSettings)
              FilledButton.icon(
                onPressed: () async {
                  await PushNotificationService.instance.openSystemSettings();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('設定で AuraFace の「通知」をオンにしてから、戻って「状態を再確認」を押してください。'),
                    ),
                  );
                },
                icon: const Icon(Icons.settings),
                label: const Text('設定で通知をオンにする'),
              ),
            if (status != null && !status.granted && !status.needsSystemSettings) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await PushNotificationService.instance.openSystemSettings();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('設定アプリで「通知」をオンにしてください。戻ったら画面を更新します。')),
                  );
                },
                icon: const Icon(Icons.settings),
                label: const Text('システム設定を開く'),
              ),
            ],
            if (status?.granted == true) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  await PushNotificationService.instance.openSystemSettings();
                },
                icon: const Icon(Icons.settings_outlined),
                label: const Text('通知の詳細設定を開く'),
              ),
            ],
            TextButton(
              onPressed: _loadNotificationStatus,
              child: const Text('状態を再確認'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        elevation: 0,
      ),
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          final u = snapshot.data ?? FirebaseAuth.instance.currentUser;
          final linked = u != null && !u.isAnonymous;
          final email = u?.email;
          final label = !linked
              ? '現在は匿名で利用中です。ログインするとアカウントに紐づけられます。'
              : (email != null && email.isNotEmpty
                  ? 'ログイン中: $email'
                  : 'ログイン中（${u.uid.substring(0, 8)}…）');

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _notificationSection(context),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: linked
                    ? null
                    : () => _openLoginSheet(context),
                icon: const Icon(Icons.login),
                label: const Text('ログイン'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: linked
                    ? () => _confirmLogout(context)
                    : null,
                icon: const Icon(Icons.logout),
                label: const Text('ログアウト'),
              ),
              const SizedBox(height: 12),
              _cancellationGuideTile(context),
              if (!CloudService.isFirebaseAppReady) ...[
                const SizedBox(height: 24),
                Text(
                  'Firebase が初期化されていないため、ログイン・プッシュ通知は利用できません。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.orangeAccent,
                      ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
