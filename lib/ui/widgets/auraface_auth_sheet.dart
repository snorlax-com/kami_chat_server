import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kami_face_oracle/services/auraface_auth_service.dart';

String _authErrorMessage(FirebaseAuthException e) {
  final msg = (e.message ?? '').toLowerCase();
  final code = e.code.toLowerCase();
  if (code == 'configuration-not-found') {
    return e.message ??
        'Firebase Authentication の初期設定が未完了です（CONFIGURATION_NOT_FOUND）。';
  }
  if (code == 'internal-error' ||
      msg.contains('internal') ||
      msg.contains('configuration_not_found')) {
    if (msg.contains('configuration_not_found') ||
        msg.contains('configuration not found')) {
      return 'Firebase の「ホスト用 Auth 設定」が見つかりません（CONFIGURATION_NOT_FOUND）。\n\n'
          'Firebase Console → Authentication で「使ってみる」を実行し、Google を有効化してください。'
          ' プロジェクトに Web アプリが無い場合は追加してください。\n'
          'Google Cloud で「Identity Toolkit API」が有効かも確認してください。';
    }
    final firebaseDetail = (e.message != null && e.message!.trim().isNotEmpty)
        ? '\n\n--- Firebase からのメッセージ ---\n${e.message}'
        : '';
    return 'Google ログインで内部エラーが発生しました（FirebaseAuth: $code）。\n\n'
        'よくある原因と確認手順:\n'
        '1) Firebase Console → Authentication → Sign-in method で「Google」を有効化\n'
        '2) Firebase Console → プロジェクトの設定 → マイアプリ（Android）で SHA-1 を登録し、'
        'google-services.json を再ダウンロードして置き換え（oauth_client が空のままだと失敗しやすい）\n'
        '3) Google Cloud Console の OAuth 同意画面が「外部」の場合、テストユーザーに自分のGoogleアカウントを追加\n'
        '4) Web クライアントID（…apps.googleusercontent.com）は、Firebase の「Web SDK 設定」と一致させる\n'
        '   （別プロジェクトで作ったクライアントIDだと失敗することがあります）\n'
        '5) Web クライアント ID の正は lib/config/google_web_client_id.dart（必要なら local.properties で上書き）\n'
        '6) 開発時は PC で次を実行するとログが取れます: adb logcat | grep -i AurafaceAuth'
        '$firebaseDetail';
  }
  if (code == 'google-sign-in-failed') {
    return e.message ?? 'Google サインインに失敗しました';
  }
  if (code == 'missing-id-token') {
    return e.message ??
        'Google の設定が不足しています。Firebase で SHA-1 登録後に google-services.json を更新するか、'
        'lib/config/google_web_client_id.dart を確認してください。';
  }
  return e.message ?? e.code;
}

/// チュートリアル診断後の「ログインして詳細を開示」用ボトムシート（ホームの設定からも利用可）
class AurafaceAuthSheet extends StatefulWidget {
  const AurafaceAuthSheet({
    super.key,
    required this.onAuthenticated,
    this.title,
    this.subtitle,
  });

  final void Function(User user) onAuthenticated;
  final String? title;
  final String? subtitle;

  @override
  State<AurafaceAuthSheet> createState() => _AurafaceAuthSheetState();
}

class _AurafaceAuthSheetState extends State<AurafaceAuthSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _wrap(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _authErrorMessage(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _after(UserCredential cred) async {
    final u = cred.user;
    if (u == null) throw StateError('no user');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', u.uid);
    if (!mounted) return;
    widget.onAuthenticated(u);
  }

  Future<void> _google() async {
    await _wrap(() async {
      final c = await AurafaceAuthService.signInWithGoogle();
      await _after(c);
    });
  }

  Future<void> _apple() async {
    await _wrap(() async {
      final c = await AurafaceAuthService.signInWithApple();
      await _after(c);
    });
  }

  Future<void> _showEmailDialog() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('メールアドレスで続ける'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'メールアドレス'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
              ),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: 'パスワード（6文字以上）'),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'login'),
            child: const Text('ログイン'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'register'),
            child: const Text('新規登録'),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) {
      emailCtrl.dispose();
      passCtrl.dispose();
      return;
    }
    await _wrap(() async {
      final UserCredential c;
      if (mode == 'login') {
        c = await AurafaceAuthService.signInWithEmailPassword(
          email: emailCtrl.text,
          password: passCtrl.text,
        );
      } else {
        c = await AurafaceAuthService.registerWithEmailPassword(
          email: emailCtrl.text,
          password: passCtrl.text,
        );
      }
      await _after(c);
    });
    emailCtrl.dispose();
    passCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appleOk = AurafaceAuthService.appleSignInAvailable;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title ?? '診断結果を保存して続きを見る',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.subtitle ??
                  '認証後、詳細な性格診断が開示され、次回も同じ内容を確認できます。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _google,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text('Googleで続ける'),
            ),
            if (appleOk) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _apple,
                icon: const Icon(Icons.apple),
                label: const Text('Appleで続ける'),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _showEmailDialog,
              icon: const Icon(Icons.mail_outline),
              label: const Text('メールアドレスで続ける'),
            ),
            if (_busy) const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }
}
