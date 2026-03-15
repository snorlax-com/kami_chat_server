import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// MediaPipe Face Meshのランドマークインデックス（468個のランドマーク）
class MediaPipeLandmarks {
  // 眉のランドマーク（左眉: 10個、右眉: 10個）
  static const List<int> leftEyebrow = [107, 55, 65, 52, 53, 46, 70, 63, 105, 66];
  static const List<int> rightEyebrow = [336, 285, 295, 282, 283, 276, 300, 293, 334, 296];

  // 目のランドマーク（左目: 33個、右目: 33個）
  static const List<int> leftEye = [
    33,
    7,
    163,
    144,
    145,
    153,
    154,
    155,
    133,
    173,
    157,
    158,
    159,
    160,
    161,
    246,
    36,
    0,
    11,
    228,
    229,
    230,
    231,
    232,
    233,
    244,
    245,
    122,
    6,
    196,
    3,
    51,
    48
  ];
  static const List<int> rightEye = [
    362,
    382,
    381,
    380,
    374,
    373,
    390,
    249,
    263,
    466,
    388,
    387,
    386,
    385,
    384,
    398,
    263,
    362,
    382,
    381,
    380,
    374,
    373,
    390,
    249,
    263,
    466,
    388,
    387,
    386,
    385,
    384,
    398
  ];

  // 目の精密なランドマーク（切れ長判定用）
  // 左目の外側（目尻）
  static const List<int> leftEyeOuter = [33, 7];
  // 左目の内側（目頭）
  static const List<int> leftEyeInner = [133, 163];
  // 左目の上端
  static const List<int> leftEyeTop = [159, 158, 157, 173, 133];
  // 左目の下端
  static const List<int> leftEyeBottom = [145, 144, 153, 154, 155, 133];

  // 右目の外側（目尻）
  static const List<int> rightEyeOuter = [263, 362];
  // 右目の内側（目頭）
  static const List<int> rightEyeInner = [362, 390];
  // 右目の上端
  static const List<int> rightEyeTop = [386, 385, 384, 398, 362];
  // 右目の下端
  static const List<int> rightEyeBottom = [374, 373, 390, 391, 392, 362];

  // 口のランドマーク（20個）
  static const List<int> mouth = [
    61,
    146,
    91,
    181,
    84,
    17,
    314,
    405,
    320,
    307,
    375,
    321,
    308,
    324,
    318,
    13,
    82,
    81,
    80,
    78
  ];

  // 顔の輪郭（17個）
  static const List<int> faceOval = [
    10,
    338,
    297,
    332,
    284,
    251,
    389,
    356,
    454,
    323,
    361,
    288,
    397,
    365,
    379,
    378,
    400
  ];

  // 鼻のランドマーク（10個）
  static const List<int> nose = [1, 2, 5, 4, 6, 19, 20, 94, 98, 131];
}

/// MediaPipe Face Meshのランドマークポイント（3D座標）
class MediaPipeLandmark {
  final double x;
  final double y;
  final double z;

  MediaPipeLandmark(this.x, this.y, this.z);

  double distanceTo(MediaPipeLandmark other) {
    return math.sqrt(math.pow(x - other.x, 2) + math.pow(y - other.y, 2) + math.pow(z - other.z, 2));
  }
}

/// MediaPipe Face Meshのデータ（468個のランドマーク）
class MediaPipeFaceMesh {
  final List<MediaPipeLandmark> landmarks;

  MediaPipeFaceMesh(this.landmarks);

  /// 左眉のランドマークを取得
  List<MediaPipeLandmark> getLeftEyebrow() {
    return MediaPipeLandmarks.leftEyebrow.map((i) => landmarks[i]).toList();
  }

  /// 右眉のランドマークを取得
  List<MediaPipeLandmark> getRightEyebrow() {
    return MediaPipeLandmarks.rightEyebrow.map((i) => landmarks[i]).toList();
  }

  /// 左目のランドマークを取得
  List<MediaPipeLandmark> getLeftEye() {
    return MediaPipeLandmarks.leftEye.map((i) => landmarks[i]).toList();
  }

  /// 右目のランドマークを取得
  List<MediaPipeLandmark> getRightEye() {
    return MediaPipeLandmarks.rightEye.map((i) => landmarks[i]).toList();
  }

  /// 口のランドマークを取得
  List<MediaPipeLandmark> getMouth() {
    return MediaPipeLandmarks.mouth.map((i) => landmarks[i]).toList();
  }

  /// 顔の輪郭のランドマークを取得
  List<MediaPipeLandmark> getFaceOval() {
    return MediaPipeLandmarks.faceOval.map((i) => landmarks[i]).toList();
  }

  /// 鼻のランドマークを取得
  List<MediaPipeLandmark> getNose() {
    return MediaPipeLandmarks.nose.map((i) => landmarks[i]).toList();
  }

  /// 左目の外側（目尻）のランドマークを取得
  List<MediaPipeLandmark> getLeftEyeOuter() {
    return MediaPipeLandmarks.leftEyeOuter.map((i) => landmarks[i]).toList();
  }

  /// 左目の内側（目頭）のランドマークを取得
  List<MediaPipeLandmark> getLeftEyeInner() {
    return MediaPipeLandmarks.leftEyeInner.map((i) => landmarks[i]).toList();
  }

  /// 左目の上端のランドマークを取得
  List<MediaPipeLandmark> getLeftEyeTop() {
    return MediaPipeLandmarks.leftEyeTop.map((i) => landmarks[i]).toList();
  }

  /// 左目の下端のランドマークを取得
  List<MediaPipeLandmark> getLeftEyeBottom() {
    return MediaPipeLandmarks.leftEyeBottom.map((i) => landmarks[i]).toList();
  }

  /// 右目の外側（目尻）のランドマークを取得
  List<MediaPipeLandmark> getRightEyeOuter() {
    return MediaPipeLandmarks.rightEyeOuter.map((i) => landmarks[i]).toList();
  }

  /// 右目の内側（目頭）のランドマークを取得
  List<MediaPipeLandmark> getRightEyeInner() {
    return MediaPipeLandmarks.rightEyeInner.map((i) => landmarks[i]).toList();
  }

  /// 右目の上端のランドマークを取得
  List<MediaPipeLandmark> getRightEyeTop() {
    return MediaPipeLandmarks.rightEyeTop.map((i) => landmarks[i]).toList();
  }

  /// 右目の下端のランドマークを取得
  List<MediaPipeLandmark> getRightEyeBottom() {
    return MediaPipeLandmarks.rightEyeBottom.map((i) => landmarks[i]).toList();
  }
}

/// Google ML KitのデータからMediaPipe Face Mesh相当のランドマークを推定
class MediaPipeFaceMeshEstimator {
  /// Google ML KitのFaceからMediaPipe Face Mesh相当のランドマークを推定
  /// 正規化された座標（0.0-1.0）を返す
  static MediaPipeFaceMesh? estimateFromMLKit(Face face, {double imageWidth = 1.0, double imageHeight = 1.0}) {
    try {
      final landmarks = <MediaPipeLandmark>[];

      // Google ML Kitのデータから基本的なランドマークを取得
      final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
      final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
      final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;
      final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
      final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;

      // 眉の輪郭からランドマークを推定
      final leftBrow = face.contours[FaceContourType.leftEyebrowTop]?.points ?? [];
      final rightBrow = face.contours[FaceContourType.rightEyebrowTop]?.points ?? [];

      // 目の輪郭からランドマークを推定
      final leftEyeContour = face.contours[FaceContourType.leftEye]?.points ?? [];
      final rightEyeContour = face.contours[FaceContourType.rightEye]?.points ?? [];

      // 顔の輪郭からランドマークを推定
      final faceContour = face.contours[FaceContourType.face]?.points ?? [];

      final box = face.boundingBox;
      final width = box.width;
      final height = box.height;

      // 468個のランドマークを生成（推定）
      // 実際のMediaPipe Face Meshの468個のランドマークを模擬
      for (int i = 0; i < 468; i++) {
        double x = 0.5;
        double y = 0.5;
        double z = 0.0;

        // 既知のランドマークから推定（正規化された座標: 0.0-1.0）
        if (i < 10) {
          // 左眉のランドマーク（0-9）- MediaPipeのインデックス107, 55, 65, 52, 53, 46, 70, 63, 105, 66に相当
          if (leftBrow.isNotEmpty) {
            final idx = (i * leftBrow.length / 10).floor().clamp(0, leftBrow.length - 1);
            final point = leftBrow[idx];
            x = (point.x - box.left) / width;
            y = (point.y - box.top) / height;
          }
        } else if (i < 20) {
          // 右眉のランドマーク（10-19）- MediaPipeのインデックス336, 285, 295, 282, 283, 276, 300, 293, 334, 296に相当
          if (rightBrow.isNotEmpty) {
            final idx = ((i - 10) * rightBrow.length / 10).floor().clamp(0, rightBrow.length - 1);
            final point = rightBrow[idx];
            x = (point.x - box.left) / width;
            y = (point.y - box.top) / height;
          }
        } else if (i < 53) {
          // 左目のランドマーク（20-52）
          if (leftEyeContour.isNotEmpty) {
            final idx = ((i - 20) * leftEyeContour.length / 33).floor().clamp(0, leftEyeContour.length - 1);
            final point = leftEyeContour[idx];
            x = (point.x - box.left) / width;
            y = (point.y - box.top) / height;
          } else if (leftEye != null) {
            // 目の中心から推定
            x = (leftEye.x - box.left) / width;
            y = (leftEye.y - box.top) / height;
          }
        } else if (i < 86) {
          // 右目のランドマーク（53-85）
          if (rightEyeContour.isNotEmpty) {
            final idx = ((i - 53) * rightEyeContour.length / 33).floor().clamp(0, rightEyeContour.length - 1);
            final point = rightEyeContour[idx];
            x = (point.x - box.left) / width;
            y = (point.y - box.top) / height;
          } else if (rightEye != null) {
            // 目の中心から推定
            x = (rightEye.x - box.left) / width;
            y = (rightEye.y - box.top) / height;
          }
        } else if (i < 106) {
          // 口のランドマーク（86-105）
          if (leftMouth != null && rightMouth != null) {
            final ratio = (i - 86) / 20.0;
            x = ((leftMouth.x * (1 - ratio) + rightMouth.x * ratio) - box.left) / width;
            y = ((leftMouth.y * (1 - ratio) + rightMouth.y * ratio) - box.top) / height;
          }
        } else if (i < 123) {
          // 顔の輪郭のランドマーク（106-122）
          if (faceContour.isNotEmpty) {
            final idx = ((i - 106) * faceContour.length / 17).floor().clamp(0, faceContour.length - 1);
            final point = faceContour[idx];
            x = (point.x - box.left) / width;
            y = (point.y - box.top) / height;
          }
        } else if (i < 133) {
          // 鼻のランドマーク（123-132）
          if (noseBase != null) {
            x = (noseBase.x - box.left) / width;
            y = (noseBase.y - box.top) / height;
            // 鼻の周辺を推定
            final offset = (i - 123) * 0.01;
            x = (x + offset).clamp(0.0, 1.0);
            y = (y + offset).clamp(0.0, 1.0);
          }
        } else {
          // その他のランドマーク（133-467）は既存のデータから補間
          if (faceContour.isNotEmpty) {
            final idx = ((i - 133) * faceContour.length / 335).floor().clamp(0, faceContour.length - 1);
            final point = faceContour[idx];
            x = (point.x - box.left) / width;
            y = (point.y - box.top) / height;
          }
        }

        // 正規化された座標（0.0-1.0）を確保
        x = x.clamp(0.0, 1.0);
        y = y.clamp(0.0, 1.0);
        landmarks.add(MediaPipeLandmark(x, y, z));
      }

      return MediaPipeFaceMesh(landmarks);
    } catch (e) {
      print('[MediaPipeFaceMeshEstimator] Error: $e');
      return null;
    }
  }
}
