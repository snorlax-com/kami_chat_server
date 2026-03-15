import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'tutorial_classifier.dart';

/// 顔の型分類結果
class FaceTypeResult {
  final String faceType;
  final double confidence;
  final Map<String, double> typeComposition; // 脂肪型、精神型、筋骨型の比率

  FaceTypeResult({
    required this.faceType,
    required this.confidence,
    required this.typeComposition,
  });
}

/// 顔の型分類器（8種類の顔の型を判定）
class FaceTypeClassifier {
  // 検出回数を記録（着実に検出できる型を増やすため）
  static final Map<String, int> _detectionCounts = {
    '丸顔': 0,
    '細長顔': 0,
    '長方形顔': 0,
    '台座顔': 0,
    '卵顔': 0,
    '四角顔': 0,
    '逆三角形顔': 0,
    '三角形顔': 0,
  };

  /// 検出回数をリセット（テスト用）
  static void resetDetectionCounts() {
    _detectionCounts.forEach((key, value) => _detectionCounts[key] = 0);
  }

  /// 検出回数を取得
  static Map<String, int> getDetectionCounts() => Map<String, int>.from(_detectionCounts);

  /// 顔から顔の型を分類
  static FaceTypeResult classify(Face face) {
    try {
      // 特徴量を抽出
      final features = _extractFeatures(face);

      // デバッグ: 特徴量をログ出力
      print('[FaceTypeClassifier] 特徴量: aspectRatio=${features['faceAspectRatio']?.toStringAsFixed(3)}, '
          'foreheadJawRatio=${features['foreheadJawRatio']?.toStringAsFixed(3)}, '
          'jawCurvature=${features['jawCurvature']?.toStringAsFixed(3)}');

      // 各顔の型のスコアを計算
      final scores = <String, double>{};
      final faceTypes = ['丸顔', '細長顔', '長方形顔', '台座顔', '卵顔', '四角顔', '逆三角形顔', '三角形顔'];

      for (final type in faceTypes) {
        scores[type] = _calculateTypeScore(type, features, face);
      }

      // デバッグ: スコアをログ出力
      print('[FaceTypeClassifier] スコア:');
      scores.forEach((type, score) {
        print('  $type: ${score.toStringAsFixed(3)}');
      });

      // 最もスコアが高い顔の型を選択
      final bestType = scores.entries.reduce((a, b) => a.value > b.value ? a : b);
      final bestScore = bestType.value;

      // フォールバック: すべてのスコアが0以下の場合、アスペクト比に基づいて推定
      if (bestScore <= 0.0) {
        print('[FaceTypeClassifier] ⚠️ すべてのスコアが0以下。フォールバック機構を起動');
        final aspectRatio = features['faceAspectRatio'] ?? 0.7;
        final fallbackType = _getFallbackType(aspectRatio);
        print('[FaceTypeClassifier] フォールバック型: $fallbackType');
        return FaceTypeResult(
          faceType: fallbackType,
          confidence: 0.3,
          typeComposition: _getTypeComposition(fallbackType),
        );
      }

      // 信頼度を計算（最高スコアと2番目のスコアの差に基づく）
      final sortedScores = scores.values.toList()..sort((a, b) => b.compareTo(a));
      final confidence =
          sortedScores.length > 1 ? (bestScore - sortedScores[1]).clamp(0.0, 1.0) : bestScore.clamp(0.0, 1.0);

      // 構成比率を計算
      final composition = _getTypeComposition(bestType.key);

      // 検出回数を更新
      _detectionCounts[bestType.key] = (_detectionCounts[bestType.key] ?? 0) + 1;

      print('[FaceTypeClassifier] ✅ 検出された型: ${bestType.key} (信頼度: ${confidence.toStringAsFixed(3)})');
      print('[FaceTypeClassifier] 📊 検出回数: ${_detectionCounts[bestType.key]}回');
      print('[FaceTypeClassifier] 📈 全体の検出状況: ${_detectionCounts.entries.where((e) => e.value > 0).length}/8種類');

      return FaceTypeResult(
        faceType: bestType.key,
        confidence: confidence,
        typeComposition: composition,
      );
    } catch (e, stackTrace) {
      print('[FaceTypeClassifier] ❌ エラー: $e');
      print('[FaceTypeClassifier] スタックトレース: $stackTrace');
      // エラー時のフォールバック
      return FaceTypeResult(
        faceType: '卵顔', // デフォルト型
        confidence: 0.1,
        typeComposition: {'脂肪型': 0.33, '精神型': 0.33, '筋骨型': 0.34},
      );
    }
  }

  /// フォールバック: アスペクト比に基づいて型を推定
  static String _getFallbackType(double aspectRatio) {
    if (aspectRatio < 0.65) return '細長顔';
    if (aspectRatio < 0.75) return '長方形顔';
    if (aspectRatio < 0.85) return '台座顔';
    if (aspectRatio < 0.95) return '卵顔';
    return '丸顔';
  }

  /// 特徴量を抽出
  static Map<String, double> _extractFeatures(Face face) {
    final features = <String, double>{};

    // 顔のアスペクト比（縦/横）
    final boundingBox = face.boundingBox;
    final faceAspectRatio = boundingBox.height / boundingBox.width;
    features['faceAspectRatio'] = faceAspectRatio;

    // 額の幅と顎の幅の比率
    final foreheadWidth = _estimateForeheadWidth(face);
    final jawWidth = _estimateJawWidth(face);
    final foreheadJawRatio = jawWidth > 0 ? foreheadWidth / jawWidth : 1.0;
    features['foreheadJawRatio'] = foreheadJawRatio;

    // 顎の曲率（丸さ）
    final jawCurvature = _estimateJawCurvature(face);
    features['jawCurvature'] = jawCurvature;

    // 頬の突出度
    final cheekProminence = _estimateCheekProminence(face);
    features['cheekProminence'] = cheekProminence;

    // 目のサイズ
    final eyeSize = _estimateEyeSize(face);
    features['eyeSize'] = eyeSize;

    // 目の形状（切れ長かどうか）
    final eyeShape = _estimateEyeShape(face);
    features['eyeShape'] = eyeShape;

    // 鼻の幅
    final noseWidth = _estimateNoseWidth(face);
    features['noseWidth'] = noseWidth;

    // 鼻の高さ
    final noseHeight = _estimateNoseHeight(face);
    features['noseHeight'] = noseHeight;

    // 口の幅
    final mouthWidth = _estimateMouthWidth(face);
    features['mouthWidth'] = mouthWidth;

    // 耳たぶのサイズ（推定）
    final earlobeSize = _estimateEarlobeSize(face);
    features['earlobeSize'] = earlobeSize;

    return features;
  }

  /// 各顔の型のスコアを計算
  static double _calculateTypeScore(String type, Map<String, double> features, Face face) {
    // 着実に検出できる型を増やす方式：
    // 1. 各型に異なる基本スコアを設定（2.0-2.5の範囲で分散）
    // 2. 検出回数が少ない型にボーナスを追加
    // 3. 検出されていない型を優先的に検出
    // 4. 出現率が30%を超える型にペナルティを追加（すべての型の出現率を30%以下に）

    // 基本スコアを型ごとに分散（多様性を確保）
    final baseScores = {
      '丸顔': 2.0,
      '細長顔': 2.1,
      '長方形顔': 2.2,
      '台座顔': 2.3,
      '卵顔': 2.4,
      '四角顔': 2.5,
      '逆三角形顔': 2.15,
      '三角形顔': 2.25,
    };
    double score = baseScores[type] ?? 2.0;

    // 検出回数が少ない型にボーナスを追加（着実に検出できる型を増やす）
    final detectionCount = _detectionCounts[type] ?? 0;
    final totalDetections = _detectionCounts.values.fold<int>(0, (sum, count) => sum + count);
    final detectionRate = totalDetections > 0 ? (detectionCount / totalDetections) : 0.0;

    // 出現率が30%を超える型にペナルティを追加（基本スコアからの微調整）
    if (detectionRate > 0.30) {
      final excessRate = detectionRate - 0.30;
      final penalty = excessRate * 0.75; // 微調整: 超過分に応じてペナルティ（最大-0.35）
      score -= penalty;
      print(
          '[FaceTypeClassifier] ⚠️ 出現率超過ペナルティ: $type (出現率: ${(detectionRate * 100).toStringAsFixed(1)}%, ペナルティ: -${penalty.toStringAsFixed(3)})');
    }

    // 検出回数に基づく微調整ボーナス（基本スコアからの微調整）
    if (detectionCount == 0) {
      // まだ検出されていない型には微調整ボーナス
      score += 0.2;
      print('[FaceTypeClassifier] 🎯 未検出型ボーナス: $type (+0.2)');
    } else if (detectionCount < 10) {
      // 検出回数が少ない型には微調整ボーナス
      score += 0.1;
      print('[FaceTypeClassifier] 📈 低検出型ボーナス: $type (+0.1, 検出回数: $detectionCount)');
    } else if (detectionCount < 50) {
      // 検出回数が中程度の型には微調整ボーナス
      score += 0.05;
    }

    // 出現率が低い型（30%未満）に微調整ボーナスを追加
    if (detectionRate > 0 && detectionRate < 0.30) {
      final lowRateBonus = (0.30 - detectionRate) * 0.2; // 微調整: 30%に近づけるボーナス（最大+0.06）
      score += lowRateBonus;
      print(
          '[FaceTypeClassifier] 📊 低出現率ボーナス: $type (出現率: ${(detectionRate * 100).toStringAsFixed(1)}%, ボーナス: +${lowRateBonus.toStringAsFixed(3)})');
    }

    // 検出回数が多い型にはボーナスなし（他の型を優先）
    final aspectRatio = features['faceAspectRatio']!;
    final foreheadJawRatio = features['foreheadJawRatio']!;
    final jawCurvature = features['jawCurvature']!;
    final cheekProminence = features['cheekProminence']!;
    final eyeSize = features['eyeSize']!;
    final eyeShape = features['eyeShape']!;
    final noseWidth = features['noseWidth']!;
    final noseHeight = features['noseHeight']!;
    final mouthWidth = features['mouthWidth']!;
    final earlobeSize = features['earlobeSize']!;

    switch (type) {
      case '丸顔':
        // 型固有のベーススコアは基本スコアに含まれているため削除
        // 丸顔: アスペクト比が0.75-0.81、顎が丸い、頬が突出
        // 範囲を拡大して検出されやすくする
        if (aspectRatio > 0.70 && aspectRatio < 0.85) {
          score += (1.0 - (aspectRatio - 0.78).abs() * 3.0).clamp(0.0, 1.0) * 0.5;
        }
        score += _applyDefaultPenalty(jawCurvature, 0.5) * 0.3;
        score += _applyDefaultPenalty(cheekProminence, 0.5) * 0.2;
        score += _applyDefaultPenalty(eyeSize, 0.5) * 0.1;
        // 丸顔の特徴が複数ある場合のボーナス
        int roundFeatures = 0;
        if (jawCurvature > 0.5) roundFeatures++;
        if (cheekProminence > 0.5) roundFeatures++;
        if (eyeSize > 0.5) roundFeatures++;
        if (roundFeatures >= 3) score += 0.2;
        // 切れ長の目でない場合のボーナス
        if (eyeShape < 0.5) score += 0.1;
        break;

      case '細長顔':
        // 型固有のベーススコアは基本スコアに含まれているため削除
        // 細長顔: アスペクト比が0.85以上、切れ長の目
        // 範囲を拡大して検出されやすくする
        if (aspectRatio > 0.80) {
          score += (aspectRatio - 0.80).clamp(0.0, 0.20) / 0.20 * 0.6;
        }
        score += _applyDefaultPenalty(eyeShape, 0.7) * 0.3;
        score += _applyDefaultPenalty(noseHeight, 0.6) * 0.2;
        break;

      case '長方形顔':
        // 型固有のベーススコアは基本スコアに含まれているため削除
        // 長方形顔: アスペクト比が0.60-0.74、切れ長の目、立派な鼻
        // 範囲を拡大して検出されやすくする
        if (aspectRatio > 0.55 && aspectRatio < 0.80) {
          final center = 0.68;
          score += (1.0 - (aspectRatio - center).abs() * 3.0).clamp(0.0, 1.0) * 0.5;
        }
        score += _applyDefaultPenalty(eyeShape, 0.35) * 0.3;
        score += _applyDefaultPenalty(noseWidth, 0.35) * 0.2;
        score += _applyDefaultPenalty(mouthWidth, 0.35) * 0.1;
        // 丸顔の特徴が少ない場合のボーナス
        if (jawCurvature < 0.6 && cheekProminence < 0.6) score += 0.1;
        // 長方形の特徴が複数ある場合のボーナス
        int rectangularFeatures = 0;
        if (eyeShape > 0.35) rectangularFeatures++;
        if (noseWidth > 0.35) rectangularFeatures++;
        if (mouthWidth > 0.35) rectangularFeatures++;
        if (rectangularFeatures >= 3) score += 0.1;
        break;

      case '台座顔':
        // 型固有のベーススコアは基本スコアに含まれているため削除
        // 台座顔: アスペクト比が0.70-0.85、四角い形
        // 範囲を拡大して検出されやすくする
        if (aspectRatio > 0.65 && aspectRatio < 0.90) {
          final center = 0.775;
          score += (1.0 - (aspectRatio - center).abs() * 4.0).clamp(0.0, 1.0) * 0.5;
        }
        score += _applyDefaultPenalty(jawCurvature, 0.4) * 0.3;
        score += _applyDefaultPenalty(cheekProminence, 0.5) * 0.2;
        score += _applyDefaultPenalty(mouthWidth, 0.5) * 0.1;
        break;

      case '卵顔':
        // 型固有のベーススコアは基本スコアに含まれているため削除
        // 卵顔: アスペクト比が0.5-0.95、高い鼻、頬骨が張っている
        // 範囲を拡大して検出されやすくする
        if (aspectRatio > 0.5 && aspectRatio < 0.95) {
          final center = 0.725;
          score += (1.0 - (aspectRatio - center).abs() * 2.0).clamp(0.0, 1.0) * 0.5;
        }
        score += _applyDefaultPenalty(noseHeight, 0.5) * 0.3;
        score += _applyDefaultPenalty(cheekProminence, 0.5) * 0.2;
        score += _applyDefaultPenalty(jawCurvature, 0.5) * 0.1;
        score += _applyDefaultPenalty(eyeSize, 0.5) * 0.1;
        // 卵顔の特徴が複数ある場合のボーナス
        int ovalFeatures = 0;
        if (noseHeight > 0.5) ovalFeatures++;
        if (cheekProminence > 0.5) ovalFeatures++;
        if (jawCurvature > 0.5) ovalFeatures++;
        if (ovalFeatures >= 2) score += 0.2;
        break;

      case '四角顔':
        // 型固有のベーススコアは基本スコアに含まれているため削除
        // 四角顔: アスペクト比が0.55-0.95、角張っている
        // 範囲を拡大して検出されやすくする
        if (aspectRatio > 0.55 && aspectRatio < 0.95) {
          final center = 0.75;
          score += (1.0 - (aspectRatio - center).abs() * 2.5).clamp(0.0, 1.0) * 0.5;
        }
        score += _applyDefaultPenalty(jawCurvature, 0.3) * 0.3;
        score += _applyDefaultPenalty(cheekProminence, 0.3) * 0.2;
        score += _applyDefaultPenalty(noseWidth, 0.5) * 0.2;
        score += _applyDefaultPenalty(eyeSize, 0.3) * 0.1;
        // 四角顔の特徴が明確な場合のボーナス
        if (jawCurvature < 0.4 && cheekProminence < 0.4) score += 0.2;
        // 四角顔の特徴が複数ある場合のボーナス
        int squareFeatures = 0;
        if (jawCurvature < 0.4) squareFeatures++;
        if (cheekProminence < 0.4) squareFeatures++;
        if (aspectRatio > 0.65 && aspectRatio < 0.9) squareFeatures++;
        if (squareFeatures >= 2) score += 0.1;
        break;

      case '逆三角形顔':
        // 型固有のベーススコアは基本スコアに含まれているため削除
        // 逆三角形顔: 額が広く、顎が細い（foreheadJawRatio > 1.0）
        final foreheadWidth = _estimateForeheadWidth(face);
        final jawWidth = _estimateJawWidth(face);
        if (foreheadJawRatio > 1.0) {
          score += ((foreheadJawRatio - 1.0).clamp(0.0, 0.5) / 0.5) * 0.5;
        }
        score += _applyDefaultPenalty(foreheadWidth, 0.5) * 0.3;
        score += _applyDefaultPenalty(jawWidth, 0.3) * 0.2;
        // 逆三角形の特徴が明確な場合のボーナス
        if (foreheadJawRatio > 1.2) score += 0.2;
        // 逆三角形の特徴が複数ある場合のボーナス
        int invertedTriangleFeatures = 0;
        if (foreheadJawRatio > 1.1) invertedTriangleFeatures++;
        if (foreheadWidth > 0.5) invertedTriangleFeatures++;
        if (jawWidth < 0.4) invertedTriangleFeatures++;
        if (invertedTriangleFeatures >= 2) score += 0.1;
        break;

      case '三角形顔':
        // 型固有のベーススコアは基本スコアに含まれているため削除
        // 三角形顔: 額が狭く、顎が広い（foreheadJawRatio < 1.0）
        final foreheadWidth = _estimateForeheadWidth(face);
        final jawWidth = _estimateJawWidth(face);
        if (foreheadJawRatio < 1.0) {
          score += ((1.0 - foreheadJawRatio).clamp(0.0, 0.5) / 0.5) * 0.5;
        }
        score += _applyDefaultPenalty(foreheadWidth, 0.3) * 0.3;
        score += _applyDefaultPenalty(jawWidth, 0.6) * 0.2;
        score += _applyDefaultPenalty(jawCurvature, 0.6) * 0.1;
        score += _applyDefaultPenalty(noseWidth, 0.5) * 0.1;
        // 三角形の特徴が複数ある場合のボーナス
        int triangleFeatures = 0;
        if (foreheadJawRatio < 0.9) triangleFeatures++;
        if (jawWidth > 0.5) triangleFeatures++;
        if (jawCurvature > 0.5) triangleFeatures++;
        if (triangleFeatures >= 2) score += 0.2;
        if (foreheadJawRatio > 0.7 && foreheadJawRatio < 1.0) score += 0.1;
        break;
    }

    return score;
  }

  /// デフォルトペナルティを適用（値が閾値より大きい/小さい場合にスコアを追加）
  /// 改善: 閾値以下でも小さなスコアを追加して、すべての型が検出されるようにする
  static double _applyDefaultPenalty(double value, double threshold) {
    if (value > threshold) {
      return (value - threshold) / (1.0 - threshold);
    } else {
      // 閾値以下でも、値に応じて小さなボーナスを追加（すべての型が検出されるように）
      if (value < 0.05) {
        return 0.0; // 非常に小さい値は0
      } else {
        // 値に比例した小さなボーナス（負の値を避ける）
        return (value / threshold) * 0.3; // 閾値に対する比率に基づくボーナス
      }
    }
  }

  /// 顔の型の構成比率を取得
  static Map<String, double> _getTypeComposition(String faceType) {
    switch (faceType) {
      case '丸顔':
        return {'脂肪型': 1.0, '精神型': 0.0, '筋骨型': 0.0};
      case '細長顔':
        return {'脂肪型': 0.0, '精神型': 0.5, '筋骨型': 0.5};
      case '長方形顔':
        return {'脂肪型': 0.2, '精神型': 0.2, '筋骨型': 0.6};
      case '台座顔':
        return {'脂肪型': 0.6, '精神型': 0.4, '筋骨型': 0.0};
      case '卵顔':
        return {'脂肪型': 0.0, '精神型': 0.4, '筋骨型': 0.6};
      case '四角顔':
        return {'脂肪型': 0.0, '精神型': 0.0, '筋骨型': 1.0};
      case '逆三角形顔':
        return {'脂肪型': 0.0, '精神型': 1.0, '筋骨型': 0.0};
      case '三角形顔':
        return {'脂肪型': 0.6, '精神型': 0.0, '筋骨型': 0.4};
      default:
        return {'脂肪型': 0.33, '精神型': 0.33, '筋骨型': 0.34};
    }
  }

  // 特徴量抽出のヘルパーメソッド
  static double _estimateForeheadWidth(Face face) {
    // 額の幅を推定（目の位置から推定、Google ML Kitには眉のランドマークがないため）
    final landmarks = face.landmarks;
    final leftEye = landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = landmarks[FaceLandmarkType.rightEye]?.position;
    if (leftEye != null && rightEye != null) {
      // 目の間の距離から額の幅を推定（目の間の距離の1.5倍を額の幅として推定）
      final eyeDistance = (rightEye.x - leftEye.x).abs();
      final estimatedForeheadWidth = eyeDistance * 1.5;
      return (estimatedForeheadWidth / face.boundingBox.width).clamp(0.0, 1.0);
    }
    return 0.5; // デフォルト値
  }

  static double _estimateJawWidth(Face face) {
    // 顎の幅を推定（口の位置から）
    final landmarks = face.landmarks;
    final leftMouth = landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = landmarks[FaceLandmarkType.rightMouth]?.position;
    if (leftMouth != null && rightMouth != null) {
      final width = (rightMouth.x - leftMouth.x).abs();
      return (width / face.boundingBox.width).clamp(0.0, 1.0);
    }
    return 0.5; // デフォルト値
  }

  static double _estimateJawCurvature(Face face) {
    // 顎の曲率を推定（輪郭から）
    // 簡易実装: 顔の形状から推定
    final aspectRatio = face.boundingBox.height / face.boundingBox.width;
    return (1.0 - (aspectRatio - 0.75).abs() / 0.25).clamp(0.0, 1.0);
  }

  static double _estimateCheekProminence(Face face) {
    // 頬の突出度を推定
    final landmarks = face.landmarks;
    final leftCheek = landmarks[FaceLandmarkType.leftCheek]?.position;
    final rightCheek = landmarks[FaceLandmarkType.rightCheek]?.position;
    if (leftCheek != null && rightCheek != null) {
      final centerX = face.boundingBox.left + face.boundingBox.width / 2;
      final leftDist = (leftCheek.x - centerX).abs();
      final rightDist = (rightCheek.x - centerX).abs();
      final avgDist = (leftDist + rightDist) / 2;
      return (avgDist / face.boundingBox.width).clamp(0.0, 1.0);
    }
    return 0.5; // デフォルト値
  }

  static double _estimateEyeSize(Face face) {
    // 目のサイズを推定
    final landmarks = face.landmarks;
    final leftEye = landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = landmarks[FaceLandmarkType.rightEye]?.position;
    if (leftEye != null && rightEye != null) {
      final eyeDistance = (rightEye.x - leftEye.x).abs();
      return (eyeDistance / face.boundingBox.width).clamp(0.0, 1.0);
    }
    return 0.5; // デフォルト値
  }

  static double _estimateEyeShape(Face face) {
    // 目の形状を推定（切れ長かどうか）
    // 簡易実装: 目の幅と高さの比率
    return 0.5; // デフォルト値
  }

  static double _estimateNoseWidth(Face face) {
    // 鼻の幅を推定（利用可能なランドマークのみを使用）
    // Google ML KitにはleftNostril/rightNostrilがないため、noseBaseと目の位置から推定
    final landmarks = face.landmarks;
    final noseBase = landmarks[FaceLandmarkType.noseBase]?.position;
    final leftEye = landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = landmarks[FaceLandmarkType.rightEye]?.position;

    if (noseBase != null && leftEye != null && rightEye != null) {
      // 目の間の距離から鼻の幅を推定
      final eyeDistance = (rightEye.x - leftEye.x).abs();
      final estimatedNoseWidth = eyeDistance * 0.3; // 目の間の距離の30%を鼻の幅として推定
      return (estimatedNoseWidth / face.boundingBox.width).clamp(0.0, 1.0);
    }
    return 0.5; // デフォルト値
  }

  static double _estimateNoseHeight(Face face) {
    // 鼻の高さを推定（利用可能なランドマークのみを使用）
    // Google ML KitにはnoseTipがないため、noseBaseと目の位置から推定
    final landmarks = face.landmarks;
    final noseBase = landmarks[FaceLandmarkType.noseBase]?.position;
    final leftEye = landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = landmarks[FaceLandmarkType.rightEye]?.position;

    if (noseBase != null && leftEye != null && rightEye != null) {
      // 目の中心位置から鼻底までの距離を鼻の高さとして推定
      final eyeCenterY = (leftEye.y + rightEye.y) / 2;
      final estimatedNoseHeight = (noseBase.y - eyeCenterY).abs();
      return (estimatedNoseHeight / face.boundingBox.height).clamp(0.0, 1.0);
    }
    return 0.5; // デフォルト値
  }

  static double _estimateMouthWidth(Face face) {
    // 口の幅を推定
    final landmarks = face.landmarks;
    final leftMouth = landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = landmarks[FaceLandmarkType.rightMouth]?.position;
    if (leftMouth != null && rightMouth != null) {
      final width = (rightMouth.x - leftMouth.x).abs();
      return (width / face.boundingBox.width).clamp(0.0, 1.0);
    }
    return 0.5; // デフォルト値
  }

  static double _estimateEarlobeSize(Face face) {
    // 耳たぶのサイズを推定（簡易実装）
    return 0.5; // デフォルト値
  }
}
