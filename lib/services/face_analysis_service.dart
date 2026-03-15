import 'dart:ui' as ui;
import 'package:kami_face_oracle/core/face_analyzer.dart';
import 'package:kami_face_oracle/models/face_data_model.dart';

/// 顔分析サービス
class FaceAnalysisService {
  final FaceAnalyzer _analyzer = FaceAnalyzer();

  /// 顔を分析してFaceDataを返す
  Future<FaceData?> analyzeFace(
    ui.Image image, {
    String? imagePath,
  }) async {
    try {
      final features = await _analyzer.analyze(image);
      if (features == null) {
        return null;
      }

      // FaceFeaturesからFaceDataに変換
      return FaceData(
        smile: features.smile,
        eyeOpen: features.eyeOpen,
        gloss: features.gloss,
        straightness: features.straightness,
        claim: features.claim,
        mouthCorner: features.mouthCorner(),
      );
    } catch (e) {
      print('[FaceAnalysisService] Error: $e');
      return null;
    }
  }
}
