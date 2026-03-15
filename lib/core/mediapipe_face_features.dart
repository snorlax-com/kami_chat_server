import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'mediapipe_face_data.dart';
import 'dart:convert';
import 'dart:io';

/// MediaPipe Face Meshから抽出した特徴量
class MediaPipeFaceFeatures {
  final double faceAspectRatio; // 顔全体の縦横比
  final double foreheadWidth; // 額の幅
  final double jawWidth; // 顎の幅
  final double jawCurvature; // 顎の丸さ
  final double cheekProminence; // 頬の突出度
  final double eyeShape; // 目の形状（縦横比）
  final double noseWidth; // 鼻の幅
  final double noseHeight; // 鼻の高さ
  final double mouthWidth; // 口の幅

  MediaPipeFaceFeatures({
    required this.faceAspectRatio,
    required this.foreheadWidth,
    required this.jawWidth,
    required this.jawCurvature,
    required this.cheekProminence,
    required this.eyeShape,
    required this.noseWidth,
    required this.noseHeight,
    required this.mouthWidth,
  });

  /// JSONに変換（データセット保存用）
  Map<String, dynamic> toJson() {
    return {
      'faceAspectRatio': faceAspectRatio,
      'foreheadWidth': foreheadWidth,
      'jawWidth': jawWidth,
      'jawCurvature': jawCurvature,
      'cheekProminence': cheekProminence,
      'eyeShape': eyeShape,
      'noseWidth': noseWidth,
      'noseHeight': noseHeight,
      'mouthWidth': mouthWidth,
    };
  }

  /// JSONから復元
  factory MediaPipeFaceFeatures.fromJson(Map<String, dynamic> json) {
    return MediaPipeFaceFeatures(
      faceAspectRatio: json['faceAspectRatio']?.toDouble() ?? 0.0,
      foreheadWidth: json['foreheadWidth']?.toDouble() ?? 0.0,
      jawWidth: json['jawWidth']?.toDouble() ?? 0.0,
      jawCurvature: json['jawCurvature']?.toDouble() ?? 0.0,
      cheekProminence: json['cheekProminence']?.toDouble() ?? 0.0,
      eyeShape: json['eyeShape']?.toDouble() ?? 0.0,
      noseWidth: json['noseWidth']?.toDouble() ?? 0.0,
      noseHeight: json['noseHeight']?.toDouble() ?? 0.0,
      mouthWidth: json['mouthWidth']?.toDouble() ?? 0.0,
    );
  }
}

/// MediaPipe Face Meshから特徴量を抽出
class MediaPipeFaceFeatureExtractor {
  /// FaceとMediaPipeFaceMeshから特徴量を抽出
  static MediaPipeFaceFeatures extractFeatures(
    Face face,
    MediaPipeFaceMesh? faceMesh, {
    double imageWidth = 1.0,
    double imageHeight = 1.0,
  }) {
    // MediaPipe Face Meshが利用可能な場合はそれを使用、そうでなければML Kitから推定
    if (faceMesh != null) {
      return _extractFromMediaPipe(face, faceMesh, imageWidth, imageHeight);
    } else {
      return _extractFromMLKit(face, imageWidth, imageHeight);
    }
  }

  /// MediaPipe Face Meshから特徴量を抽出（高精度）
  static MediaPipeFaceFeatures _extractFromMediaPipe(
    Face face,
    MediaPipeFaceMesh faceMesh,
    double imageWidth,
    double imageHeight,
  ) {
    final box = face.boundingBox;

    // 1. 顔全体の縦横比
    final faceAspectRatio = box.height / box.width;

    // 2. 額の幅（眉の位置から推定）
    final leftBrow = faceMesh.getLeftEyebrow();
    final rightBrow = faceMesh.getRightEyebrow();
    double foreheadWidth = 0.5;
    if (leftBrow.isNotEmpty && rightBrow.isNotEmpty) {
      // 眉の外側の点を使用
      final leftBrowOuter = leftBrow.first;
      final rightBrowOuter = rightBrow.first;
      final browDistance = math.sqrt(math.pow((rightBrowOuter.x - leftBrowOuter.x) * imageWidth, 2) +
          math.pow((rightBrowOuter.y - leftBrowOuter.y) * imageHeight, 2));
      // 額の幅は眉の間の距離の約1.5倍
      foreheadWidth = (browDistance * 1.5) / box.width;
    }

    // 3. 顎の幅（顔の輪郭の下部から）
    final faceOval = faceMesh.getFaceOval();
    double jawWidth = 0.5;
    if (faceOval.length >= 3) {
      // 輪郭の下部の点を使用（インデックス8-10あたりが顎）
      final jawPoints = faceOval.sublist(math.max(0, faceOval.length - 5));
      if (jawPoints.length >= 2) {
        final leftJaw = jawPoints.first;
        final rightJaw = jawPoints.last;
        final jawDist = math.sqrt(
            math.pow((rightJaw.x - leftJaw.x) * imageWidth, 2) + math.pow((rightJaw.y - leftJaw.y) * imageHeight, 2));
        jawWidth = jawDist / box.width;
      }
    }

    // 4. 顎の曲率（丸さ）
    double jawCurvature = 0.5;
    if (faceOval.length >= 5) {
      // 輪郭の下部の曲率を計算
      final jawPoints = faceOval.sublist(math.max(0, faceOval.length - 5));
      if (jawPoints.length >= 3) {
        // 3点から曲率を計算
        final curvature = _calculateCurvature(jawPoints, imageWidth, imageHeight);
        jawCurvature = curvature.clamp(0.0, 1.0);
      }
    }

    // 5. 頬の突出度（頬骨の位置から）
    double cheekProminence = 0.5;
    if (faceOval.length >= 10) {
      // 頬骨の位置（輪郭の中間あたり）
      final cheekIndices = [faceOval.length ~/ 4, faceOval.length * 3 ~/ 4];
      if (cheekIndices[0] < faceOval.length && cheekIndices[1] < faceOval.length) {
        final leftCheek = faceOval[cheekIndices[0]];
        final rightCheek = faceOval[cheekIndices[1]];
        final centerX = box.left + box.width / 2;
        final leftDist = (leftCheek.x * imageWidth - centerX).abs();
        final rightDist = (rightCheek.x * imageWidth - centerX).abs();
        final avgDist = (leftDist + rightDist) / 2;
        cheekProminence = (avgDist / box.width).clamp(0.0, 1.0);
      }
    }

    // 6. 目の形状（縦横比）
    final leftEye = faceMesh.getLeftEye();
    final rightEye = faceMesh.getRightEye();
    double eyeShape = 0.5;
    if (leftEye.isNotEmpty && rightEye.isNotEmpty) {
      // 目の幅と高さを計算
      final leftEyeWidth = _calculateEyeWidth(leftEye, imageWidth);
      final leftEyeHeight = _calculateEyeHeight(leftEye, imageHeight);
      final rightEyeWidth = _calculateEyeWidth(rightEye, imageWidth);
      final rightEyeHeight = _calculateEyeHeight(rightEye, imageHeight);

      final avgWidth = (leftEyeWidth + rightEyeWidth) / 2;
      final avgHeight = (leftEyeHeight + rightEyeHeight) / 2;

      if (avgHeight > 0) {
        // 縦横比が大きいほど切れ長（1.0に近いほど切れ長）
        eyeShape = (avgWidth / avgHeight).clamp(0.0, 1.0);
      }
    }

    // 7. 鼻の幅
    final nose = faceMesh.getNose();
    double noseWidth = 0.5;
    if (nose.length >= 2) {
      // 鼻翼の位置から幅を計算
      final noseLeft = nose.first;
      final noseRight = nose.last;
      final noseDist = math.sqrt(
          math.pow((noseRight.x - noseLeft.x) * imageWidth, 2) + math.pow((noseRight.y - noseLeft.y) * imageHeight, 2));
      noseWidth = (noseDist / box.width).clamp(0.0, 1.0);
    }

    // 8. 鼻の高さ
    double noseHeight = 0.5;
    if (nose.length >= 2 && leftEye.isNotEmpty) {
      // 鼻の上端と下端の距離
      final noseTop = nose.first;
      final noseBottom = nose.last;
      final noseHeightDist = math.sqrt(
          math.pow((noseBottom.x - noseTop.x) * imageWidth, 2) + math.pow((noseBottom.y - noseTop.y) * imageHeight, 2));
      noseHeight = (noseHeightDist / box.height).clamp(0.0, 1.0);
    }

    // 9. 口の幅
    final mouth = faceMesh.getMouth();
    double mouthWidth = 0.5;
    if (mouth.length >= 2) {
      // 口角の位置から幅を計算
      final mouthLeft = mouth.first;
      final mouthRight = mouth.last;
      final mouthDist = math.sqrt(math.pow((mouthRight.x - mouthLeft.x) * imageWidth, 2) +
          math.pow((mouthRight.y - mouthLeft.y) * imageHeight, 2));
      mouthWidth = (mouthDist / box.width).clamp(0.0, 1.0);
    }

    return MediaPipeFaceFeatures(
      faceAspectRatio: faceAspectRatio,
      foreheadWidth: foreheadWidth,
      jawWidth: jawWidth,
      jawCurvature: jawCurvature,
      cheekProminence: cheekProminence,
      eyeShape: eyeShape,
      noseWidth: noseWidth,
      noseHeight: noseHeight,
      mouthWidth: mouthWidth,
    );
  }

  /// ML Kitから特徴量を抽出（フォールバック）
  static MediaPipeFaceFeatures _extractFromMLKit(
    Face face,
    double imageWidth,
    double imageHeight,
  ) {
    final box = face.boundingBox;
    final faceAspectRatio = box.height / box.width;

    // ML Kitのランドマークから推定
    final landmarks = face.landmarks;
    final leftEye = landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = landmarks[FaceLandmarkType.rightEye]?.position;
    final leftMouth = landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = landmarks[FaceLandmarkType.rightMouth]?.position;
    final noseBase = landmarks[FaceLandmarkType.noseBase]?.position;

    // 額の幅（目の間の距離から推定）
    double foreheadWidth = 0.5;
    if (leftEye != null && rightEye != null) {
      final eyeDistance = (rightEye.x - leftEye.x).abs();
      foreheadWidth = (eyeDistance * 1.5 / box.width).clamp(0.0, 1.0);
    }

    // 顎の幅（口の幅から推定）
    double jawWidth = 0.5;
    if (leftMouth != null && rightMouth != null) {
      final mouthDist = (rightMouth.x - leftMouth.x).abs();
      jawWidth = (mouthDist / box.width).clamp(0.0, 1.0);
    }

    // 顎の曲率（簡易推定）
    final jawCurvature = (1.0 - (faceAspectRatio - 0.75).abs() / 0.25).clamp(0.0, 1.0);

    // 頬の突出度
    double cheekProminence = 0.5;
    final leftCheek = landmarks[FaceLandmarkType.leftCheek]?.position;
    final rightCheek = landmarks[FaceLandmarkType.rightCheek]?.position;
    if (leftCheek != null && rightCheek != null) {
      final centerX = box.left + box.width / 2;
      final leftDist = (leftCheek.x - centerX).abs();
      final rightDist = (rightCheek.x - centerX).abs();
      final avgDist = (leftDist + rightDist) / 2;
      cheekProminence = (avgDist / box.width).clamp(0.0, 1.0);
    }

    // 目の形状（簡易推定）
    final eyeShape = 0.5;

    // 鼻の幅（目の間の距離から推定）
    double noseWidth = 0.5;
    if (leftEye != null && rightEye != null) {
      final eyeDistance = (rightEye.x - leftEye.x).abs();
      noseWidth = (eyeDistance * 0.3 / box.width).clamp(0.0, 1.0);
    }

    // 鼻の高さ
    double noseHeight = 0.5;
    if (noseBase != null && leftEye != null && rightEye != null) {
      final eyeCenterY = (leftEye.y + rightEye.y) / 2;
      final noseHeightDist = (noseBase.y - eyeCenterY).abs();
      noseHeight = (noseHeightDist / box.height).clamp(0.0, 1.0);
    }

    // 口の幅
    double mouthWidth = 0.5;
    if (leftMouth != null && rightMouth != null) {
      final mouthDist = (rightMouth.x - leftMouth.x).abs();
      mouthWidth = (mouthDist / box.width).clamp(0.0, 1.0);
    }

    return MediaPipeFaceFeatures(
      faceAspectRatio: faceAspectRatio,
      foreheadWidth: foreheadWidth,
      jawWidth: jawWidth,
      jawCurvature: jawCurvature,
      cheekProminence: cheekProminence,
      eyeShape: eyeShape,
      noseWidth: noseWidth,
      noseHeight: noseHeight,
      mouthWidth: mouthWidth,
    );
  }

  /// 曲率を計算（3点から）
  static double _calculateCurvature(
    List<MediaPipeLandmark> points,
    double imageWidth,
    double imageHeight,
  ) {
    if (points.length < 3) return 0.5;

    // 3点から曲率を計算
    final p1 = points[0];
    final p2 = points[points.length ~/ 2];
    final p3 = points[points.length - 1];

    final x1 = p1.x * imageWidth;
    final y1 = p1.y * imageHeight;
    final x2 = p2.x * imageWidth;
    final y2 = p2.y * imageHeight;
    final x3 = p3.x * imageWidth;
    final y3 = p3.y * imageHeight;

    // 3点が一直線上にある場合、曲率は0
    final area = ((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)).abs();
    if (area < 1e-6) return 0.0;

    // 曲率が大きいほど丸い（1.0に近い）
    final dist12 = math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));
    final dist23 = math.sqrt(math.pow(x3 - x2, 2) + math.pow(y3 - y2, 2));
    final dist13 = math.sqrt(math.pow(x3 - x1, 2) + math.pow(y3 - y1, 2));

    if (dist12 + dist23 < dist13 * 1.01) return 0.0; // ほぼ一直線

    // 曲率を正規化
    final curvature = (area / (dist12 * dist23 * dist13 + 1e-6)).clamp(0.0, 1.0);
    return curvature;
  }

  /// 目の幅を計算
  static double _calculateEyeWidth(
    List<MediaPipeLandmark> eyePoints,
    double imageWidth,
  ) {
    if (eyePoints.isEmpty) return 0.0;
    final minX = eyePoints.map((p) => p.x).reduce(math.min);
    final maxX = eyePoints.map((p) => p.x).reduce(math.max);
    return (maxX - minX) * imageWidth;
  }

  /// 目の高さを計算
  static double _calculateEyeHeight(
    List<MediaPipeLandmark> eyePoints,
    double imageHeight,
  ) {
    if (eyePoints.isEmpty) return 0.0;
    final minY = eyePoints.map((p) => p.y).reduce(math.min);
    final maxY = eyePoints.map((p) => p.y).reduce(math.max);
    return (maxY - minY) * imageHeight;
  }

  /// 特徴量をJSONファイルに保存
  static Future<void> saveFeaturesToJson(
    String imagePath,
    MediaPipeFaceFeatures features,
    String outputPath,
  ) async {
    final jsonData = {
      'imagePath': imagePath,
      'features': features.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    final file = File(outputPath);
    await file.writeAsString(jsonEncode(jsonData));
  }
}
