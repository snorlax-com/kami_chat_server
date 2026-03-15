import 'package:kami_face_oracle/web/web_camera_types.dart';

/// 非 Web 用スタブ。Web 以外ではインスタンス化しない（isSupported で分岐）。
class WebCameraController {
  WebCameraController();

  static bool get isSupported => false;

  Future<void> start(String videoElementId) async {
    throw UnsupportedError('WebCameraController is only supported on Web.');
  }

  void stop() {}

  Future<List<int>> captureJpegBytes({double quality = 0.92}) async {
    throw UnsupportedError('WebCameraController is only supported on Web.');
  }

  bool get isReady => false;
  WebCameraError? get lastError => null;
}
