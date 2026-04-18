import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kami_face_oracle/services/auraface_auth_service.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/ui/widgets/auraface_auth_sheet.dart';

/// ホームから開くアカウント設定（ログイン / ログアウト）
class HomeAccountSettingsPage extends StatelessWidget {
  const HomeAccountSettingsPage({super.key});

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
          subtitle: 'Google・Apple・メールのいずれかでサインインすると、診断の保存や相談機能で本人確認に使えます。',
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
              if (!CloudService.isFirebaseAppReady) ...[
                const SizedBox(height: 24),
                Text(
                  'Firebase が初期化されていないため、ログイン機能は利用できません。',
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
