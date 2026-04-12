import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 相談メールブリッジ用 userId。Firebase の実ユーザー（匿名以外）を必須にする。
class ConsultationIdentity {
  ConsultationIdentity._();

  /// 送信可能なら [User]、匿名・未ログインなら SnackBar のみで null。
  static Future<User?> requireFirebaseUserForConsultation(BuildContext context) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '相談を送るには、まず性格診断結果の画面で Google・Apple・メールのいずれかでログインしてください。',
            ),
            duration: Duration(seconds: 8),
          ),
        );
      }
      return null;
    }
    if (u.isAnonymous) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '相談を送るには認証が必要です。ホームの「保存された性格診断を開く」またはチュートリアル診断後の画面からログインしてください。',
            ),
            duration: Duration(seconds: 10),
          ),
        );
      }
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', u.uid);
    return u;
  }

  /// ブリッジ API 用 ID（認証済みなら Firebase UID、それ以外は従来の prefs フォールバック）
  static Future<String> bridgeUserIdOrLegacy() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u != null && !u.isAnonymous) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', u.uid);
      return u.uid;
    }
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('user_id');
    if (id == null || id.isEmpty) {
      id = 'user_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('user_id', id);
    }
    return id;
  }
}
