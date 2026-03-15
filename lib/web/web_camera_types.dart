/// Web カメラのエラー種別（getUserMedia 等の失敗理由）
enum WebCameraError {
  /// HTTP 等で開いており secure context でない
  notSecureContext,

  /// ユーザーが権限を拒否
  permissionDenied,

  /// カメラが見つからない
  notFound,

  /// カメラが他で使用中などで読み取れない
  notReadable,

  /// 制約を満たすデバイスがない
  overconstrained,

  /// その他
  unknown,
}

extension WebCameraErrorExtension on WebCameraError {
  String get message {
    switch (this) {
      case WebCameraError.notSecureContext:
        return 'HTTPSで開いてください。httpではカメラが使えません。';
      case WebCameraError.permissionDenied:
        return 'カメラの使用が許可されていません。';
      case WebCameraError.notFound:
        return 'フロントカメラが見つかりません。';
      case WebCameraError.notReadable:
        return 'カメラは他のアプリで使用中の可能性があります。';
      case WebCameraError.overconstrained:
        return 'カメラの制約を満たせません。';
      case WebCameraError.unknown:
        return 'カメラの起動に失敗しました。';
    }
  }
}
