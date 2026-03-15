/// 画像取得の抽象化（Web=HTML file input / Mobile=image_picker+camera+MethodChannel）
/// 既存フローは bytes で統一し、path 依存を排除する。

class PickedImage {
  PickedImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final List<int> bytes;
  final String filename;
  final String mimeType;
}

abstract class ImageInput {
  /// preferCamera=true の場合は撮影を優先（Webでは capture 属性を付与）
  Future<PickedImage?> pick({required bool preferCamera});

  /// 自動テスト/外部ストレージ/Intent 由来の画像。Webでは null（未対応）
  Future<PickedImage?> pickFromExternalPathOrIntentIfAvailable();
}
