import 'package:flutter/foundation.dart' show kIsWeb;

/// 診断処理で発生した例外を、ユーザー向けの短いメッセージに変換する。
/// 技術的な例外メッセージをそのまま表示しないようにする。
String getDiagnosisErrorMessage(Object e) {
  final s = e.toString();
  if (s.contains('TimeoutException') || s.contains('timed out') || s.contains('タイムアウト')) {
    return 'サーバーが応答しません。しばらく待ってからもう一度お試しください。';
  }
  if (s.contains('CONSENT_REQUIRED') || s.contains('403')) {
    return '同意が未登録です。最初に生体データの同意で「同意する」をタップしてください。';
  }
  if (s.contains('Failed to load') ||
      s.contains('CORS') ||
      s.contains('XMLHttpRequest') ||
      s.contains('Connection refused') ||
      s.contains('Connection reset') ||
      s.contains('SocketException') ||
      s.contains('NetworkException')) {
    return 'サーバーに接続できません。ネットワークを確認して、もう一度お試しください。';
  }
  if (s.contains('STOP_HERE_SERVER_INFERENCE_REQUIRED')) {
    // 内包されている実際の原因を簡潔に
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'サーバーが応答しません。しばらく待ってからもう一度お試しください。';
    }
    if (s.contains('CONSENT_REQUIRED') || s.contains('403')) {
      return '同意が未登録です。最初に生体データの同意で「同意する」をタップしてください。';
    }
    if (s.contains('画像が存在しません')) {
      return '画像の読み込みに失敗しました。もう一度撮影してください。';
    }
    return '診断処理に失敗しました。ネットワークを確認して、もう一度お試しください。';
  }
  if (kIsWeb) {
    return '診断処理に失敗しました。ネットワークを確認して、もう一度お試しください。';
  }
  return '診断処理に失敗しました。もう一度お試しください。';
}
