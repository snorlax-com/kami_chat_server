// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;

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
  static bool get isSupported {
    try {
      final b = js_util.getProperty(html.window, 'MPFaceMeshBridge');
      return b != null;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> init() async {
    try {
      final b = js_util.getProperty(html.window, 'MPFaceMeshBridge');
      if (b == null) return false;
      final p = js_util.callMethod(b, 'initFaceMesh', []);
      final r = await js_util.promiseToFuture(p);
      return r == true;
    } catch (_) {
      return false;
    }
  }

  static bool start() {
    try {
      final b = js_util.getProperty(html.window, 'MPFaceMeshBridge');
      if (b == null) return false;
      final r = js_util.callMethod(b, 'startFaceMesh', []);
      return r == true;
    } catch (_) {
      return false;
    }
  }

  static bool stop() {
    try {
      final b = js_util.getProperty(html.window, 'MPFaceMeshBridge');
      if (b == null) return false;
      final r = js_util.callMethod(b, 'stopFaceMesh', []);
      return r == true;
    } catch (_) {
      return false;
    }
  }

  /// videoElementId: e.g. 'web_shutter_video'
  static Future<FaceMeshResult> analyzeFrame(String videoElementId) async {
    try {
      final el = html.document.getElementById(videoElementId);
      if (el == null) return FaceMeshResult.notOk();
      final b = js_util.getProperty(html.window, 'MPFaceMeshBridge');
      if (b == null) return FaceMeshResult.notOk();
      final p = js_util.callMethod(b, 'analyzeFrame', [el]);
      final obj = await js_util.promiseToFuture(p);
      if (obj == null) return FaceMeshResult.notOk();
      final ok = js_util.getProperty(obj, 'ok') == true;
      if (!ok) return FaceMeshResult.notOk();

      final yaw = (js_util.getProperty(obj, 'yaw') as num).toDouble();
      final pitch = (js_util.getProperty(obj, 'pitch') as num).toDouble();
      final roll = (js_util.getProperty(obj, 'roll') as num).toDouble();
      final score = (js_util.getProperty(obj, 'score') as num).toDouble();
      final bboxObj = js_util.getProperty(obj, 'bbox');
      BBox? bbox;
      if (bboxObj != null) {
        bbox = BBox(
          (js_util.getProperty(bboxObj, 'minX') as num).toDouble(),
          (js_util.getProperty(bboxObj, 'minY') as num).toDouble(),
          (js_util.getProperty(bboxObj, 'maxX') as num).toDouble(),
          (js_util.getProperty(bboxObj, 'maxY') as num).toDouble(),
        );
      }
      return FaceMeshResult(
        ok: true,
        yaw: yaw,
        pitch: pitch,
        roll: roll,
        score: score,
        bbox: bbox,
      );
    } catch (_) {
      return FaceMeshResult.notOk();
    }
  }

  static QualitySignalsResult getQualitySignals(String videoElementId) {
    try {
      final el = html.document.getElementById(videoElementId);
      if (el == null) return QualitySignalsResult(brightness: 0, contrast: 0);
      final b = js_util.getProperty(html.window, 'MPFaceMeshBridge');
      if (b == null) return QualitySignalsResult(brightness: 0, contrast: 0);
      final obj = js_util.callMethod(b, 'getQualitySignals', [el]);
      if (obj == null) return QualitySignalsResult(brightness: 0, contrast: 0);
      final brightness = (js_util.getProperty(obj, 'brightness') as num?)?.toDouble() ?? 0.0;
      final contrast = (js_util.getProperty(obj, 'contrast') as num?)?.toDouble() ?? 0.0;
      return QualitySignalsResult(brightness: brightness, contrast: contrast);
    } catch (_) {
      return QualitySignalsResult(brightness: 0, contrast: 0);
    }
  }

  static Future<String?> captureOneFrame(String videoElementId) async {
    try {
      final b = js_util.getProperty(html.window, 'MPFaceMeshBridge');
      if (b == null) return null;
      final p = js_util.callMethod(b, 'captureOneFrame', [videoElementId]);
      final r = await js_util.promiseToFuture(p);
      return r as String?;
    } catch (_) {
      return null;
    }
  }
}
