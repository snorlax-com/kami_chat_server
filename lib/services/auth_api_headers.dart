import 'package:kami_face_oracle/services/secure_auth_token_store.dart';

/// 認証必須 API 用の Authorization ヘッダー。
class AuthApiHeaders {
  AuthApiHeaders._();

  static Future<Map<String, String>> authorizationJson() async {
    final token = await SecureAuthTokenStore.readToken();
    if (token == null || token.isEmpty) {
      return const {};
    }
    return {'Authorization': 'Bearer $token'};
  }
}
