import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  /// CredentialManager / serverClientId 周りで失敗したときの代替（ブラウザ系フロー）。
  static Future<UserCredential> _signInWithGoogleFirebaseProvider() async {
    final provider = GoogleAuthProvider();
    provider.addScope('email');
    provider.setCustomParameters(const {'prompt': 'select_account'});
    return FirebaseAuth.instance.signInWithProvider(provider);
  }

  static bool _googleSignInFailureShouldTryProvider(GoogleSignInException e) {
    return e.code == GoogleSignInExceptionCode.clientConfigurationError ||
        e.code == GoogleSignInExceptionCode.providerConfigurationError;
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

    await _ensureGoogleSignInInitialized();

    final hadAnonymous =
        FirebaseAuth.instance.currentUser?.isAnonymous ?? false;
    var mustRestoreAnonymous = false;

    try {
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
      } on TimeoutException catch (_) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
        final result = await _signInWithGoogleFirebaseProvider();
        mustRestoreAnonymous = false;
        return result;
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled ||
            e.code == GoogleSignInExceptionCode.interrupted) {
          throw FirebaseAuthException(
            code: 'aborted-by-user',
            message: 'ログインがキャンセルされました',
          );
        }
        if (_googleSignInFailureShouldTryProvider(e)) {
          try {
            await GoogleSignIn.instance.signOut();
          } catch (_) {}
          final result = await _signInWithGoogleFirebaseProvider();
          mustRestoreAnonymous = false;
          return result;
        }
        throw FirebaseAuthException(
          code: 'google-sign-in-failed',
          message: e.description ?? e.toString(),
        );
      }

      UserCredential result;
      try {
        final credential = await _googleCredentialFromAccount(account);
        result =
            await FirebaseAuth.instance.signInWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'missing-id-token') rethrow;
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
        result = await _signInWithGoogleFirebaseProvider();
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
}
