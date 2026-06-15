import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Firebase ID トークンを暗号化ストレージに保持（平文 SharedPreferences は使わない）。
class SecureAuthTokenStore {
  SecureAuthTokenStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _keyJwt = 'jwt_token';

  static Future<String?> readToken() async {
    final cached = await _storage.read(key: _keyJwt);
    if (cached != null && cached.isNotEmpty) return cached;
    return _refreshFromFirebase();
  }

  static Future<String?> _refreshFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) return null;
      await _storage.write(key: _keyJwt, value: token);
      return token;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SecureAuthTokenStore] getIdToken failed: $e\n$st');
      }
      return null;
    }
  }

  static Future<void> clear() async {
    await _storage.delete(key: _keyJwt);
  }

  static Future<void> onSignedIn() async {
    await _refreshFromFirebase();
  }
}
