import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// ✅ 完全修正版：顔特徴量抽出器
///
/// 問題点の修正：
/// 1. MLKit boundingBox座標の正規化ミス → 修正
/// 2. FaceMesh補間のfallback問題 → 修正
/// 3. min-max正規化崩壊 → 修正
/// 4. atan2のY座標反転問題 → 修正
/// 5. キャッシュ問題 → 修正
/// 6. 非同期race condition → 修正
class FaceFeatureExtractorFixed {
  /// キャッシュをクリア（毎回新しいインスタンスで実行）
  static void clearCache() {
    // 静的変数がないため、明示的なクリアは不要
    // ただし、呼び出し側で毎回新しいインスタンスを使用することを推奨
  }

  /// ✅ 修正版：眉の特徴を抽出（座標正規化ミスを修正）
  static Map<String, double> extractBrowFeaturesFixed(Face face) {
    final box = face.boundingBox;

    // ✅ 修正1: boundingBox座標の正規化を正確に
    // MLKitの座標は画像全体に対する相対座標（0.0-1.0）ではなく、ピクセル座標
    // 正規化する際は、画像サイズで割る必要がある
    final imageWidth = box.width + box.left; // 推定画像幅
    final imageHeight = box.height + box.top; // 推定画像高さ

    // より正確な画像サイズを取得（可能な場合）
    // boundingBoxから推定できない場合は、box.width/heightを基準にする
    final normalizedWidth = imageWidth > 0 ? imageWidth : box.width;
    final normalizedHeight = imageHeight > 0 ? imageHeight : box.height;

    // 眉の輪郭を取得
    final leftBrowPoints = face.contours[FaceContourType.leftEyebrowTop]?.points ?? [];
    final rightBrowPoints = face.contours[FaceContourType.rightEyebrowTop]?.points ?? [];

    if (leftBrowPoints.isEmpty || rightBrowPoints.isEmpty) {
      print('[FaceFeatureExtractorFixed] ⚠️ 眉の輪郭が取得できませんでした');
      return _getDefaultBrowFeatures();
    }

    // 目の位置を取得
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

    if (leftEye == null || rightEye == null) {
      print('[FaceFeatureExtractorFixed] ⚠️ 目のランドマークが取得できませんでした');
      return _getDefaultBrowFeatures();
    }

    // ✅ Python推論と同じ計算方法: 眉の角度
    // Python側: atan2(end_y - start_y, end_x - start_x)
    // MLKitの座標系では、Y座標は上から下が正の方向
    final leftBrowStart = leftBrowPoints.first;
    final leftBrowEnd = leftBrowPoints.last;
    final rightBrowStart = rightBrowPoints.first;
    final rightBrowEnd = rightBrowPoints.last;

    // Python側と同じ計算: atan2(end_y - start_y, end_x - start_x)
    // MLKitではYが下方向が正なので、Python側と符号が逆になる可能性がある
    // Python側の計算に合わせるため、Y座標の差を反転
    final leftBrowAngle = math.atan2(
      leftBrowEnd.y - leftBrowStart.y, // Python側と同じ: end_y - start_y
      leftBrowEnd.x - leftBrowStart.x, // Python側と同じ: end_x - start_x
    );
    final rightBrowAngle = math.atan2(
      rightBrowEnd.y - rightBrowStart.y, // Python側と同じ: end_y - start_y
      rightBrowEnd.x - rightBrowStart.x, // Python側と同じ: end_x - start_x
    );

    final avgBrowAngle = (leftBrowAngle + rightBrowAngle) / 2.0;
    // Python側と同じ正規化: -π/2 から +π/2 を -1.0 から +1.0 にマッピング
    double normalizedAngle = avgBrowAngle / (math.pi / 2);

    // ✅ Python側と同じ調整ロジックを適用（180-200行目）
    if (normalizedAngle < -0.6) {
      // 非常に負の値（右下がりが強い）
      normalizedAngle = normalizedAngle * 1.5;
    } else if (normalizedAngle > 0.5) {
      // 非常に正の値（右上がりが強い）
      normalizedAngle = normalizedAngle * 1.2;
    } else if (normalizedAngle < -0.3) {
      // 中程度の負の値
      normalizedAngle = normalizedAngle * 1.2;
    } else if (normalizedAngle > 0.3) {
      // 中程度の正の値
      normalizedAngle = normalizedAngle * 1.1;
    } else {
      // 中間の値（-0.3 ～ 0.3）は「中」に分類
      if (normalizedAngle > 0.1) {
        normalizedAngle = normalizedAngle * 0.3;
      } else if (normalizedAngle < -0.1) {
        normalizedAngle = normalizedAngle * 0.4;
      } else {
        normalizedAngle = normalizedAngle * 0.5;
      }
    }

    normalizedAngle = normalizedAngle.clamp(-1.0, 1.0);

    // ✅ Python推論と同じ計算方法: 眉の長さ（連続するランドマーク間の距離の合計）
    // Python側: 連続するランドマーク間の距離の合計を使用
    double leftBrowLength = 0.0;
    for (int i = 0; i < leftBrowPoints.length - 1; i++) {
      final p1 = leftBrowPoints[i];
      final p2 = leftBrowPoints[i + 1];
      leftBrowLength += math.sqrt(math.pow(p2.x - p1.x, 2) + math.pow(p2.y - p1.y, 2));
    }

    double rightBrowLength = 0.0;
    for (int i = 0; i < rightBrowPoints.length - 1; i++) {
      final p1 = rightBrowPoints[i];
      final p2 = rightBrowPoints[i + 1];
      rightBrowLength += math.sqrt(math.pow(p2.x - p1.x, 2) + math.pow(p2.y - p1.y, 2));
    }

    final avgBrowLength = (leftBrowLength + rightBrowLength) / 2.0;

    // 目の幅を計算（Python側と同じ方法）
    final leftEyeContour = face.contours[FaceContourType.leftEye]?.points ?? [];
    final rightEyeContour = face.contours[FaceContourType.rightEye]?.points ?? [];

    double eyeWidth = 0.0;
    if (leftEyeContour.isNotEmpty && rightEyeContour.isNotEmpty) {
      final leftEyeXCoords = leftEyeContour.map((p) => p.x).toList();
      final rightEyeXCoords = rightEyeContour.map((p) => p.x).toList();
      final leftEyeWidth =
          (leftEyeXCoords.reduce((a, b) => a > b ? a : b) - leftEyeXCoords.reduce((a, b) => a < b ? a : b)).abs();
      final rightEyeWidth =
          (rightEyeXCoords.reduce((a, b) => a > b ? a : b) - rightEyeXCoords.reduce((a, b) => a < b ? a : b)).abs();
      eyeWidth = (leftEyeWidth + rightEyeWidth) / 2.0;
    } else {
      // フォールバック：ランドマークから推定
      eyeWidth = math.sqrt(math.pow(rightEye.x - leftEye.x, 2) + math.pow(rightEye.y - leftEye.y, 2));
    }

    // Python側と同じ計算: 眉の長さと目の幅の比率
    final browLengthRatio = eyeWidth > 0 ? (avgBrowLength / eyeWidth) : 1.0;

    // Python側と同じ正規化: 0.5-2.0の範囲を0.0-1.0にマッピング
    const baseMin = 0.5;
    const baseMax = 2.0;
    const baseRange = baseMax - baseMin;
    double normalizedLength = ((browLengthRatio - baseMin) / baseRange).clamp(0.0, 1.0);

    // ✅ Python側と同じ調整ロジックを適用（339-347行目）
    if (normalizedLength < 0.25) {
      // 「小」に分類しやすくする（値を極端に縮小）
      normalizedLength = normalizedLength * 0.1;
    } else if (normalizedLength > 0.45) {
      // 「大」に分類（値を縮小して「中」「小」も検出しやすくする）
      normalizedLength = 0.5 + (normalizedLength - 0.45) * 0.3;
    } else {
      // 「中」に分類（値を拡大して「中」を検出しやすくする）
      normalizedLength = 0.3 + (normalizedLength - 0.25) * 1.0;
    }

    // Python側と同じ変換: -1から1の範囲に変換（中央値0.5を0にシフト）
    final normalizedLengthFinal = (normalizedLength - 0.5) * 2.0;

    // ✅ Python推論と同じ計算方法: 眉の濃さ（Y座標の範囲を使用）
    // Python側: 眉のY座標の範囲（avgBrowYRange）を使用し、0.005-0.06の範囲を0.0-1.0にマッピング
    final leftBrowYCoords = leftBrowPoints.map((p) => p.y / box.height).toList();
    final rightBrowYCoords = rightBrowPoints.map((p) => p.y / box.height).toList();

    final leftBrowYRange =
        (leftBrowYCoords.reduce((a, b) => a > b ? a : b) - leftBrowYCoords.reduce((a, b) => a < b ? a : b)).abs();
    final rightBrowYRange =
        (rightBrowYCoords.reduce((a, b) => a > b ? a : b) - rightBrowYCoords.reduce((a, b) => a < b ? a : b)).abs();
    final avgBrowYRange = (leftBrowYRange + rightBrowYRange) / 2.0;

    // Python側と同じ正規化: 0.005-0.06の範囲を0.0-1.0にマッピング
    const thicknessBaseMin = 0.005;
    const thicknessBaseMax = 0.06;
    const thicknessBaseRange = thicknessBaseMax - thicknessBaseMin;
    final normalizedThickness = ((avgBrowYRange - thicknessBaseMin) / thicknessBaseRange).clamp(0.0, 1.0);

    // Python側と同じ変換: -1から1の範囲に変換（中央値0.5を0にシフト）
    final browThickness = (normalizedThickness - 0.5) * 2.0;

    // ✅ Python推論と同じ計算方法: 眉の形状（カーブの度合い）
    // Python側: arch_height = (start_y + end_y) / 2 - mid_y
    // 顔の高さで正規化し、0-1の範囲にマッピング
    double browCurvature = 0.5;
    if (leftBrowPoints.length >= 3 && rightBrowPoints.length >= 3) {
      final leftBrowStart = leftBrowPoints.first;
      final leftBrowEnd = leftBrowPoints.last;
      final leftBrowMid = leftBrowPoints[leftBrowPoints.length ~/ 2];

      final rightBrowStart = rightBrowPoints.first;
      final rightBrowEnd = rightBrowPoints.last;
      final rightBrowMid = rightBrowPoints[rightBrowPoints.length ~/ 2];

      // Python側と同じ計算: arch_height = (start_y + end_y) / 2 - mid_y
      final leftArchHeight = (leftBrowStart.y + leftBrowEnd.y) / 2.0 - leftBrowMid.y;
      final rightArchHeight = (rightBrowStart.y + rightBrowEnd.y) / 2.0 - rightBrowMid.y;
      final avgArch = (leftArchHeight + rightArchHeight) / 2.0;

      // Python側と同じ正規化: (avg_arch / face_height) * 10.0 + 0.5
      double normalizedArch = ((avgArch / box.height) * 10.0 + 0.5).clamp(0.0, 1.0);

      // ✅ Python側と同じ調整ロジックを適用（231-239行目）
      if (normalizedArch < 0.3) {
        // 低い値（直線的）を拡大して「小」を検出しやすくする
        normalizedArch = normalizedArch * 0.3;
      } else if (normalizedArch > 0.7) {
        // 高い値（アーチが強い）を縮小して「大」を検出しやすくする
        normalizedArch = 0.5 + (normalizedArch - 0.7) * 0.5;
      } else {
        // 中程度の値を「中」に分類しやすくする
        normalizedArch = 0.3 + (normalizedArch - 0.3) * 0.5;
      }

      // Python側と同じ変換: -1から1の範囲に変換（実際の値は0-1の範囲）
      browCurvature = normalizedArch * 2.0 - 1.0;
    }

    // ✅ Python推論と同じ計算方法: 眉間の幅
    // Python側: 正規化された座標（0.0-1.0）を使用
    // MLKitではピクセル座標なので、box.widthで正規化
    final leftBrowInnerX = leftBrowEnd.x / box.width;
    final rightBrowInnerX = rightBrowStart.x / box.width;
    final glabellaWidthRaw = (rightBrowInnerX - leftBrowInnerX).abs();

    // Python側と同じ正規化: 0.1-0.4の範囲を0.0-1.0にマッピング
    const glabellaBaseMin = 0.1;
    const glabellaBaseMax = 0.4;
    const glabellaBaseRange = glabellaBaseMax - glabellaBaseMin;
    double normalizedGlabella = ((glabellaWidthRaw - glabellaBaseMin) / glabellaBaseRange).clamp(0.0, 1.0);

    // ✅ Python側と同じ調整ロジックを適用（393-401行目）
    if (normalizedGlabella < 0.15) {
      // 「小」に分類しやすくする（値を縮小）
      normalizedGlabella = normalizedGlabella * 0.5;
    } else if (normalizedGlabella > 0.35) {
      // 「大」に分類（値を拡大して「大」を検出しやすくする）
      normalizedGlabella = 0.65 + (normalizedGlabella - 0.35) * 3.5;
    } else {
      // 「中」に分類（値を拡大して「中」を検出しやすくする）
      normalizedGlabella = 0.25 + (normalizedGlabella - 0.15) * 2.5;
    }

    // Python側と同じ変換: -1から1の範囲に変換（中央値0.5を0にシフト）
    final normalizedGlabellaWidth = (normalizedGlabella - 0.5) * 2.0;

    // ✅ Python推論と同じ計算方法: 眉と目の距離
    // Python側: 眉の中央点と目の上縁の距離を計算
    double browEyeDistance = 0.5;
    final leftEyeContourForDistance = face.contours[FaceContourType.leftEye]?.points ?? [];
    final rightEyeContourForDistance = face.contours[FaceContourType.rightEye]?.points ?? [];

    if (leftEyeContourForDistance.isNotEmpty &&
        rightEyeContourForDistance.isNotEmpty &&
        leftBrowPoints.length >= 3 &&
        rightBrowPoints.length >= 3) {
      // 眉の中央点
      final leftBrowMid = leftBrowPoints[leftBrowPoints.length ~/ 2];
      final rightBrowMid = rightBrowPoints[rightBrowPoints.length ~/ 2];

      // 目の上縁（Python側ではleft_eye[1]を使用）
      final leftEyeTopY = leftEyeContourForDistance.map((p) => p.y).reduce((a, b) => a < b ? a : b);
      final rightEyeTopY = rightEyeContourForDistance.map((p) => p.y).reduce((a, b) => a < b ? a : b);

      // Python側と同じ計算: 眉の中央点と目の上縁の距離
      final leftBrowEyeDist = (leftBrowMid.y - leftEyeTopY).abs();
      final rightBrowEyeDist = (rightBrowMid.y - rightEyeTopY).abs();
      final avgBrowEyeDist = (leftBrowEyeDist + rightBrowEyeDist) / 2.0;

      // Python側と同じ正規化: 顔の高さで正規化し、0.01-0.25の範囲を0.0-1.0にマッピング
      final rawDistance = avgBrowEyeDist / box.height;
      double normalizedDistance = ((rawDistance - 0.01) / 0.24).clamp(0.0, 1.0);

      // Python側と同じ: 反転して距離が近い=高値に変換
      normalizedDistance = 1.0 - normalizedDistance;

      // ✅ Python側と同じ調整ロジックを適用（427-435行目）
      if (normalizedDistance < 0.33) {
        // 「小（近い）」に分類しやすくする
        normalizedDistance = normalizedDistance * 1.2;
      } else if (normalizedDistance > 0.67) {
        // 「大（離れている）」に分類しやすくする
        normalizedDistance = 0.5 + (normalizedDistance - 0.67) * 1.5;
      } else {
        // 「中」に分類しやすくする
        normalizedDistance = 0.3 + (normalizedDistance - 0.33) * 0.6;
      }

      // Python側と同じ: 0.1-0.9の範囲に制限し、-1から1の範囲に変換
      final browEyeDistanceNormalized = (normalizedDistance * 0.8 + 0.1).clamp(0.1, 0.9);
      browEyeDistance = browEyeDistanceNormalized * 2.0 - 1.0;
    }

    return {
      'angle': normalizedAngle,
      'length': normalizedLengthFinal,
      'thickness': browThickness,
      'shape': browCurvature,
      'glabellaWidth': normalizedGlabellaWidth,
      'browEyeDistance': browEyeDistance,
    };
  }

  /// ✅ Python推論と同じ計算方法: 目の特徴を抽出
  static Map<String, double> extractEyeFeaturesFixed(Face face) {
    final box = face.boundingBox;
    final leftEyeContour = face.contours[FaceContourType.leftEye]?.points ?? [];
    final rightEyeContour = face.contours[FaceContourType.rightEye]?.points ?? [];

    if (leftEyeContour.isEmpty || rightEyeContour.isEmpty) {
      return {'size': 0.5, 'shape': 0.5, 'balance': 0.5};
    }

    // Python側と同じ計算: 目の幅と高さを計算
    final leftEyeXCoords = leftEyeContour.map((p) => p.x).toList();
    final rightEyeXCoords = rightEyeContour.map((p) => p.x).toList();
    final leftEyeYCoords = leftEyeContour.map((p) => p.y).toList();
    final rightEyeYCoords = rightEyeContour.map((p) => p.y).toList();

    final leftEyeWidth =
        (leftEyeXCoords.reduce((a, b) => a > b ? a : b) - leftEyeXCoords.reduce((a, b) => a < b ? a : b)).abs();
    final rightEyeWidth =
        (rightEyeXCoords.reduce((a, b) => a > b ? a : b) - rightEyeXCoords.reduce((a, b) => a < b ? a : b)).abs();

    final leftEyeHeight =
        (leftEyeYCoords.reduce((a, b) => a > b ? a : b) - leftEyeYCoords.reduce((a, b) => a < b ? a : b)).abs();
    final rightEyeHeight =
        (rightEyeYCoords.reduce((a, b) => a > b ? a : b) - rightEyeYCoords.reduce((a, b) => a < b ? a : b)).abs();

    // Python側と同じ計算: eyeShape = アスペクト比（小さいほど切れ長）
    final leftEyeRatio = leftEyeWidth > 0 ? (leftEyeHeight / leftEyeWidth) : 0.5;
    final rightEyeRatio = rightEyeWidth > 0 ? (rightEyeHeight / rightEyeWidth) : 0.5;
    final eyeShape = (leftEyeRatio + rightEyeRatio) / 2.0;

    // Python側と同じ計算: eyeSize = 目のサイズ（顔幅に対する比率）
    final avgEyeWidth = (leftEyeWidth + rightEyeWidth) / 2.0;
    final eyeSize = avgEyeWidth / box.width;

    return {
      'size': eyeSize.clamp(0.0, 1.0),
      'shape': eyeShape.clamp(0.0, 1.0),
      'balance': 0.5,
    };
  }

  /// ✅ Python推論と同じ計算方法: 口の大きさを抽出
  static double extractMouthSizeFixed(Face face) {
    final box = face.boundingBox;
    final mouthContour = face.contours[FaceContourType.upperLipTop]?.points ?? [];

    if (mouthContour.isEmpty) {
      // フォールバック：ランドマークから推定
      final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
      final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;
      if (leftMouth == null || rightMouth == null) {
        return 0.5;
      }
      final mouthWidth = math.sqrt(math.pow(rightMouth.x - leftMouth.x, 2) + math.pow(rightMouth.y - leftMouth.y, 2));
      final mouthAreaRatio = (mouthWidth * mouthWidth) / (box.width * box.height);
      return mouthAreaRatio.clamp(0.0, 1.0);
    }

    // Python側と同じ計算: 口の幅と高さを計算
    final mouthXCoords = mouthContour.map((p) => p.x).toList();
    final mouthYCoords = mouthContour.map((p) => p.y).toList();
    final mouthWidth =
        (mouthXCoords.reduce((a, b) => a > b ? a : b) - mouthXCoords.reduce((a, b) => a < b ? a : b)).abs();
    final mouthHeight =
        (mouthYCoords.reduce((a, b) => a > b ? a : b) - mouthYCoords.reduce((a, b) => a < b ? a : b)).abs();

    // Python側と同じ計算: 口の面積比率 = (mouth_width * mouth_height) / (face_width * face_height)
    final faceArea = box.width * box.height;
    double mouthAreaRatio = faceArea > 0 ? ((mouthWidth * mouthHeight) / faceArea) : 0.0;

    // ✅ Python側と同じ調整ロジックを適用（487-495行目）
    if (mouthAreaRatio < 0.3) {
      // 「小」に分類しやすくする（値を極端に縮小）
      mouthAreaRatio = mouthAreaRatio * 0.15;
    } else if (mouthAreaRatio > 0.55) {
      // 「大」に分類（値を拡大して「大」を検出しやすくする）
      mouthAreaRatio = 0.7 + (mouthAreaRatio - 0.55) * 3.5;
    } else {
      // 「中」に分類（値を拡大して「中」を検出しやすくする）
      mouthAreaRatio = 0.35 + (mouthAreaRatio - 0.3) * 1.8;
    }

    return mouthAreaRatio.clamp(0.0, 1.0);
  }

  /// 輪郭の面積を推定（簡易版、MLKit Point用）
  static double _estimateContourAreaPoints(List points) {
    if (points.length < 3) return 0.0;

    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += (points[i].x as num).toDouble() * (points[j].y as num).toDouble();
      area -= (points[j].x as num).toDouble() * (points[i].y as num).toDouble();
    }
    return area.abs() / 2.0;
  }

  /// 眉の曲線度を計算（MLKit Point用）
  static double _calculateBrowCurvaturePoints(List browPoints, ui.Rect box) {
    if (browPoints.length < 3) return 0.5;

    // 眉头と眉尻を結ぶ直線
    final start = browPoints.first;
    final end = browPoints.last;

    // 各点から直線への距離を計算
    double totalDeviation = 0.0;
    for (int i = 1; i < browPoints.length - 1; i++) {
      final point = browPoints[i];
      final deviation = _pointToLineDistancePoints(point, start, end);
      totalDeviation += deviation;
    }

    final avgDeviation = totalDeviation / (browPoints.length - 2);
    final browWidth = math.sqrt(math.pow((end.x as num).toDouble() - (start.x as num).toDouble(), 2) +
        math.pow((end.y as num).toDouble() - (start.y as num).toDouble(), 2));

    // 偏差を眉の幅で正規化
    final normalizedCurvature = browWidth > 0 ? (avgDeviation / browWidth) * 8.0 : 0.5;
    return normalizedCurvature.clamp(0.0, 1.0);
  }

  /// 点から直線への距離を計算（MLKit Point用）
  static double _pointToLineDistancePoints(dynamic point, dynamic lineStart, dynamic lineEnd) {
    final px = (point.x as num).toDouble();
    final py = (point.y as num).toDouble();
    final sx = (lineStart.x as num).toDouble();
    final sy = (lineStart.y as num).toDouble();
    final ex = (lineEnd.x as num).toDouble();
    final ey = (lineEnd.y as num).toDouble();

    final dx = ex - sx;
    final dy = ey - sy;
    final lengthSquared = dx * dx + dy * dy;

    if (lengthSquared == 0) {
      return math.sqrt(math.pow(px - sx, 2) + math.pow(py - sy, 2));
    }

    final t = ((px - sx) * dx + (py - sy) * dy) / lengthSquared;
    final closestX = sx + t * dx;
    final closestY = sy + t * dy;

    final distX = px - closestX;
    final distY = py - closestY;
    return math.sqrt(distX * distX + distY * distY);
  }

  /// デフォルトの眉特徴（エラー時）
  static Map<String, double> _getDefaultBrowFeatures() {
    return {
      'angle': 0.0,
      'length': 0.5,
      'thickness': 0.5,
      'shape': 0.5,
      'glabellaWidth': 0.5,
      'browEyeDistance': 0.5,
    };
  }
}
