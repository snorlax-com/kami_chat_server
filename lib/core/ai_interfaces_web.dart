// Web用スタブ: tflite_flutter / dart:ffi を使わない

import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:kami_face_oracle/services/remote_config_service.dart';

class AppAiConfig {
  static bool get enableTFLite => RemoteConfigService.instance.getBool('enable_tflite', defaultValue: false);
  static bool get enableSegmentation =>
      RemoteConfigService.instance.getBool('enable_segmentation', defaultValue: false);
  static String get modelsDir => 'assets/models/';
}

class GlossEvennessTFLite {
  final String modelPath;
  GlossEvennessTFLite(this.modelPath);
  bool get isAvailable => false;
  Future<Map<String, double>?> predict(img.Image face) async => null;
}

class BlemishSegmentation {
  final String modelPath;
  BlemishSegmentation(this.modelPath);
  bool get isAvailable => false;
  Future<double?> inferMaskRatio(img.Image face) async => null;
}

class SkinConditionClassifier {
  final String modelPath;
  SkinConditionClassifier(this.modelPath);
  bool get isAvailable => false;
  Future<bool> initialize() async => false;
  Future<Map<String, double>?> classify(img.Image faceImage) async => null;
  void dispose() {}
}
