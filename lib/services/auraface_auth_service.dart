import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:kami_face_oracle/config/google_web_client_id.dart';

/// Google / Apple / メール（Firebase Email+Password）
///
/// 起動時の**匿名ログイン**と Google 資格情報がぶつかると `invalid-credential` 等になりやすいため、
/// Google / Apple / メールのいずれかでログインする直前に匿名をサインアウトし、
/// **失敗時（キャンセル含む）のみ**匿名へ戻す。
class AurafaceAuthService {
  AurafaceAuthService._();

  /// `adb logcat | grep -i AurafaceAuth` で追える（トークンは出さない）。
  static void _logAuth(String event, [String? detail]) {
    if (detail == null || detail.isEmpty) {
      debugPrint('[AurafaceAuth] $event');
    } else {
      debugPrint('[AurafaceAuth] $event: $detail');
    }
  }

  static bool _googleSignInInitialized = false;

  /// 任意: `--dart-define=GOOGLE_WEB_CLIENT_ID=xxx.apps.googleusercontent.com`
  static const String _webClientIdFromEnv = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static String get _resolvedWebClientId {
    final fromEnv = _webClientIdFromEnv.trim();
    if (fromEnv.isNotEmpty) return fromEnv;
    return kGoogleOAuth2WebClientId.trim();
  }

  static Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    final w = _resolvedWebClientId;
    await GoogleSignIn.instance.initialize(
      serverClientId: w.isNotEmpty ? w : null,
    );
    _googleSignInInitialized = true;
  }

  static Future<void> _restoreAnonymousIfNeeded(bool mustRestore) async {
    if (!mustRestore) return;
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (_) {}
  }

  /// Identity Toolkit の `GetAuthDomainTask` が CONFIGURATION_NOT_FOUND を返すとき true。
  /// （ログ例: Error getting project config. Failed with CONFIGURATION_NOT_FOUND 400）
  static bool _isAuthConfigurationNotFound(FirebaseAuthException e) {
    final blob = '${e.code} ${e.message ?? ''}'.toUpperCase();
    return blob.contains('CONFIGURATION_NOT_FOUND');
  }

  /// CredentialManager / serverClientId 周りで失敗したときの代替（ブラウザ系フロー）。
  static Future<UserCredential> _signInWithGoogleFirebaseProvider() async {
    final provider = GoogleAuthProvider();
    provider.addScope('email');
    provider.setCustomParameters(const {'prompt': 'select_account'});
    try {
      return await FirebaseAuth.instance.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (_isAuthConfigurationNotFound(e)) {
        _logAuth(
          'signInWithProvider',
          'CONFIGURATION_NOT_FOUND → Firebase Console で Authentication を有効化してください',
        );
        throw FirebaseAuthException(
          code: 'configuration-not-found',
          message:
              'Firebase の「ホスト用 Auth 設定」が見つかりません（CONFIGURATION_NOT_FOUND）。\n\n'
              '次を順に確認してください:\n'
              '1) Firebase Console → Authentication を開き、「使ってみる」/「Get Started」を一度実行する\n'
              '2) 同じ画面の「Sign-in method」で「Google」を有効にする\n'
              '3) プロジェクトに Web アプリが無い場合は「アプリを追加」→ Web で追加する（auth ドメインの生成に必要なことがあります）\n'
              '4) Google Cloud Console → API とサービス で「Identity Toolkit API」が有効か確認する\n\n'
              '※ Google アカウント選択（Credential Manager）だけではログインできず、'
              '上記が済むまでブラウザ経由の Google ログインも失敗します。',
        );
      }
      rethrow;
    }
  }

  static bool _googleSignInFailureShouldTryProvider(GoogleSignInException e) {
    return e.code == GoogleSignInExceptionCode.clientConfigurationError ||
        e.code == GoogleSignInExceptionCode.providerConfigurationError;
  }

  /// `signInWithProvider` 後に「ユーザーがブラウザ／シートを閉じた」と判断できるコードだけ true。
  static bool _googleProviderSignInLooksLikeUserCancelled(FirebaseAuthException e) {
    switch (e.code) {
      case 'web-context-cancelled':
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'aborted-by-user':
        return true;
      default:
        return false;
    }
  }

  static Future<AuthCredential> _googleCredentialFromAccount(
    GoogleSignInAccount account,
  ) async {
    var idToken = account.authentication.idToken;
    String? accessToken;

    try {
      final silent = await account.authorizationClient.authorizationForScopes(
        const ['email', 'profile', 'openid'],
      );
      accessToken = silent?.accessToken;
    } catch (_) {}

    if (idToken == null || idToken.isEmpty) {
      try {
        final authz = await account.authorizationClient.authorizeScopes(
          const ['email', 'profile', 'openid'],
        );
        accessToken = accessToken ?? authz.accessToken;
        idToken = account.authentication.idToken ?? idToken;
      } catch (_) {}
    }

    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message:
            'Google に接続できません（ID トークンなし）。google-services.json の oauth_client が空のことが多いです。'
            'Firebase で Android の SHA-1 を登録して JSON を取り直すか、'
            'lib/config/google_web_client_id.dart に Web クライアント ID を設定してください。',
      );
    }

    return GoogleAuthProvider.credential(
      accessToken: accessToken,
      idToken: idToken,
    );
  }

  static Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      return FirebaseAuth.instance.signInWithProvider(provider);
    }

    // android/app/google-services.json の oauth_client が空などで CredentialManager + serverClientId が失敗する場合がある。
    // Web クライアントIDが未設定なら、まず FirebaseAuth の provider フロー（ブラウザ系）を試す。
    if (_resolvedWebClientId.isEmpty) {
      _logAuth('signInWithGoogle', 'webClientId empty → signInWithProvider only');
      return _signInWithGoogleFirebaseProvider();
    }

    await _ensureGoogleSignInInitialized();

    final hadAnonymous =
        FirebaseAuth.instance.currentUser?.isAnonymous ?? false;
    var mustRestoreAnonymous = false;

    try {
      _logAuth(
        'signInWithGoogle_start',
        'hadAnonymous=$hadAnonymous platform=$defaultTargetPlatform',
      );
      if (hadAnonymous) {
        await FirebaseAuth.instance.signOut();
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
        mustRestoreAnonymous = true;
      }

      const authenticateTimeout = Duration(seconds: 45);

      GoogleSignInAccount account;
      try {
        account = await GoogleSignIn.instance
            .authenticate(scopeHint: const ['email', 'profile'])
            .timeout(
              authenticateTimeout,
              onTimeout: () => throw TimeoutException(
                'GoogleSignIn.authenticate',
                authenticateTimeout,
              ),
            );
        _logAuth('GoogleSignIn.authenticate', 'ok');
      } on TimeoutException catch (_) {
        _logAuth('GoogleSignIn.authenticate', 'timeout → signInWithProvider');
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
        final result = await _signInWithGoogleFirebaseProvider();
        mustRestoreAnonymous = false;
        return result;
      } on GoogleSignInException catch (e) {
        _logAuth(
          'GoogleSignIn.authenticate',
          'GoogleSignInException ${e.code} ${e.description ?? ""}',
        );
        // canceled も Credential Manager や OEM により誤検知されやすい。
        // interrupted / uiUnavailable と同様、まず Firebase の provider（Custom Tabs）を試す。
        if (e.code == GoogleSignInExceptionCode.canceled ||
            e.code == GoogleSignInExceptionCode.interrupted ||
            e.code == GoogleSignInExceptionCode.uiUnavailable) {
          try {
            await GoogleSignIn.instance.signOut();
          } catch (_) {}
          try {
            final result = await _signInWithGoogleFirebaseProvider();
            mustRestoreAnonymous = false;
            return result;
          } on FirebaseAuthException catch (fe) {
            _logAuth(
              'signInWithProvider_after_CM',
              'FirebaseAuthException ${fe.code} ${fe.message ?? ""}',
            );
            if (_googleProviderSignInLooksLikeUserCancelled(fe)) {
              throw FirebaseAuthException(
                code: 'aborted-by-user',
                message: 'ログインがキャンセルされました',
              );
            }
            // Custom Tabs が internal-error を返す端末では、再スローすると
            // Credential 側のヒントが出ず終了するため、明示メッセージに寄せる。
            if (fe.code == 'internal-error') {
              throw FirebaseAuthException(
                code: 'internal-error',
                message: fe.message ??
                    'Google ログイン（ブラウザ）で内部エラーが発生しました。'
                    'Firebase で Google を有効にし、OAuth 同意画面のテストユーザーを確認してください。',
              );
            }
            rethrow;
          } catch (fallbackErr) {
            throw FirebaseAuthException(
              code: 'google-sign-in-failed',
              message:
                  'Google ログインが完了しませんでした（${e.code}）。\n'
                  'しばらくしてから再度お試しください。\n'
                  'OAuth 同意画面が「外部」の場合は、テストユーザーにこの Google アカウントを追加してください。\n\n'
                  '(${e.description ?? fallbackErr.toString()})',
            );
          }
        }
        if (_googleSignInFailureShouldTryProvider(e)) {
          // serverClientId / google-services.json の oauth_client が空等で CredentialManager が失敗する端末向け。
          // まず FirebaseAuth の provider フロー（ブラウザ系）を試す。
          try {
            await GoogleSignIn.instance.signOut();
          } catch (_) {}
          final result = await _signInWithGoogleFirebaseProvider();
          mustRestoreAnonymous = false;
          return result;
        }
        throw FirebaseAuthException(
          code: 'google-sign-in-failed',
          message:
              '${e.description ?? e.toString()}\n\n（設定ヒント）Android の場合は次を確認してください:\n'
              '- Firebase Console で Android の SHA-1 を登録し、android/app/google-services.json を再ダウンロード\n'
              '- lib/config/google_web_client_id.dart の kGoogleOAuth2WebClientId（正）と google-services.json の client_type 3 を同一にする\n'
              '- 必要なら --dart-define=GOOGLE_WEB_CLIENT_ID=... または android/local.properties の googleWebClientId で上書き',
        );
      }

      UserCredential result;
      try {
        final credential = await _googleCredentialFromAccount(account);
        result =
            await FirebaseAuth.instance.signInWithCredential(credential);
        _logAuth('signInWithCredential', 'ok');
      } on FirebaseAuthException catch (e) {
        _logAuth(
          'signInWithCredential',
          'FirebaseAuthException ${e.code} ${e.message ?? ""}',
        );
        final retryWithProvider = e.code == 'missing-id-token' ||
            e.code == 'internal-error' ||
            e.code == 'invalid-credential';
        if (!retryWithProvider) rethrow;
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
        try {
          result = await _signInWithGoogleFirebaseProvider();
          _logAuth('signInWithProvider_after_credential', 'ok');
        } on FirebaseAuthException catch (pe) {
          _logAuth(
            'signInWithProvider_after_credential',
            'FirebaseAuthException ${pe.code} ${pe.message ?? ""}',
          );
          final a = e.message?.trim();
          final b = pe.message?.trim();
          final combined = (a != null &&
                  a.isNotEmpty &&
                  b != null &&
                  b.isNotEmpty)
              ? '① IDトークン＋Credential: $a\n② ブラウザ（signInWithProvider）: $b'
              : (b?.isNotEmpty == true)
                  ? b!
                  : (a?.isNotEmpty == true)
                      ? a!
                      : '${e.code} → ${pe.code}';
          throw FirebaseAuthException(
            code: pe.code,
            message: combined,
          );
        }
      }
      mustRestoreAnonymous = false;
      return result;
    } finally {
      await _restoreAnonymousIfNeeded(mustRestoreAnonymous);
    }
  }

  static bool get appleSignInAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<UserCredential> signInWithApple() async {
    if (!appleSignInAvailable) {
      throw UnsupportedError('Appleログインは iOS / macOS のみ対応です');
    }

    final hadAnonymous =
        FirebaseAuth.instance.currentUser?.isAnonymous ?? false;
    var mustRestoreAnonymous = false;

    try {
      if (hadAnonymous) {
        await FirebaseAuth.instance.signOut();
        mustRestoreAnonymous = true;
      }

      final apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final idToken = apple.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Apple サインイン: identityToken が取得できませんでした');
      }
      final oauth = OAuthProvider('apple.com').credential(idToken: idToken);
      final result = await FirebaseAuth.instance.signInWithCredential(oauth);
      mustRestoreAnonymous = false;
      return result;
    } finally {
      await _restoreAnonymousIfNeeded(mustRestoreAnonymous);
    }
  }

  static Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final hadAnonymous =
        FirebaseAuth.instance.currentUser?.isAnonymous ?? false;
    var mustRestoreAnonymous = false;
    try {
      if (hadAnonymous) {
        await FirebaseAuth.instance.signOut();
        mustRestoreAnonymous = true;
      }
      final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      mustRestoreAnonymous = false;
      return result;
    } finally {
      await _restoreAnonymousIfNeeded(mustRestoreAnonymous);
    }
  }

  static Future<UserCredential> registerWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final hadAnonymous =
        FirebaseAuth.instance.currentUser?.isAnonymous ?? false;
    var mustRestoreAnonymous = false;
    try {
      if (hadAnonymous) {
        await FirebaseAuth.instance.signOut();
        mustRestoreAnonymous = true;
      }
      final result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      mustRestoreAnonymous = false;
      return result;
    } finally {
      await _restoreAnonymousIfNeeded(mustRestoreAnonymous);
    }
  }

  /// Google / Apple / メールでログインしたセッションを終了し、可能なら匿名に戻す。
  static Future<void> signOutFromAccount() async {
    _logAuth('signOutFromAccount', 'start');
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      _logAuth('signOutFromAccount', 'Firebase signOut: $e');
    }
    if (!kIsWeb) {
      try {
        await _ensureGoogleSignInInitialized();
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        _logAuth('signOutFromAccount', 'GoogleSignIn: $e');
      }
    }
    try {
      await FirebaseAuth.instance.signInAnonymously();
      _logAuth('signOutFromAccount', 'anonymous restored');
    } catch (e) {
      _logAuth('signOutFromAccount', 'anonymous restore failed: $e');
    }
  }
}
