import 'package:in_app_purchase/in_app_purchase.dart';

/// Play Billing / in_app_purchase エラーをユーザー向けメッセージに変換。
class PlayBillingErrorMapper {
  PlayBillingErrorMapper._();

  static String userMessage(Object? error, {String? productId}) {
    final code = _errorCode(error);
    final detail = error?.toString() ?? '';
    final prefix = productId != null ? '（$productId）' : '';

    switch (code) {
      case 'userCanceled':
      case 'USER_CANCELED':
        return '購入をキャンセルしました$prefix';
      case 'itemUnavailable':
      case 'ITEM_UNAVAILABLE':
      case 'itemNotOwned':
      case 'ITEM_NOT_OWNED':
        return '商品が見つかりません$prefix。Play Console の商品 ID と内部テストの反映を確認してください。';
      case 'serviceUnavailable':
      case 'SERVICE_UNAVAILABLE':
      case 'serviceDisconnected':
      case 'SERVICE_DISCONNECTED':
        return 'Google Play 課金サービスに接続できません。Play ストアアプリを開き、再試行してください。';
      case 'networkError':
      case 'NETWORK_ERROR':
        return 'ネットワークエラーです。通信環境を確認して再試行してください。';
      case 'billingUnavailable':
      case 'BILLING_UNAVAILABLE':
        return 'この端末では Google Play 課金が利用できません。';
      case 'developerError':
      case 'DEVELOPER_ERROR':
        return 'アプリの課金設定に問題があります。開発者へお問い合わせください。';
      default:
        if (detail.contains('not licensed') || detail.contains('not installed')) {
          return 'Play ストアからアプリをインストールし、内部テストのテスターアカウントでログインしてください。';
        }
        if (detail.contains('ITEM_NOT_FOUND') || detail.contains('itemNotFound')) {
          return '商品 ID が Play Console に未登録、または反映待ちです$prefix。';
        }
        return '購入に失敗しました$prefix${detail.isNotEmpty ? '\n$detail' : ''}';
    }
  }

  static String? _errorCode(Object? error) {
    if (error is IAPError) {
      return error.code;
    }
    if (error is PurchaseDetails) {
      return error.error?.code;
    }
    final text = error.toString();
    for (final c in const [
      'USER_CANCELED',
      'ITEM_NOT_FOUND',
      'SERVICE_DISCONNECTED',
      'NETWORK_ERROR',
      'BILLING_UNAVAILABLE',
    ]) {
      if (text.contains(c)) return c;
    }
    return null;
  }
}
