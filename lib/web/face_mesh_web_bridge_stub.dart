/// スタブ（非 Web 用）。Web では face_mesh_web_bridge_web を利用する。
class FaceMeshResult {
  final bool ok;
  final double yaw;
  final double pitch;
  final double roll;
  final double score;
  final BBox? bbox;

  FaceMeshResult({
    required this.ok,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.score,
    required this.bbox,
  });

  static FaceMeshResult notOk() => FaceMeshResult(
        ok: false,
        yaw: 0,
        pitch: 0,
        roll: 0,
        score: 0,
        bbox: null,
      );
}

class BBox {
  final double minX, minY, maxX, maxY;
  BBox(this.minX, this.minY, this.maxX, this.maxY);

  double get w => (maxX - minX).clamp(0.0, 1.0);
  double get h => (maxY - minY).clamp(0.0, 1.0);
  double get cx => (minX + maxX) / 2.0;
  double get cy => (minY + maxY) / 2.0;
}

class QualitySignalsResult {
  final double brightness;
  final double contrast;
  QualitySignalsResult({required this.brightness, required this.contrast});
}

class FaceMeshWebBridge {
  static bool get isSupported => false;

  static Future<bool> init() async => false;
  static bool start() => false;
  static bool stop() => false;
  static Future<FaceMeshResult> analyzeFrame(String videoElementId) async => FaceMeshResult.notOk();
  static QualitySignalsResult getQualitySignals(String videoElementId) =>
      QualitySignalsResult(brightness: 0, contrast: 0);
  static Future<String?> captureOneFrame(String videoElementId) async => null;
}
