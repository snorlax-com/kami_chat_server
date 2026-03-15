import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'face_type_classifier.dart';
import 'mediapipe_face_data.dart';
import 'router_tree_classifier.dart';

class TutorialDiagnosisResult {
  final String deityId;
  final String zone; // 上停/中停/下停
  final String polarity; // 陽/陰
  final String faceShape; // 丸/卵/角
  final String? faceType; // 人相学の顔の型（丸顔、細長顔など）
  final FaceTypeResult? faceTypeResult; // 顔の型分類の詳細結果
  final String reason;
  final Map<String, dynamic>? deityMeta; // title/trait/message
  final Map<String, dynamic>? detailedReason; // 詳細な判定根拠
  TutorialDiagnosisResult({
    required this.deityId,
    required this.zone,
    required this.polarity,
    required this.faceShape,
    this.faceType,
    this.faceTypeResult,
    required this.reason,
    this.deityMeta,
    this.detailedReason,
  });
}

class TutorialClassifier {
  static Future<Map<String, dynamic>> _loadGods() async {
    final txt = await rootBundle.loadString('assets/data/gods_tutorial.json');
    return json.decode(txt) as Map<String, dynamic>;
  }

  /// 眉の曲線度を計算（ML Kit用：実際の座標）
  /// 眉のランドマークポイント全体を使って、直線からの偏差を計算
  /// これにより、眉山の位置に関係なく、眉全体の曲線度を正確に評価できる
  static double _calculateBrowCurvature(List<ui.Offset> browPoints, ui.Rect box) {
    if (browPoints.length < 3) return 0.5; // 少なくとも3点必要

    // 眉頭と眉尻を結ぶ直線を基準とする
    final startPoint = browPoints.first;
    final endPoint = browPoints.last;

    // 直線の傾きと切片を計算 (y = mx + b)
    final dx = endPoint.dx - startPoint.dx;
    if (dx.abs() < 1e-6) {
      // 垂直線の場合は、X座標からの偏差を計算
      double totalDeviation = 0.0;
      for (int i = 1; i < browPoints.length - 1; i++) {
        totalDeviation += (browPoints[i].dx - startPoint.dx).abs();
      }
      final avgDeviation = totalDeviation / (browPoints.length - 2);
      final browWidth = box.width;
      if (browWidth < 1e-6) return 0.5;
      // 偏差を眉の幅で正規化し、0.0-1.0の範囲にマッピング
      // 実際のテストに基づいて調整：偏差が眉の幅の5%以上で曲線的と判定
      // スケーリング係数をさらに調整して、アーチ型が多すぎないようにする
      return ((avgDeviation / browWidth) * 10.0).clamp(0.0, 0.9); // 15.0から10.0にさらに調整、最大値を0.9に制限
    }

    final dy = endPoint.dy - startPoint.dy;
    final m = dy / dx; // 傾き
    final b = startPoint.dy - m * startPoint.dx; // 切片

    // 中間のランドマークポイントから基準直線までの垂直距離を計算
    double totalDeviation = 0.0;
    int count = 0;

    for (int i = 1; i < browPoints.length - 1; i++) {
      final point = browPoints[i];
      // 直線上の対応するY座標
      final expectedY = m * point.dx + b;
      // 垂直距離（偏差）
      final deviation = (point.dy - expectedY).abs();
      totalDeviation += deviation;
      count++;
    }

    if (count == 0) return 0.5;

    final averageDeviation = totalDeviation / count;

    // 眉の幅で正規化（顔の幅でも良い）
    final browWidth = (endPoint.dx - startPoint.dx).abs();
    if (browWidth < 1e-6) return 0.5;

    // 偏差を眉の幅で正規化
    // 実際のテストに基づいて調整：偏差が眉の幅の2%以上で曲線的と判定
    // より曲線的な眉（偏差が大きい）ほど高い値になるようにスケーリング
    // スケーリング係数をさらに調整して、アーチ型が多すぎないようにする
    // 標準的な眉の偏差は眉の幅の1-3%程度なので、より適切なスケーリングに調整
    // 直線的な眉が正しく「中（直線的）」と判定されるように、スケーリング係数をさらに下げる
    final normalizedCurvature = (averageDeviation / browWidth) * 8.0; // 10.0から8.0にさらに調整

    // 0.0から1.0の範囲にクランプ（極端な値を防ぐ）
    final result = normalizedCurvature.clamp(0.0, 0.85); // 最大値を0.85に制限

    // デバッグログ（実際の値を確認）
    print(
        '[眉の形状計算(ML Kit)] averageDeviation: ${averageDeviation.toStringAsFixed(4)}, browWidth: ${browWidth.toStringAsFixed(4)}, normalizedCurvature: ${normalizedCurvature.toStringAsFixed(4)}, result: ${result.toStringAsFixed(4)}');

    return result;
  }

  /// 眉の曲線度を計算（MediaPipe用：正規化された座標 0.0-1.0）
  /// 眉のランドマークポイント全体を使って、直線からの偏差を計算
  /// これにより、眉山の位置に関係なく、眉全体の曲線度を正確に評価できる
  static double _calculateBrowCurvatureNormalized(List<ui.Offset> browPoints) {
    if (browPoints.length < 3) return 0.5; // 少なくとも3点必要

    // 眉頭と眉尻を結ぶ直線を基準とする
    final startPoint = browPoints.first;
    final endPoint = browPoints.last;

    // 直線の傾きと切片を計算 (y = mx + b)
    final dx = endPoint.dx - startPoint.dx;
    if (dx.abs() < 1e-6) {
      // 垂直線の場合は、X座標からの偏差を計算
      double totalDeviation = 0.0;
      for (int i = 1; i < browPoints.length - 1; i++) {
        totalDeviation += (browPoints[i].dx - startPoint.dx).abs();
      }
      final avgDeviation = totalDeviation / (browPoints.length - 2);
      final browWidth = (endPoint.dx - startPoint.dx).abs();
      if (browWidth < 1e-6) return 0.5;
      // 偏差を眉の幅で正規化し、0.0-1.0の範囲にマッピング
      // 正規化された座標（0.0-1.0）なので、スケーリングを調整
      // 実際のテストに基づいて調整：偏差が眉の幅の5%以上で曲線的と判定
      // スケーリング係数を調整して、極端な値（1.00など）が出ないようにする
      // 直線的な眉が正しく「中（直線的）」と判定されるように、スケーリング係数をさらに下げる
      final result = ((avgDeviation / browWidth) * 12.0).clamp(0.0, 0.85); // 15.0から12.0に調整、最大値を0.85に制限

      // デバッグログ（実際の値を確認）
      print(
          '[眉の形状計算(MediaPipe-垂直)] avgDeviation: ${avgDeviation.toStringAsFixed(4)}, browWidth: ${browWidth.toStringAsFixed(4)}, result: ${result.toStringAsFixed(4)}');

      return result;
    }

    final dy = endPoint.dy - startPoint.dy;
    final m = dy / dx; // 傾き
    final b = startPoint.dy - m * startPoint.dx; // 切片

    // 中間のランドマークポイントから基準直線までの垂直距離を計算
    double totalDeviation = 0.0;
    int count = 0;

    for (int i = 1; i < browPoints.length - 1; i++) {
      final point = browPoints[i];
      // 直線上の対応するY座標
      final expectedY = m * point.dx + b;
      // 垂直距離（偏差）
      final deviation = (point.dy - expectedY).abs();
      totalDeviation += deviation;
      count++;
    }

    if (count == 0) return 0.5;

    final averageDeviation = totalDeviation / count;

    // 眉の幅で正規化（正規化された座標なので、そのまま使用）
    final browWidth = (endPoint.dx - startPoint.dx).abs();
    if (browWidth < 1e-6) return 0.5;

    // 偏差を眉の幅で正規化
    // 正規化された座標（0.0-1.0）なので、スケーリングを調整
    // 実際のテストに基づいて調整：偏差が眉の幅の2%以上で曲線的と判定
    // より曲線的な眉（偏差が大きい）ほど高い値になるようにスケーリング
    // スケーリング係数をさらに調整して、アーチ型が多すぎないようにする
    // 標準的な眉の偏差は眉の幅の1-3%程度なので、より適切なスケーリングに調整
    // 直線的な眉が正しく「中（直線的）」と判定されるように、スケーリング係数をさらに下げる
    final normalizedCurvature = (averageDeviation / browWidth) * 8.0; // 10.0から8.0にさらに調整

    // 0.0から1.0の範囲にクランプ（極端な値を防ぐ）
    final result = normalizedCurvature.clamp(0.0, 0.85); // 最大値を0.85に制限

    // デバッグログ（実際の値を確認）
    print(
        '[眉の形状計算(MediaPipe)] averageDeviation: ${averageDeviation.toStringAsFixed(4)}, browWidth: ${browWidth.toStringAsFixed(4)}, normalizedCurvature: ${normalizedCurvature.toStringAsFixed(4)}, result: ${result.toStringAsFixed(4)}');

    return result;
  }

  static double _gradientScore(double value) {
    value = value.clamp(0.0, 1.0);
    if (value < 0.3) {
      // 0.0〜0.3：徐々に減点（0点〜0.5点）
      return (value / 0.3) * 0.5;
    } else if (value <= 0.7) {
      // 0.3〜0.7：比例スコア（0.5点〜1.0点）
      return 0.5 + ((value - 0.3) / (0.7 - 0.3)) * 0.5;
    } else {
      // 0.7〜1.0：徐々に加点（最大1.0点）
      // 0.7で1.0、1.0でも1.0（上限）
      return 1.0;
    }
  }

  /// 標準偏差を計算
  static double _calculateStdDev(List<double> values) {
    if (values.isEmpty) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
    return math.sqrt(variance);
  }

  /// 顔全体の調和度を計算
  /// harmony = 1 - std（標準偏差が小さいほど調和が取れている）
  static double _calculateHarmony(List<double> featureScores) {
    if (featureScores.isEmpty) return 0.0;
    final std = _calculateStdDev(featureScores);
    return (1.0 - std.clamp(0.0, 1.0)).clamp(0.0, 1.0);
  }

  // 【眉を最優先】眉の特徴から直接性格診断を行う（新しいフロー・改良版）
  static Future<TutorialDiagnosisResult> diagnose(Face face, {double imageBrightness = 0.6}) async {
    // ===== ステップ1: 眉の特徴を抽出（最優先） =====
    final browFeatures = extractBrowFeaturesAdvanced(face);
    final browAngle = browFeatures['angle'] ?? 0.0;
    final browLength = browFeatures['length'] ?? 0.5;
    final browThickness = browFeatures['thickness'] ?? 0.5;
    final browShape = browFeatures['shape'] ?? 0.5;
    final glabellaWidth = browFeatures['glabellaWidth'] ?? 0.5;
    final browNeatness = browFeatures['neatness'] ?? 0.5;

    // ===== ステップ2: 眉の特徴から直接候補を振り分け =====
    final browCandidates = _getBrowCandidates(
      browAngle,
      browLength,
      browThickness,
      browShape,
      glabellaWidth,
      browNeatness,
    );

    // ===== ステップ3: 目の特徴を抽出（第2優先・MediaPipe Face Mesh統合版） =====
    final eyeFeatures = extractEyeFeaturesForDiagnosis(face);
    final eyeBalance = eyeFeatures['balance'] ?? 0.5;
    final eyeSize = eyeFeatures['size'] ?? 0.5;
    final eyeShape = eyeFeatures['shape'] ?? 0.5;

    // ===== ステップ4: 口の大きさを判定（第3優先・人相学の本から学習） =====
    // 両目の瞳孔の内側の角から下に引いた線の幅を標準として判定
    final mouthSize = estimateMouthSizeStandard(face);

    // ===== ステップ5: 顔の形を判定（第4優先） =====
    final actualFaceShape = _estimateFaceShapeAdvanced(face); // 実際の顔形

    // ===== ステップ6: その他の特徴を抽出（補正用） =====
    // 注: 以下の変数は将来の拡張用に保持（現在は未使用）
    // final actualZone = _estimateZoneAdvanced(face);
    // final jawCurvature = _estimateJawCurvatureAdvanced(face);
    // final mouthWidth = _estimateMouthWidth(face);
    // final noseShape = _estimateNoseShape(face);
    // final cheekProminence = _estimateCheekProminence(face);
    // final foreheadWidth = _estimateForeheadWidth(face);

    // 人相学の顔の型を判定（補正用）
    final faceTypeResult = FaceTypeClassifier.classify(face);
    final faceType = faceTypeResult.faceType;
    final faceTypeCandidates = _getFaceTypeCandidates(faceType, faceTypeResult);
    final faceTypeConfidence = faceTypeResult.confidence;
    final useFaceTypePriority = faceTypeConfidence > 0.5;

    // ===== ステップ7: 目の特徴から候補を追加（第2優先） =====
    final eyeCandidates = _getEyeCandidates(eyeBalance, eyeSize, eyeShape);

    // 修正: 眉が曲線的（browShape > 0.6）の場合、Verdatsuを候補から除外
    // Verdatsuは眉が直線的（browShape < 0.3）の場合のみ選ばれるべき
    if (browShape > 0.6 && eyeCandidates.contains('Verdatsu')) {
      eyeCandidates.remove('Verdatsu');
    }

    // ===== ステップ8: 口の大きさから候補を追加（第3優先） =====
    final mouthCandidates = _getMouthSizeCandidates(mouthSize);

    // ===== ステップ9: ハイブリッド判定（樹形図ルーティング + スコアベース） =====
    // まず樹形図ルーティングで候補を絞り込み、その後スコアベースで最終選択

    // 樹形図ルーティングで候補を取得
    final routerResult = RouterTreeClassifier.diagnose(face);
    final routerCandidates = RouterTreeClassifier.getCandidates(face);

    // 候補が空の場合は全柱を候補とする
    final finalCandidates = routerCandidates.isNotEmpty
        ? routerCandidates
        : [
            'Amatera',
            'Yatael',
            'Skura',
            'Delphos',
            'Amanoira',
            'Noirune',
            'Ragias',
            'Verdatsu',
            'Osiria',
            'Fatemis',
            'Kanonis',
            'Sylna',
            'Yorusi',
            'Tenkora',
            'Shisaru',
            'Mimika',
            'Tenmira',
            'Shiran'
          ];

    // グラデーション補間式によるスコア計算（改良版）
    // 基本スコアの重みバランス（均等化）
    // 顔の形（卵・角など）の判断基準は削除し、顔の型（8種類）のみを使用
    const double browWeight = 1.0; // 眉（均等化）
    const double eyeWeight = 1.0; // 目（均等化）
    const double mouthWeight = 1.0; // 口（均等化）
    const double otherWeight = 0.8; // その他（補助的、変更なし）

    // 樹形図ルーティングで絞り込んだ候補のみスコアを計算
    final scores = <String, double>{};
    for (final id in finalCandidates) {
      scores[id] = 0.0; // 初期化
    }

    // 各候補に対してグラデーション補間式でスコアを計算
    // 【重要】樹形図ルーティングで絞り込んだ候補のみスコアを計算
    // 【再構成】複合条件を優先的に評価し、判断基準を統合
    for (final id in finalCandidates) {
      double totalScore = 0.0;
      final featureScores = <double>[]; // 調和度計算用

      // 【最優先】眉と目の複合条件スコア（マークダウンファイルの判定基準に基づく）
      final eyeBrowCompositeScore = _calculateEyeBrowCompositeScore(id, browAngle, browLength, browThickness, browShape,
          glabellaWidth, browNeatness, eyeBalance, eyeSize, eyeShape);
      if (eyeBrowCompositeScore > 0.0) {
        featureScores.add(eyeBrowCompositeScore);
        // 複合条件は重みを大きく（眉と目の重みの合計）
        totalScore += eyeBrowCompositeScore * (browWeight + eyeWeight);
      }

      // 【第2優先】眉の複合条件スコア（眉の特徴のみの複合条件）
      final browCompositeScore =
          _getBrowCompositeScore(id, browAngle, browLength, browThickness, browShape, glabellaWidth, browNeatness);
      if (browCompositeScore > 0.0 && eyeBrowCompositeScore == 0.0) {
        // 眉と目の複合条件がない場合のみ評価
        featureScores.add(browCompositeScore);
        totalScore += browCompositeScore * browWeight;
      }

      // 【第3優先】目の複合条件スコア（目の特徴のみの複合条件）
      final eyeCompositeScore = _calculateEyeCompositeScore(id, eyeBalance, eyeSize, eyeShape);
      if (eyeCompositeScore > 0.0 && eyeBrowCompositeScore == 0.0) {
        // 眉と目の複合条件がない場合のみ評価
        featureScores.add(eyeCompositeScore);
        totalScore += eyeCompositeScore * eyeWeight;
      }

      // 【第4優先】個別の特徴スコア（複合条件がない場合のみ評価）
      if (eyeBrowCompositeScore == 0.0 && browCompositeScore == 0.0) {
        // 眉の特徴スコア（すべての柱が計算）
        final browScore =
            _calculateBrowScore(id, browAngle, browLength, browThickness, browShape, glabellaWidth, browNeatness);
        if (browScore > 0.0) {
          featureScores.add(browScore);
          totalScore += browScore * browWeight;
        }
      }

      if (eyeBrowCompositeScore == 0.0 && eyeCompositeScore == 0.0) {
        // 目の特徴スコア（すべての柱が計算）
        final eyeScore = _calculateEyeScore(id, eyeBalance, eyeSize, eyeShape);
        if (eyeScore > 0.0) {
          featureScores.add(eyeScore);
          totalScore += eyeScore * eyeWeight;
        }
      }

      // 口の大きさスコア（すべての柱が計算、常に評価）
      final mouthScore = _calculateMouthScore(id, mouthSize);
      if (mouthScore > 0.0) {
        featureScores.add(mouthScore);
        totalScore += mouthScore * mouthWeight;
      }

      // 顔の型スコア（すべての柱が計算）
      if (useFaceTypePriority) {
        final faceTypeScore = _calculateFaceTypeScore(id, faceType, faceTypeConfidence);
        if (faceTypeScore > 0.0) {
          featureScores.add(faceTypeScore);
          totalScore += faceTypeScore * otherWeight;
        }
      }

      // 顔全体の調和度を計算
      double harmony = 0.0;
      if (featureScores.length > 1) {
        harmony = _calculateHarmony(featureScores);
        totalScore += harmony * 0.2; // 調和度補正
      }

      scores[id] = totalScore;
    }

    // ===== ステップ10: ペナルティを削除（すべての神を公平に判定） =====
    // ペナルティをすべて削除し、純粋に特徴のみで判定

    // 三停・陰陽を計算（結果表示用のみ、判定には使用しない）
    final zone = _estimateZoneAdvanced(face);
    final polarity = _estimatePolarityAdvanced(face);

    // スコアをソートして、最高スコアの神を選択（三停・陰陽は使用しない）
    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // 常に最高スコアの神を選ぶ（三停・陰陽による選択を排除）
    String best = sorted.first.key;

    // Yorusiが選ばれた場合、他の候補とのスコア差が小さい場合は再選択
    // ただし、ランダム要素を削除して決定論的に選択
    if (best == 'Yorusi' && sorted.length > 1) {
      final yorusiIndex = sorted.indexWhere((e) => e.key == 'Yorusi');
      if (yorusiIndex >= 0 && yorusiIndex < sorted.length - 1) {
        final yorusiScore = sorted[yorusiIndex].value;
        final secondScore = sorted[yorusiIndex + 1].value;
        final scoreDiff = yorusiScore - secondScore;

        // スコア差が0.05以内の場合は、2番目に高いスコアの神を選ぶ（決定論的）
        if (scoreDiff < 0.05) {
          final otherCandidates = sorted.where((e) => e.key != 'Yorusi').take(1).toList();
          if (otherCandidates.isNotEmpty) {
            best = otherCandidates.first.key; // ランダムではなく、2番目を選ぶ
          }
        }
        // スコア差が大きい場合は、Yorusiをそのまま選ぶ（ランダム要素を削除）
      }
    }

    // 実際の三停・陰陽・顔形を計算（結果表示用、既に計算済み）
    final faceShape = actualFaceShape;

    // 注: ランキングは将来の拡張用に保持（現在は未使用）
    // final ranking = sorted.take(5).map((e) => {
    //   'god': e.key,
    //   'score': e.value,
    // }).toList();

    // 判定理由を配列形式で作成
    final reasons = <String>[];
    if (browCandidates.contains(best)) {
      reasons.add('眉の特徴が高い');
    }
    if (eyeCandidates.contains(best)) {
      reasons.add('目の特徴が高い');
    }
    if (mouthCandidates.contains(best)) {
      reasons.add('口の大きさが特徴的');
    }

    // 調和度が高い場合
    final allFeatureScores = [
      TutorialClassifier._gradientScore((browAngle + 1.0) / 2.0),
      TutorialClassifier._gradientScore(browLength),
      TutorialClassifier._gradientScore(browThickness),
      TutorialClassifier._gradientScore(browShape),
      TutorialClassifier._gradientScore(glabellaWidth),
      TutorialClassifier._gradientScore(browNeatness),
      TutorialClassifier._gradientScore(eyeBalance),
      TutorialClassifier._gradientScore(eyeSize),
      TutorialClassifier._gradientScore(eyeShape),
      TutorialClassifier._gradientScore(mouthSize),
    ];
    final harmony = _calculateHarmony(allFeatureScores);
    if (harmony > 0.7) {
      reasons.add('顔全体の調和が良い');
    }

    // 理由が空の場合はデフォルトメッセージ
    if (reasons.isEmpty) {
      reasons.add('総合的な判定');
    }

    // 詳細な判定根拠を生成
    final bestScore = scores[best] ?? 0.0;
    final bestIndex = sorted.indexWhere((e) => e.key == best);
    final secondScore = bestIndex < sorted.length - 1 ? sorted[bestIndex + 1].value : 0.0;
    final scoreDiff = bestScore - secondScore;

    // 各柱のスコアを取得（実際の計算ロジックに合わせる）
    double bestBrowScore = 0.0;
    if (browCandidates.contains(best)) {
      final browAngleScore = TutorialClassifier._gradientScore((browAngle + 1.0) / 2.0);
      final browLengthScore = TutorialClassifier._gradientScore(browLength);
      final browThicknessScore = TutorialClassifier._gradientScore(browThickness);
      final browShapeScore = TutorialClassifier._gradientScore(browShape);
      final glabellaWidthScore = TutorialClassifier._gradientScore(glabellaWidth);
      final browNeatnessScore = TutorialClassifier._gradientScore(browNeatness);
      final avgBrowScore = (browAngleScore +
              browLengthScore +
              browThicknessScore +
              browShapeScore +
              glabellaWidthScore +
              browNeatnessScore) /
          6.0;
      bestBrowScore = avgBrowScore * browWeight;
    }

    double bestEyeScore = 0.0;
    if (eyeCandidates.contains(best)) {
      final eyeBalanceScore = TutorialClassifier._gradientScore(eyeBalance);
      final eyeSizeScore = TutorialClassifier._gradientScore(eyeSize);
      final eyeShapeScore = TutorialClassifier._gradientScore(eyeShape);
      final avgEyeScore = (eyeBalanceScore + eyeSizeScore + eyeShapeScore) / 3.0;
      bestEyeScore = avgEyeScore * eyeWeight;
    }

    final bestMouthScore =
        mouthCandidates.contains(best) ? TutorialClassifier._gradientScore(mouthSize) * mouthWeight : 0.0;
    // 顔の形（卵・角など）の判断基準は削除し、顔の型（8種類）のみを使用
    const bestFaceShapeScore = 0.0;
    final bestFaceTypeScore = (useFaceTypePriority && faceTypeCandidates.contains(best))
        ? TutorialClassifier._gradientScore(faceTypeConfidence) * otherWeight
        : 0.0;
    final bestHarmonyScore = harmony * 0.2;

    // ペナルティを取得
    double penalty = 0.0;
    if (best == 'Tenkora') penalty = 0.05;
    if (best == 'Shisaru') penalty = 0.05;
    if (best == 'Yorusi') penalty = 0.10;
    if (best == 'Fatemis') penalty = 0.08;
    if (best == 'Amatera') penalty = 0.20;
    if (best == 'Delphos') penalty = 0.10;
    if (best == 'Yatael') penalty = 0.25;
    if (best == 'Osiria') penalty = 0.2;
    if (best == 'Skura') penalty = 0.3;
    if (best == 'Kanonis' || best == 'Sylna') penalty = 0.15;
    if (best == 'Ragias') penalty = 0.15;

    final detailedReason = <String, dynamic>{
      // 各特徴の生の値
      'features': {
        'brow': {
          'angle': browAngle.toStringAsFixed(3),
          'length': browLength.toStringAsFixed(3),
          'thickness': browThickness.toStringAsFixed(3),
          'shape': browShape.toStringAsFixed(3),
          'glabellaWidth': glabellaWidth.toStringAsFixed(3),
          'neatness': browNeatness.toStringAsFixed(3),
        },
        'eye': {
          'balance': eyeBalance.toStringAsFixed(3),
          'size': eyeSize.toStringAsFixed(3),
          'shape': eyeShape.toStringAsFixed(3),
        },
        'mouth': {
          'size': mouthSize.toStringAsFixed(3),
        },
        'faceShape': '', // 顔の形（卵・角など）の判断基準は削除（結果表示用のみ）
        'faceType': faceType,
        'faceTypeConfidence': faceTypeConfidence.toStringAsFixed(3),
      },
      // 候補に含まれたかどうか
      'candidates': {
        'brow': browCandidates.contains(best),
        'eye': eyeCandidates.contains(best),
        'mouth': mouthCandidates.contains(best),
        'faceShape': false, // 顔の形（卵・角など）の判断基準は削除
        'faceType': useFaceTypePriority && faceTypeCandidates.contains(best),
      },
      // 各特徴のスコア
      'scores': {
        'brow': bestBrowScore.toStringAsFixed(3),
        'eye': bestEyeScore.toStringAsFixed(3),
        'mouth': bestMouthScore.toStringAsFixed(3),
        'faceShape': bestFaceShapeScore.toStringAsFixed(3),
        'faceType': bestFaceTypeScore.toStringAsFixed(3),
        'harmony': bestHarmonyScore.toStringAsFixed(3),
        'totalBeforePenalty': (bestScore + penalty).toStringAsFixed(3),
        'penalty': penalty.toStringAsFixed(3),
        'final': bestScore.toStringAsFixed(3),
      },
      // 調和度
      'harmony': harmony.toStringAsFixed(3),
      // スコア差
      'scoreDifference': scoreDiff.toStringAsFixed(3),
      // 上位3位のスコア
      'topScores': sorted
          .take(3)
          .map((e) => {
                'deity': e.key,
                'score': e.value.toStringAsFixed(3),
              })
          .toList(),
    };

    final gods = await _loadGods();

    // 樹形図ルーティングの情報を判定理由に追加
    final hybridReasons = <String>[];
    if (routerResult.route.isNotEmpty) {
      hybridReasons.add('ルート: ${routerResult.route.join(" → ")}');
    }
    hybridReasons.addAll(reasons);

    final reason = hybridReasons.join('、');

    // 詳細な判定根拠に樹形図ルーティング情報を追加
    if (detailedReason != null) {
      detailedReason['routerTree'] = {
        'pillar': routerResult.pillar,
        'confidence': routerResult.confidence,
        'route': routerResult.route,
        'usedFeatures': routerResult.usedFeatures,
        'reason': routerResult.reason,
      };
    }

    return TutorialDiagnosisResult(
      deityId: best,
      zone: zone,
      polarity: polarity,
      faceShape: faceShape,
      faceType: faceType,
      faceTypeResult: faceTypeResult,
      reason: reason,
      deityMeta: gods[best] as Map<String, dynamic>?,
      detailedReason: detailedReason,
    );
  }

  /// 眉の特徴から顔形を推定
  /// 眉の形状や角度から、丸/卵/角を推定
  static String _estimateFaceShapeFromBrow(double browShape, double browAngle, double browThickness) {
    // 眉が曲線 → 丸顔（柔軟、円満）
    if (browShape > 0.7) {
      return '丸';
    }
    // 眉が直線 + 眉が上がっている → 角顔（意志が強い、頑固）
    if (browShape < 0.3 && browAngle > 0.2) {
      return '角';
    }
    // 眉が直線 + 眉が濃い → 角顔（積極的、決断力）
    if (browShape < 0.3 && browThickness > 0.7) {
      return '角';
    }
    // デフォルトは卵顔（バランス型）
    return '卵';
  }

  /// 目の特徴から候補を振り分け（第2優先）
  static List<String> _getEyeCandidates(double eyeBalance, double eyeSize, double eyeShape) {
    final candidates = <String>[];

    // 目のバランスが良い → 陽の特徴
    // 極端な特徴のみ判定（非常に良い >0.85 のみ、普通のバランスはスキップ）
    // Amateraはより厳しい条件でのみ追加（目のバランスが非常に良い + 目が大きい）
    if (eyeBalance > 0.85 && eyeSize > 0.7) {
      candidates.addAll(['Amatera']);
    }
    // Yataelはより厳しい条件でのみ追加（目のバランスが非常に良い + 目が大きい）
    if (eyeBalance > 0.85 && eyeSize > 0.8) {
      candidates.addAll(['Yatael']);
    }
    // Osiriaはより厳しい条件でのみ追加（目のバランスが非常に良い + 目が大きい）
    if (eyeBalance > 0.85 && eyeSize > 0.75) {
      candidates.addAll(['Osiria']);
    }
    // Skuraはより厳しい条件でのみ追加（目のバランスが非常に良い）
    if (eyeBalance > 0.8 && eyeSize > 0.75) {
      candidates.addAll(['Skura', 'Kanonis', 'Sylna']);
    }

    // 目のバランスが悪い → 陰の特徴
    // 極端な特徴のみ判定（悪い <0.35 のみ、普通のバランスはスキップ）
    if (eyeBalance < 0.35) {
      candidates.addAll(['Noirune', 'Mimika', 'Sylna']);
    }

    // 目が大きい → 陽の特徴
    // 極端な特徴のみ判定（非常に大きい >0.85 のみ、普通のサイズはスキップ）
    // Amateraはより厳しい条件でのみ追加（目が非常に大きい + 目のバランスが良い）
    if (eyeSize > 0.8 && eyeBalance > 0.75) {
      candidates.addAll(['Amatera']);
    }
    // Yataelはより厳しい条件でのみ追加（目が非常に大きい + 目のバランスが非常に良い）
    if (eyeSize > 0.85 && eyeBalance > 0.85) {
      candidates.addAll(['Yatael']);
    }
    // Osiriaはより厳しい条件でのみ追加（目が非常に大きい + 目のバランスが非常に良い）
    if (eyeSize > 0.85 && eyeBalance > 0.8) {
      candidates.addAll(['Osiria']);
    }
    // Skuraはより厳しい条件でのみ追加（目が非常に大きい + 目のバランスが非常に良い）
    if (eyeSize > 0.85 && eyeBalance > 0.8) {
      candidates.addAll(['Skura']);
    }

    // 目が小さい → 陰の特徴
    // 極端な特徴のみ判定（小さい <0.3 のみ、普通のサイズはスキップ）
    if (eyeSize < 0.3) {
      candidates.addAll(['Noirune', 'Mimika', 'Sylna', 'Kanonis']);
    }

    // 切れ長の目 → 知的、決断力がある
    // 極端な特徴のみ判定（非常に切れ長 >0.95 のみ、普通の形状はスキップ）
    // 判断基準を厳しくする（0.9 → 0.95）
    // FatemisとDelphosはより厳しい条件でのみ追加（目が非常に切れ長）
    // Ragiasは眉の特徴と組み合わせて判定されるため、ここでは追加しない（_getEyeBrowCandidatesで判定）
    if (eyeShape > 0.95) {
      candidates.addAll(['Verdatsu', 'Fatemis', 'Delphos', 'Amanoira']);
    }

    return candidates.toSet().toList();
  }

  /// 口の大きさから候補を振り分け（第3優先・人相学の本から学習）
  static List<String> _getMouthSizeCandidates(double mouthSize) {
    final candidates = <String>[];

    // 口が大きい → 本能や欲望が強い、明るく開放的、社会性がある、心が広い、度量がある、生命力にあふれている
    // 極端な特徴のみ判定（非常に大きい >0.8 のみ、普通のサイズはスキップ）
    // Amateraはより厳しい条件でのみ追加（口が非常に大きい）
    if (mouthSize > 0.75) {
      candidates.addAll(['Kanonis', 'Sylna', 'Amatera']);
    }
    // Yataelはより厳しい条件でのみ追加（口が非常に大きい）
    if (mouthSize > 0.8) {
      candidates.addAll(['Yatael', 'Skura']);
    }

    // 口が小さい → 素直で誠実、臆病、夢や希望が小さい、神経質、慎重、心配性、受動的、実行力に欠ける、しかし誠実で丁寧、細かい、美的感覚が鋭い
    // 極端な特徴のみ判定（非常に小さい <0.25 のみ、普通のサイズはスキップ）
    // FatemisとDelphosはより厳しい条件でのみ追加（口が非常に小さい）
    if (mouthSize < 0.25) {
      candidates.addAll(['Delphos', 'Amanoira', 'Fatemis', 'Noirune', 'Mimika']);
    }

    return candidates.toSet().toList();
  }

  /// 顔の形から候補を振り分け（第4優先）
  static List<String> _getFaceShapeCandidates(String faceShape) {
    switch (faceShape) {
      case '丸':
        // AmateraとSkuraは削除（他の条件で十分に選ばれるため）
        // Yataelは条件を厳しくするため、ここでは追加しない（他の厳しい条件でのみ追加）
        return ['Sylna', 'Kanonis', 'Noirune', 'Mimika', 'Shiran'];
      case '角':
        // FatemisとDelphosは削除（他の条件で十分に選ばれるため）
        // Ragiasはより厳しい条件でのみ追加（角顔 + 眉が右上がり + 眉が直線的 + 眉が太い）
        return ['Verdatsu', 'Amanoira', 'Fatemis', 'Tenkora', 'Shisaru'];
      case '卵':
        // AmateraとOsiriaは削除（他の条件で十分に選ばれるため）
        // Yataelは条件を厳しくするため、ここでは追加しない（他の厳しい条件でのみ追加）
        return ['Kanonis', 'Sylna', 'Yorusi', 'Tenmira'];
      default:
        return [];
    }
  }

  /// 眉の特徴から直接候補を振り分け（眉を最優先・人相学の本から学習した詳細な判定）
  /// 眉の特徴のみで候補を振り分ける（目は補助的）
  static List<String> _getBrowCandidates(
    double browAngle,
    double browLength,
    double browThickness,
    double browShape,
    double glabellaWidth,
    double browNeatness,
  ) {
    final candidates = <String>[];

    // 【人相学の本から学習】眉尻が上がっている → 気性が激しい、積極的、合理的、決断力、数字に強い
    if (browAngle > 0.2) {
      // 眉が右上がり → 積極的、明るい性格
      // Amateraは削除（他の条件で十分に選ばれるため）
      candidates.addAll(['Yatael', 'Ragias', 'Delphos', 'Tenkora']);
      // 【学習】眉が太い + 右上がり → 決断力、実行力、積極的（男性的）
      // FatemisとAmateraはより厳しい条件でのみ追加（眉が非常に太い + 眉が直線的）
      if (browThickness > 0.8 && browShape < 0.2) {
        candidates.addAll(['Ragias', 'Fatemis', 'Verdatsu', 'Amatera']);
      } else if (browThickness > 0.7 && browShape < 0.3) {
        candidates.addAll(['Ragias', 'Fatemis', 'Verdatsu']);
      } else if (browThickness > 0.6) {
        candidates.addAll(['Ragias', 'Verdatsu']);
      }
      // 【学習】へ字眉（眉が直線的で右上がり） → 職人気質、情熱的、実行力
      // Fatemisはより厳しい条件でのみ追加（眉が非常に直線的 + 眉が非常に上がっている）
      if (browShape < 0.2 && browAngle > 0.4) {
        candidates.addAll(['Ragias', 'Fatemis', 'Verdatsu']);
      } else if (browShape < 0.3 && browAngle > 0.3) {
        candidates.addAll(['Ragias', 'Verdatsu']);
      }
    }

    // 【人相学の本から学習】眉尻が下がっている → 人柄が良い、消極的、平和主義、面倒見が良い
    if (browAngle < -0.2) {
      // 眉が右下がり → 内向的、冷静な性格
      // Delphosは削除（他の条件で十分に選ばれるため）
      candidates.addAll(['Noirune', 'Mimika', 'Sylna', 'Kanonis', 'Amanoira']);
      // 【学習】八字眉（眉尻が大きく下がる） → 度量が広い、陽気、お調子者、要領が良い
      // Skuraはより厳しい条件でのみ追加（八字眉 + 口が大きい）
      if (browAngle < -0.3 && browThickness > 0.5) {
        candidates.addAll(['Sylna', 'Kanonis', 'Yatael']);
      }
    }

    // 【人相学の本から学習】眉が水平 → バランス型
    // 極端な特徴のみ判定（非常に水平 -0.1~0.1 のみ、普通の角度はスキップ）
    // Yataelの選出条件を厳しくする（-0.15〜0.15 → -0.1〜0.1）
    if (browAngle >= -0.1 && browAngle <= 0.1) {
      // 眉が非常に水平 → バランス型、協調的（Yataelのみ）
      candidates.addAll(['Yatael']);
    }
    // 水平（-0.15~0.15）も極端な特徴として判定
    if (browAngle >= -0.15 && browAngle <= 0.15) {
      // 眉が水平 → バランス型、協調的
      candidates.addAll(['Kanonis', 'Sylna', 'Tenmira', 'Shiran']);
    }

    // 【人相学の本から学習】眉が長い → 気が長い、心が豊か、寛大、協調的、社交的
    // 極端な特徴のみ判定（非常に長い >0.9 のみ、普通の長さはスキップ）
    // Amateraはより厳しい条件でのみ追加（眉が非常に長い + 眉が整っている + 眉間が広い）
    // Kanonisはより厳しい条件でのみ追加（眉が非常に長い + 眉が整っている）
    if (browLength > 0.9 && browNeatness > 0.85 && glabellaWidth > 0.75) {
      candidates.addAll(['Kanonis', 'Sylna', 'Amatera']);
    } else if (browLength > 0.9 && browNeatness > 0.85) {
      candidates.addAll(['Kanonis', 'Sylna']);
    } else if (browLength > 0.9) {
      candidates.addAll(['Yatael']);
    }

    // 【人相学の本から学習】眉が短い → 短気、偏屈、我慢が足りない
    // 極端な特徴のみ判定（短い <0.3 のみ、普通の長さはスキップ）
    // Ragiasはより厳しい条件でのみ追加（眉が非常に短い + 眉が右上がり + 眉が直線的）
    if (browLength < 0.2 && browAngle > 0.3 && browShape < 0.3) {
      candidates.addAll(['Ragias', 'Fatemis', 'Tenkora']);
    } else if (browLength < 0.3) {
      candidates.addAll(['Fatemis', 'Tenkora', 'Delphos', 'Amanoira', 'Noirune', 'Mimika']);
    }

    // 【人相学の本から学習】眉が濃い（太い） → 欲望が強い、粘着力、積極的、理性、こだわり、頑固
    // 極端な特徴のみ判定（非常に濃い >0.95 のみ、普通の太さはスキップ）
    // AmateraとDelphosはより厳しい条件でのみ追加（眉が非常に濃い + 眉が整っている + 眉間が広い）
    // Ragiasはより厳しい条件でのみ追加（眉が非常に濃い + 眉が右上がり + 眉が直線的）
    if (browThickness > 0.95 && browNeatness > 0.85 && glabellaWidth > 0.8) {
      candidates.addAll(['Fatemis', 'Verdatsu', 'Amatera', 'Delphos']);
    } else if (browThickness > 0.9 && browAngle > 0.3 && browShape < 0.3) {
      candidates.addAll(['Ragias', 'Fatemis', 'Verdatsu', 'Delphos']);
    } else if (browThickness > 0.95) {
      candidates.addAll(['Fatemis', 'Verdatsu', 'Delphos']);
    }

    // 【人相学の本から学習】眉が薄い（細い） → 要領が良い、感情的、利己的
    // 極端な特徴のみ判定（非常に薄い <0.2 のみ、普通の太さはスキップ）
    // Kanonisはより厳しい条件でのみ追加（眉が非常に薄い + 眉が水平 + 眉が整っている）
    if (browThickness < 0.2 && browAngle >= -0.15 && browAngle <= 0.15 && browNeatness > 0.8) {
      candidates.addAll(['Noirune', 'Mimika', 'Sylna', 'Kanonis']);
    } else if (browThickness < 0.2) {
      candidates.addAll(['Noirune', 'Mimika', 'Sylna']);
    }

    // 【人相学の本から学習】眉が曲線 → 柔軟な思考、多面的、知識豊富、聡明、円満、女性的
    // 極端な特徴のみ判定（曲線的 >0.6 のみ、普通の形状はスキップ）
    // 学習：緩やかなアーチも曲線として判定（閾値を0.7→0.6に下げる）
    // Amateraはより厳しい条件でのみ追加（眉が非常に曲線的 + 眉が整っている + 眉間が広い）
    // Kanonisはより厳しい条件でのみ追加（眉が非常に曲線的 + 眉が整っている）
    if (browShape > 0.9 && browNeatness > 0.85 && glabellaWidth > 0.75) {
      candidates.addAll(['Sylna', 'Kanonis', 'Amatera']);
    } else if (browShape > 0.9 && browNeatness > 0.85) {
      candidates.addAll(['Sylna', 'Kanonis']);
    } else if (browShape > 0.85 && browNeatness > 0.85) {
      // 曲線的（>0.85）で整っている場合
      candidates.addAll(['Sylna', 'Kanonis', 'Yatael']);
    } else if (browShape > 0.75 && browNeatness > 0.8) {
      // やや曲線的（>0.75）で整っている場合
      candidates.addAll(['Sylna', 'Yatael']);
    } else if (browShape > 0.6) {
      // 緩やかな曲線（>0.6）も曲線として判定
      candidates.addAll(['Sylna', 'Yatael']);
    }

    // 【人相学の本から学習】眉が直線 → 直情的、シンプル、頑固、我が強い
    // 極端な特徴のみ判定（非常に直線的 <0.2 のみ、普通の形状はスキップ）
    // Delphosはより厳しい条件でのみ追加（眉が非常に直線的）
    // Ragiasはより厳しい条件でのみ追加（眉が非常に直線的 + 眉が右上がり + 眉が太い）
    if (browShape < 0.15 && browAngle > 0.3 && browThickness > 0.7) {
      candidates.addAll(['Ragias', 'Fatemis', 'Verdatsu', 'Delphos']);
    } else if (browShape < 0.2) {
      candidates.addAll(['Fatemis', 'Verdatsu', 'Delphos', 'Amanoira']);
    }

    // 【人相学の本から学習】眉間が広い → 器が大きい、視野が広い、楽天家、社交性
    // 極端な特徴のみ判定（非常に広い >0.9 のみ、普通の幅はスキップ）
    // Amateraはより厳しい条件でのみ追加（眉間が非常に広い + 眉が整っている + 眉が長い）
    // Kanonisはより厳しい条件でのみ追加（眉間が非常に広い + 眉が整っている）
    if (glabellaWidth > 0.9 && browNeatness > 0.85 && browLength > 0.8) {
      candidates.addAll(['Amatera', 'Kanonis']);
    } else if (glabellaWidth > 0.9 && browNeatness > 0.85) {
      candidates.addAll(['Kanonis']);
    } else if (glabellaWidth > 0.9) {
      candidates.addAll(['Yatael']);
    }

    // 【人相学の本から学習】眉間が狭い → 神経質、視野が狭い、器が小さい、疑い深い、嫉妬心
    // 極端な特徴のみ判定（非常に狭い <0.2 のみ、普通の幅はスキップ）
    // Delphosはより厳しい条件でのみ追加（眉間が非常に狭い）
    if (glabellaWidth < 0.2) {
      candidates.addAll(['Noirune', 'Mimika', 'Delphos', 'Amanoira']);
    }

    // 【人相学の本から学習】眉が整っている → 勇気、協調性、忍耐力、兄弟・友人の助け
    // 極端な特徴のみ判定（非常に整っている >0.95 のみ、普通の整いはスキップ）
    // Amateraはより厳しい条件でのみ追加（眉が非常に整っている + 眉間が広い + 眉が長い）
    // Kanonisはより厳しい条件でのみ追加（眉が非常に整っている + 眉が長い）
    if (browNeatness > 0.95 && glabellaWidth > 0.8 && browLength > 0.8) {
      candidates.addAll(['Amatera', 'Yatael', 'Kanonis', 'Sylna']);
    } else if (browNeatness > 0.95 && browLength > 0.8) {
      candidates.addAll(['Yatael', 'Kanonis', 'Sylna']);
    } else if (browNeatness > 0.95) {
      candidates.addAll(['Yatael', 'Sylna']);
    }

    // 【人相学の本から学習】眉が乱れている → 悩み、精神的に不安定、争いを好む
    // 極端な特徴のみ判定（非常に乱れている <0.15 のみ、普通の整いはスキップ）
    // Fatemisはより厳しい条件でのみ追加（眉が非常に乱れている）
    // Ragiasはより厳しい条件でのみ追加（眉が非常に乱れている + 眉が右上がり + 眉が太い）
    if (browNeatness < 0.15 && browAngle > 0.3 && browThickness > 0.7) {
      candidates.addAll(['Ragias', 'Fatemis', 'Tenkora']);
    } else if (browNeatness < 0.15) {
      candidates.addAll(['Fatemis', 'Tenkora']);
    }

    // 重複を除去して返す
    return candidates.toSet().toList();
  }

  /// 眉と目の特徴から候補を振り分け（最優先判定・人相学の本から学習した詳細な判定）
  /// 眉と目の特徴が最も性格を表す部分であるため、まずここで候補を絞り込む
  static List<String> _getEyeBrowCandidates(
    double eyeBalance,
    double browAngle,
    double eyeSize,
    double eyeShape,
    double browLength,
    double browThickness,
    double browShape,
    double glabellaWidth,
    double browNeatness,
  ) {
    final candidates = <String>[];

    // 【人相学の本から学習】眉尻が上がっている → 気性が激しい、積極的、合理的、決断力、数字に強い
    if (browAngle > 0.2) {
      // パターン1: 眉が右上がり + 目が大きい + 目のバランスが良い → 積極的、明るい性格
      // Fatemisはより厳しい条件でのみ追加（眉が直線的）
      // Skuraはより厳しい条件でのみ追加（目が非常に大きい + 目のバランスが非常に良い + 口が大きい）
      // Osiriaはより厳しい条件でのみ追加（目が非常に大きい + 目のバランスが非常に良い）
      // Ragiasはより厳しい条件でのみ追加（眉が非常に右上がり + 目が大きい + 目のバランスが良い + 眉が直線的）
      if (eyeSize > 0.6 && eyeBalance > 0.65 && browShape < 0.3 && browAngle > 0.4) {
        candidates.addAll(['Amatera', 'Yatael', 'Ragias', 'Fatemis']);
      } else if (eyeSize > 0.6 && eyeBalance > 0.65 && browAngle > 0.4) {
        candidates.addAll(['Amatera', 'Yatael']);
      }
      // パターン3: 切れ長の目 + 眉が右上がり → 知的、決断力がある
      // Fatemisはより厳しい条件でのみ追加（目が非常に切れ長）
      // Ragiasはより厳しい条件でのみ追加（目が非常に切れ長 + 眉が非常に右上がり + 眉が直線的）
      if (eyeShape > 0.85 && browAngle > 0.4 && browShape < 0.3) {
        candidates.addAll(['Verdatsu', 'Fatemis', 'Delphos', 'Ragias', 'Amanoira']);
      } else if (eyeShape > 0.8) {
        candidates.addAll(['Verdatsu', 'Fatemis', 'Delphos', 'Amanoira']);
      } else if (eyeShape > 0.6) {
        candidates.addAll(['Verdatsu', 'Delphos', 'Amanoira']);
      }
      // パターン7: 目のバランスが良い + 眉が右上がり → 明るく積極的
      // Fatemisはより厳しい条件でのみ追加（眉が直線的）
      // Ragiasはより厳しい条件でのみ追加（目のバランスが非常に良い + 眉が非常に右上がり + 眉が直線的 + 眉が太い）
      if (eyeBalance > 0.8 && browAngle > 0.5 && browShape < 0.2 && browThickness > 0.7) {
        candidates.addAll(['Amatera', 'Yatael', 'Ragias', 'Fatemis', 'Delphos']);
      } else if (eyeBalance > 0.75 && browAngle > 0.4 && browShape < 0.3) {
        candidates.addAll(['Amatera', 'Yatael', 'Fatemis', 'Delphos']);
      } else if (eyeBalance > 0.75 && browAngle > 0.4) {
        candidates.addAll(['Amatera', 'Yatael', 'Delphos']);
      }
      // パターン8: 目が大きい + 切れ長 + 眉が右上がり → 知的で積極的
      // Fatemisはより厳しい条件でのみ追加（目が非常に切れ長）
      // Osiriaはより厳しい条件でのみ追加（目が非常に大きい + 目のバランスが非常に良い）
      // Ragiasはより厳しい条件でのみ追加（目が大きい + 目が非常に切れ長 + 眉が非常に右上がり + 眉が直線的）
      if (eyeSize > 0.6 && eyeShape > 0.85 && browAngle > 0.5 && browShape < 0.3) {
        candidates.addAll(['Verdatsu', 'Fatemis', 'Ragias', 'Amatera']);
      } else if (eyeSize > 0.6 && eyeShape > 0.8) {
        candidates.addAll(['Verdatsu', 'Fatemis', 'Amatera']);
      } else if (eyeSize > 0.6 && eyeShape > 0.6) {
        candidates.addAll(['Verdatsu', 'Amatera']);
      }
      // 【学習】眉が太い + 右上がり → 決断力、実行力、積極的（男性的）
      // Fatemisはより厳しい条件でのみ追加（眉が非常に太い + 眉が直線的）
      // Ragiasはより厳しい条件でのみ追加（眉が非常に太い + 眉が非常に右上がり + 眉が直線的）
      if (browThickness > 0.85 && browAngle > 0.5 && browShape < 0.2) {
        candidates.addAll(['Ragias', 'Fatemis', 'Verdatsu', 'Amatera']);
      } else if (browThickness > 0.7 && browShape < 0.3) {
        candidates.addAll(['Fatemis', 'Verdatsu', 'Amatera']);
      } else if (browThickness > 0.6) {
        candidates.addAll(['Verdatsu', 'Amatera']);
      }
      // 【学習】へ字眉（眉が直線的で右上がり） → 職人気質、情熱的、実行力
      // Fatemisはより厳しい条件でのみ追加（眉が非常に直線的）
      // Ragiasはより厳しい条件でのみ追加（眉が非常に直線的 + 眉が非常に右上がり + 眉が太い）
      if (browShape < 0.15 && browAngle > 0.5 && browThickness > 0.7) {
        candidates.addAll(['Ragias', 'Fatemis', 'Verdatsu']);
      } else if (browShape < 0.2 && browAngle > 0.4) {
        candidates.addAll(['Fatemis', 'Verdatsu']);
      } else if (browShape < 0.3 && browAngle > 0.3) {
        candidates.addAll(['Verdatsu']);
      }
    }

    // 【人相学の本から学習】眉尻が下がっている → 人柄が良い、消極的、平和主義、面倒見が良い
    if (browAngle < -0.2) {
      // パターン2: 眉が右下がり + 目が小さい + 目のバランスが悪い → 内向的、冷静な性格
      if (eyeSize < 0.4 && eyeBalance < 0.35) {
        candidates.addAll(['Noirune', 'Mimika', 'Sylna', 'Kanonis', 'Amanoira', 'Delphos']);
      }
      // パターン5: 目のバランスが悪い + 眉が右下がり → 内向的、慎重
      if (eyeBalance < 0.35) {
        candidates.addAll(['Noirune', 'Mimika', 'Sylna', 'Kanonis']);
      }
      // パターン9: 目が小さい + 目のバランスが悪い + 眉が右下がり → 内向的、慎重
      if (eyeSize < 0.4 && eyeBalance < 0.35 && browAngle < -0.3) {
        candidates.addAll(['Noirune', 'Mimika', 'Sylna', 'Kanonis', 'Amanoira']);
      }
      // 【学習】八字眉（眉尻が大きく下がる） → 度量が広い、陽気、お調子者、要領が良い
      // Skuraはより厳しい条件でのみ追加（八字眉 + 口が大きい）
      if (browAngle < -0.3 && browThickness > 0.5) {
        candidates.addAll(['Sylna', 'Kanonis', 'Yatael']);
      }
    }

    // 【人相学の本から学習】眉が水平 → バランス型
    // 分散化のため、条件を緩和してTenmira, Shiranを選びやすくする
    if (browAngle >= -0.2 && browAngle <= 0.2) {
      // パターン4: 大きな目 + 眉が水平 → 社交的、情緒的
      // Skuraはより厳しい条件でのみ追加（大きな目 + 眉が水平 + 口が大きい）
      // Osiriaはより厳しい条件でのみ追加（目が非常に大きい + 目のバランスが非常に良い）
      if (eyeSize > 0.6) {
        candidates.addAll(['Sylna', 'Kanonis', 'Amatera', 'Yatael', 'Tenmira', 'Shiran']);
      }
      // パターン6: 切れ長の目 + 眉が水平 → 冷静、分析的
      // Fatemisはより厳しい条件でのみ追加（目が非常に切れ長）
      if (eyeShape > 0.8) {
        candidates.addAll(['Delphos', 'Amanoira', 'Verdatsu', 'Fatemis']);
      } else if (eyeShape > 0.6) {
        candidates.addAll(['Delphos', 'Amanoira', 'Verdatsu']);
      }
      // パターン10: 目のバランスが良い + 眉が水平 → バランス型、協調的
      // 分散化のため、条件を緩和（0.7→0.65）
      if (eyeBalance > 0.65) {
        candidates.addAll(['Yatael', 'Kanonis', 'Sylna', 'Tenmira', 'Shiran']);
      }
      // 分散化のため、眉が水平な場合、Tenmira, Shiranを常に追加
      candidates.addAll(['Tenmira', 'Shiran']);
    }

    // 【人相学の本から学習】眉が長い → 気が長い、心が豊か、寛大、協調的、社交的
    // Skuraはより厳しい条件でのみ追加（眉が非常に長い + 口が大きい）
    if (browLength > 0.7) {
      candidates.addAll(['Yatael', 'Kanonis', 'Sylna', 'Amatera']);
    }

    // 【人相学の本から学習】眉が短い → 短気、偏屈、我慢が足りない
    // Fatemisはより厳しい条件でのみ追加（眉が非常に短い + 眉が直線的）
    if (browLength < 0.2 && browShape < 0.3) {
      candidates.addAll(['Ragias', 'Fatemis', 'Tenkora']);
    } else if (browLength < 0.3) {
      candidates.addAll(['Ragias', 'Tenkora']);
    }

    // 【人相学の本から学習】眉が濃い（太い） → 欲望が強い、粘着力、積極的、理性、こだわり、頑固
    // Fatemisはより厳しい条件でのみ追加（眉が非常に濃い + 眉が直線的）
    if (browThickness > 0.8 && browShape < 0.3) {
      candidates.addAll(['Ragias', 'Fatemis', 'Verdatsu', 'Amatera', 'Delphos']);
    } else if (browThickness > 0.7) {
      candidates.addAll(['Ragias', 'Verdatsu', 'Amatera', 'Delphos']);
    }

    // 【人相学の本から学習】眉が薄い（細い） → 要領が良い、感情的、利己的
    if (browThickness < 0.3) {
      candidates.addAll(['Noirune', 'Mimika', 'Sylna', 'Kanonis']);
    }

    // 【人相学の本から学習】眉が曲線 → 柔軟な思考、多面的、知識豊富、聡明、円満、女性的
    // Skuraはより厳しい条件でのみ追加（眉が非常に曲線的 + 口が大きい）
    // Osiriaはより厳しい条件でのみ追加（眉が非常に曲線的 + 目のバランスが良い）
    if (browShape > 0.7) {
      candidates.addAll(['Sylna', 'Kanonis', 'Amatera', 'Yatael']);
    }

    // 【人相学の本から学習】眉が直線 → 直情的、シンプル、頑固、我が強い
    // Fatemisはより厳しい条件でのみ追加（眉が非常に直線的）
    if (browShape < 0.2) {
      candidates.addAll(['Ragias', 'Fatemis', 'Verdatsu', 'Delphos']);
    } else if (browShape < 0.3) {
      candidates.addAll(['Ragias', 'Verdatsu', 'Delphos']);
    }

    // 【人相学の本から学習】眉間が広い → 器が大きい、視野が広い、楽天家、社交性
    // Skuraはより厳しい条件でのみ追加（眉間が非常に広い + 口が大きい）
    // Osiriaはより厳しい条件でのみ追加（眉間が非常に広い + 目のバランスが良い）
    if (glabellaWidth > 0.7) {
      candidates.addAll(['Amatera', 'Yatael', 'Kanonis']);
    }

    // 【人相学の本から学習】眉間が狭い → 神経質、視野が狭い、器が小さい、疑い深い、嫉妬心
    if (glabellaWidth < 0.3) {
      candidates.addAll(['Noirune', 'Mimika', 'Delphos', 'Amanoira']);
    }

    // 【人相学の本から学習】眉が整っている → 勇気、協調性、忍耐力、兄弟・友人の助け
    // Skuraはより厳しい条件でのみ追加（眉が非常に整っている + 口が大きい）
    if (browNeatness > 0.7) {
      candidates.addAll(['Amatera', 'Yatael', 'Kanonis', 'Sylna']);
    }

    // 【人相学の本から学習】眉が乱れている → 悩み、精神的に不安定、争いを好む
    // Fatemisはより厳しい条件でのみ追加（眉が非常に乱れている）
    // Ragiasはより厳しい条件でのみ追加（眉が非常に乱れている + 眉が右上がり + 眉が太い）
    if (browNeatness < 0.15 && browAngle > 0.3 && browThickness > 0.7) {
      candidates.addAll(['Ragias', 'Fatemis', 'Tenkora']);
    } else if (browNeatness < 0.2) {
      candidates.addAll(['Fatemis', 'Tenkora']);
    } else if (browNeatness < 0.3) {
      candidates.addAll(['Tenkora']);
    }

    // 重複を除去して返す
    return candidates.toSet().toList();
  }

  /// 顔の型に基づく候補を取得（三停よりも優先）
  static List<String> _getFaceTypeCandidates(String faceType, FaceTypeResult faceTypeResult) {
    switch (faceType) {
      case '丸顔':
        return ['Skura', 'Sylna', 'Kanonis', 'Amatera', 'Yatael'];
      case '細長顔':
        // Fatemisはより厳しい条件でのみ追加（細長顔 + 眉が直線的）
        return ['Verdatsu', 'Delphos', 'Amanoira'];
      case '長方形顔':
        return ['Ragias', 'Verdatsu', 'Osiria', 'Tenkora'];
      case '台座顔':
        return ['Skura', 'Ragias', 'Osiria', 'Amatera'];
      case '卵顔':
        // Fatemisはより厳しい条件でのみ追加（卵顔 + 眉が直線的）
        return ['Verdatsu', 'Delphos', 'Ragias'];
      case '四角顔':
        // Fatemisはより厳しい条件でのみ追加（四角顔 + 眉が直線的）
        return ['Ragias', 'Delphos', 'Tenkora', 'Shisaru'];
      case '逆三角形顔':
        // Fatemisはより厳しい条件でのみ追加（逆三角形顔 + 眉が直線的）
        return ['Delphos', 'Amanoira', 'Verdatsu'];
      case '三角形顔':
        return ['Skura', 'Kanonis', 'Sylna', 'Osiria', 'Amatera'];
      default:
        return [];
    }
  }

  /// 人相学の顔の型に基づく補正を計算（三停よりも荷重を大きく）
  @Deprecated('未使用のため将来削除予定')
  static double _getFaceTypeBonus(String faceType, String deityId, FaceTypeResult faceTypeResult) {
    double bonus = 0.0;
    final confidence = faceTypeResult.confidence;

    // 顔の型の構成（脂肪型、精神型、筋骨型）に基づいて補正
    // 各神の特性と顔の型の特性をマッピング
    // 信頼度に応じて補正を調整（信頼度が高いほど補正を大きく）
    // 信頼度が低い場合は補正を弱める
    final confidenceMultiplier = confidence.clamp(0.3, 1.0); // 0.3-1.0の範囲（最低0.3を保証）

    switch (faceType) {
      case '丸顔':
        // 丸顔: 社交性、楽天的、情緒的
        // 脂肪型100% → 社交性が高い神にボーナス
        if (['Skura', 'Sylna', 'Kanonis', 'Amatera', 'Yatael'].contains(deityId)) {
          bonus += 0.15 * confidenceMultiplier; // 0.08 → 0.15（最大）
        }
        break;

      case '細長顔':
        // 細長顔: 着実、礼儀正しい、洞察力
        // 精神型50%、筋骨型50% → 知的で堅実な神にボーナス
        // Fatemisはより厳しい条件でのみ補正（細長顔 + 眉が直線的）
        if (['Verdatsu', 'Delphos', 'Amanoira'].contains(deityId)) {
          bonus += 0.15 * confidenceMultiplier;
        }
        break;

      case '長方形顔':
        // 長方形顔: 聡明、実行力、指導力、温かさ
        // 筋骨型60%、精神型20%、脂肪型20% → バランス型の神にボーナス
        if (['Ragias', 'Verdatsu', 'Osiria', 'Tenkora'].contains(deityId)) {
          bonus += 0.15 * confidenceMultiplier;
        }
        break;

      case '台座顔':
        // 台座顔: 積極的、社交性、処理能力、指導力
        // 脂肪型60%、精神型40% → 社交性と知性のバランス
        if (['Skura', 'Ragias', 'Osiria', 'Amatera'].contains(deityId)) {
          bonus += 0.15 * confidenceMultiplier;
        }
        break;

      case '卵顔':
        // 卵顔: 頭脳明晰、努力家、忍耐力
        // 精神型40%、筋骨型60% → 知的で意志が強い神にボーナス
        // Fatemisはより厳しい条件でのみ補正（卵顔 + 眉が直線的）
        if (['Verdatsu', 'Delphos', 'Ragias'].contains(deityId)) {
          bonus += 0.15 * confidenceMultiplier;
        }
        break;

      case '四角顔':
        // 四角顔: 冷静、処理能力、頑固、意志力
        // 筋骨型100% → 意志が強い神にボーナス
        // Fatemisはより厳しい条件でのみ補正（四角顔 + 眉が直線的）
        if (['Ragias', 'Delphos', 'Tenkora', 'Shisaru'].contains(deityId)) {
          bonus += 0.15 * confidenceMultiplier;
        }
        break;

      case '逆三角形顔':
        // 逆三角形顔: 真面目、冷静、緻密、地位志向
        // 精神型100% → 知的で冷静な神にボーナス
        // Fatemisはより厳しい条件でのみ補正（逆三角形顔 + 眉が直線的）
        if (['Delphos', 'Amanoira', 'Verdatsu'].contains(deityId)) {
          bonus += 0.15 * confidenceMultiplier;
        }
        break;

      case '三角形顔':
        // 三角形顔: 明るく円満、意志が強い、実行力、義理人情
        // 脂肪型60%、筋骨型40% → 社交性と実行力のバランス
        if (['Skura', 'Kanonis', 'Sylna', 'Osiria', 'Amatera'].contains(deityId)) {
          bonus += 0.15 * confidenceMultiplier;
        }
        break;
    }

    return bonus;
  }

  // 目の特徴を抽出（性格診断用・MediaPipe Face Mesh統合版）
  static Map<String, double> extractEyeFeaturesForDiagnosis(Face face) {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

    if (leftEye == null || rightEye == null) {
      return {'size': 0.5, 'shape': 0.5, 'balance': 0.5};
    }

    final box = face.boundingBox;

    // MediaPipe Face Mesh相当のデータを推定
    final mediaPipeMesh = MediaPipeFaceMeshEstimator.estimateFromMLKit(
      face,
      imageWidth: box.width,
      imageHeight: box.height,
    );

    final leftEyeContour = face.contours[FaceContourType.leftEye]?.points ?? [];
    final rightEyeContour = face.contours[FaceContourType.rightEye]?.points ?? [];

    // 目のサイズ（MediaPipe Face MeshとML Kitを統合）
    double eyeSize = 0.5;
    double mlKitEyeSize = 0.5;
    double rawMlKitArea = 0.0;
    if (leftEyeContour.isNotEmpty && rightEyeContour.isNotEmpty) {
      final leftArea = _estimateContourArea(leftEyeContour);
      final rightArea = _estimateContourArea(rightEyeContour);
      final avgArea = (leftArea + rightArea) / 2.0;
      rawMlKitArea = avgArea;
      final faceArea = face.boundingBox.width * face.boundingBox.height;
      // 目の面積を顔の面積に対する比率として計算（通常0.001-0.01の範囲）
      final eyeAreaRatio = avgArea / faceArea;
      // より適切な正規化範囲を使用（0.0008-0.012の範囲を0.0-1.0にマッピング）
      // 範囲を狭くして、より厳しい判定にする
      mlKitEyeSize = ((eyeAreaRatio - 0.0008) / 0.0112).clamp(0.0, 1.0);
    }

    // MediaPipe Face Meshから目のサイズを計算
    double mediaPipeEyeSize = 0.5;
    double rawMediaPipeArea = 0.0;
    if (mediaPipeMesh != null) {
      final leftEyeLandmarks = mediaPipeMesh.getLeftEye();
      final rightEyeLandmarks = mediaPipeMesh.getRightEye();
      if (leftEyeLandmarks.isNotEmpty && rightEyeLandmarks.isNotEmpty) {
        // 目のランドマークの範囲から面積を推定
        final leftEyeXs = leftEyeLandmarks.map((p) => p.x).toList();
        final leftEyeYs = leftEyeLandmarks.map((p) => p.y).toList();
        final rightEyeXs = rightEyeLandmarks.map((p) => p.x).toList();
        final rightEyeYs = rightEyeLandmarks.map((p) => p.y).toList();

        final leftWidth = (leftEyeXs.reduce(math.max) - leftEyeXs.reduce(math.min)) * box.width;
        final leftHeight = (leftEyeYs.reduce(math.max) - leftEyeYs.reduce(math.min)) * box.height;
        final rightWidth = (rightEyeXs.reduce(math.max) - rightEyeXs.reduce(math.min)) * box.width;
        final rightHeight = (rightEyeYs.reduce(math.max) - rightEyeYs.reduce(math.min)) * box.height;

        final leftArea = leftWidth * leftHeight;
        final rightArea = rightWidth * rightHeight;
        final avgArea = (leftArea + rightArea) / 2.0;
        rawMediaPipeArea = avgArea;
        final faceArea = box.width * box.height;
        // 目の面積を顔の面積に対する比率として計算
        final eyeAreaRatio = avgArea / faceArea;
        // より適切な正規化範囲を使用（0.0008-0.012の範囲を0.0-1.0にマッピング）
        // 範囲を狭くして、より厳しい判定にする
        mediaPipeEyeSize = ((eyeAreaRatio - 0.0008) / 0.0112).clamp(0.0, 1.0);
      }
    }

    // MediaPipe 70% + ML Kit 30%で統合
    eyeSize = mediaPipeEyeSize * 0.7 + mlKitEyeSize * 0.3;

    print(
        '[目の特徴抽出] rawMlKitArea: ${rawMlKitArea.toStringAsFixed(4)}, rawMediaPipeArea: ${rawMediaPipeArea.toStringAsFixed(4)}');
    print(
        '[目の特徴抽出] mlKitEyeSize: ${mlKitEyeSize.toStringAsFixed(4)}, mediaPipeEyeSize: ${mediaPipeEyeSize.toStringAsFixed(4)}, eyeSize: ${eyeSize.toStringAsFixed(4)}');

    // 目の形状（切れ長かどうか）
    double eyeShape = 0.5;
    final mediaPipeEyeShape = mediaPipeMesh != null ? _extractEyeShapeFromMediaPipe(mediaPipeMesh, box) : null;

    // MediaPipe Face Meshのデータがあれば優先的に使用、なければML Kitのデータを使用
    if (mediaPipeEyeShape != null) {
      // MediaPipe Face Meshの精密な判定結果を使用
      eyeShape = mediaPipeEyeShape;
    } else if (leftEyeContour.isNotEmpty && rightEyeContour.isNotEmpty) {
      // フォールバック: ML Kitの輪郭データから推定
      final leftWidth =
          leftEyeContour.map((p) => p.x).reduce(math.max) - leftEyeContour.map((p) => p.x).reduce(math.min);
      final leftHeight =
          leftEyeContour.map((p) => p.y).reduce(math.max) - leftEyeContour.map((p) => p.y).reduce(math.min);
      final rightWidth =
          rightEyeContour.map((p) => p.x).reduce(math.max) - rightEyeContour.map((p) => p.x).reduce(math.min);
      final rightHeight =
          rightEyeContour.map((p) => p.y).reduce(math.max) - rightEyeContour.map((p) => p.y).reduce(math.min);

      final leftRatio = leftHeight > 0 ? leftWidth / leftHeight : 1.0;
      final rightRatio = rightHeight > 0 ? rightWidth / rightHeight : 1.0;
      final avgRatio = (leftRatio + rightRatio) / 2.0;
      // 切れ長 = 横長（比率が大きい）
      eyeShape = (avgRatio / 3.0).clamp(0.0, 1.0);
    }

    // 目のバランス（MediaPipe Face MeshとML Kitを統合）
    double eyeBalance = _estimateEyeBalanceAdvanced(face);
    if (mediaPipeMesh != null) {
      final leftEyeLandmarks = mediaPipeMesh.getLeftEye();
      final rightEyeLandmarks = mediaPipeMesh.getRightEye();
      if (leftEyeLandmarks.isNotEmpty && rightEyeLandmarks.isNotEmpty) {
        // MediaPipe Face Meshから目のバランスを計算
        final leftEyeCenter = MediaPipeLandmark(
            leftEyeLandmarks.map((p) => p.x).reduce((a, b) => a + b) / leftEyeLandmarks.length,
            leftEyeLandmarks.map((p) => p.y).reduce((a, b) => a + b) / leftEyeLandmarks.length,
            0.0);
        final rightEyeCenter = MediaPipeLandmark(
            rightEyeLandmarks.map((p) => p.x).reduce((a, b) => a + b) / rightEyeLandmarks.length,
            rightEyeLandmarks.map((p) => p.y).reduce((a, b) => a + b) / rightEyeLandmarks.length,
            0.0);

        double mediaPipeBalance = 0.0;

        // Y座標の差（対称性）: 40%
        final yDiff = (leftEyeCenter.y - rightEyeCenter.y).abs();
        final ySymmetryScore = (1.0 - yDiff.clamp(0.0, 0.1) * 10.0).clamp(0.0, 1.0);
        mediaPipeBalance += ySymmetryScore * 0.4;

        // 面積比（左右の目の面積）: 30%
        final leftEyeArea = _estimateMediaPipeArea(leftEyeLandmarks, box);
        final rightEyeArea = _estimateMediaPipeArea(rightEyeLandmarks, box);
        final areaRatio =
            math.min<double>(leftEyeArea, rightEyeArea) / (math.max<double>(leftEyeArea, rightEyeArea) + 1e-6);
        mediaPipeBalance += areaRatio * 0.3;

        // 目の開き具合の差（ML Kitの確率を使用）: 30%
        final leftEyeOpen = face.leftEyeOpenProbability ?? 0.5;
        final rightEyeOpen = face.rightEyeOpenProbability ?? 0.5;
        final eyeOpenDiff = (leftEyeOpen - rightEyeOpen).abs();
        final eyeOpenBalanceScore = (1.0 - eyeOpenDiff.clamp(0.0, 0.5) * 2.0).clamp(0.0, 1.0);
        mediaPipeBalance += eyeOpenBalanceScore * 0.3;

        // MediaPipe 70% + ML Kit 30%で統合
        eyeBalance = mediaPipeBalance * 0.7 + eyeBalance * 0.3;
      }
    }

    return {'size': eyeSize, 'shape': eyeShape, 'balance': eyeBalance};
  }

  // MediaPipe Face Meshのランドマークから面積を推定
  static double _estimateMediaPipeArea(List<MediaPipeLandmark> landmarks, ui.Rect box) {
    if (landmarks.isEmpty) return 0.0;
    final xs = landmarks.map((p) => p.x * box.width).toList();
    final ys = landmarks.map((p) => p.y * box.height).toList();
    final width = xs.reduce(math.max) - xs.reduce(math.min);
    final height = ys.reduce(math.max) - ys.reduce(math.min);
    return width * height;
  }

  // MediaPipe Face Meshのデータから目の形状（切れ長度）を精密に抽出
  static double? _extractEyeShapeFromMediaPipe(MediaPipeFaceMesh mesh, ui.Rect box) {
    try {
      // 左目のランドマークを取得
      final leftEyeOuter = mesh.getLeftEyeOuter();
      final leftEyeInner = mesh.getLeftEyeInner();
      final leftEyeTop = mesh.getLeftEyeTop();
      final leftEyeBottom = mesh.getLeftEyeBottom();

      // 右目のランドマークを取得
      final rightEyeOuter = mesh.getRightEyeOuter();
      final rightEyeInner = mesh.getRightEyeInner();
      final rightEyeTop = mesh.getRightEyeTop();
      final rightEyeBottom = mesh.getRightEyeBottom();

      if (leftEyeOuter.isEmpty ||
          leftEyeInner.isEmpty ||
          leftEyeTop.isEmpty ||
          leftEyeBottom.isEmpty ||
          rightEyeOuter.isEmpty ||
          rightEyeInner.isEmpty ||
          rightEyeTop.isEmpty ||
          rightEyeBottom.isEmpty) {
        return null;
      }

      // 左目の判定
      final leftShape = _calculateEyeShapeFromLandmarks(leftEyeOuter, leftEyeInner, leftEyeTop, leftEyeBottom, box);

      // 右目の判定
      final rightShape =
          _calculateEyeShapeFromLandmarks(rightEyeOuter, rightEyeInner, rightEyeTop, rightEyeBottom, box);

      if (leftShape == null || rightShape == null) {
        return null;
      }

      // 左右の平均を返す
      return (leftShape + rightShape) / 2.0;
    } catch (e) {
      print('[MediaPipe Eye Shape] Error: $e');
      return null;
    }
  }

  // ランドマークから目の形状（切れ長度）を計算
  static double? _calculateEyeShapeFromLandmarks(
      List<MediaPipeLandmark> outer, // 外側（目尻）
      List<MediaPipeLandmark> inner, // 内側（目頭）
      List<MediaPipeLandmark> top, // 上端
      List<MediaPipeLandmark> bottom, // 下端
      ui.Rect box) {
    try {
      // 1. 横幅÷縦幅の比率を計算
      // 外側と内側の中心点を計算
      final outerCenter = MediaPipeLandmark(outer.map((p) => p.x).reduce((a, b) => a + b) / outer.length,
          outer.map((p) => p.y).reduce((a, b) => a + b) / outer.length, 0.0);
      final innerCenter = MediaPipeLandmark(inner.map((p) => p.x).reduce((a, b) => a + b) / inner.length,
          inner.map((p) => p.y).reduce((a, b) => a + b) / inner.length, 0.0);

      // 横幅（外側と内側の距離を実際のピクセル座標に変換）
      final eyeWidth = math.sqrt(math.pow((outerCenter.x - innerCenter.x) * box.width, 2) +
          math.pow((outerCenter.y - innerCenter.y) * box.height, 2));

      // 上端と下端の中心点を計算
      final topCenter = MediaPipeLandmark(top.map((p) => p.x).reduce((a, b) => a + b) / top.length,
          top.map((p) => p.y).reduce((a, b) => a + b) / top.length, 0.0);
      final bottomCenter = MediaPipeLandmark(bottom.map((p) => p.x).reduce((a, b) => a + b) / bottom.length,
          bottom.map((p) => p.y).reduce((a, b) => a + b) / bottom.length, 0.0);

      // 縦幅（上端と下端の距離を実際のピクセル座標に変換）
      final eyeHeight = math.sqrt(math.pow((topCenter.x - bottomCenter.x) * box.width, 2) +
          math.pow((topCenter.y - bottomCenter.y) * box.height, 2));

      // 横幅÷縦幅の比率
      final widthHeightRatio = eyeHeight > 0 ? eyeWidth / eyeHeight : 1.0;

      // 2. 目尻の角度と鋭さを計算（改善版：アーモンド型と切れ長を区別）
      // 外側ランドマークの上端と下端を取得
      final outerTop = outer.map((p) => p.y).reduce((a, b) => a < b ? a : b);
      final outerBottom = outer.map((p) => p.y).reduce((a, b) => a > b ? a : b);
      final outerLeft = outer.map((p) => p.x).reduce((a, b) => a < b ? a : b);
      final outerRight = outer.map((p) => p.x).reduce((a, b) => a > b ? a : b);

      // 内側ランドマークの上端を取得（目頭の上端）
      final innerTop = inner.map((p) => p.y).reduce((a, b) => a < b ? a : b);

      // 改善1: 目尻の上端と内側の上端の差を計算（目尻が鋭く上がっているかどうか）
      // 目尻が目頭より明らかに高い場合のみ切れ長と判定
      final outerInnerTopDiff = (innerTop - outerTop) * box.height; // 目尻が上にあるほど正の値

      // 改善2: 目尻の角度（外側ランドマークの傾き）を計算
      // 外側の上端と下端のY座標の差（実際のピクセル座標）
      final outerHeightDiff = (outerBottom - outerTop) * box.height;
      // 外側の左端と右端のX座標の差（実際のピクセル座標）
      final outerWidthDiff = (outerRight - outerLeft) * box.width;

      // 目尻の角度（アークタンジェントで計算、上がっているほど角度が大きい）
      final outerAngle = math.atan2(outerHeightDiff, outerWidthDiff);
      // 角度を0.0〜1.0に正規化（-π/2〜π/2 → 0.0〜1.0）
      final normalizedAngle = (outerAngle / math.pi + 0.5).clamp(0.0, 1.0);

      // 改善3: 目尻の鋭さを正規化（目尻が目頭より明らかに高い場合のみ高評価）
      // 目尻が目頭より5mm以上高い場合のみ切れ長と判定（box.heightの5%以上）
      final sharpnessThreshold = box.height * 0.05;
      final normalizedSharpness = (outerInnerTopDiff / sharpnessThreshold).clamp(0.0, 1.0);

      // 改善4: 目尻の角度と鋭さを組み合わせ（角度50%、鋭さ50%）
      final combinedAngle = normalizedAngle * 0.5 + normalizedSharpness * 0.5;

      // 3. 横幅÷縦幅の比率と目尻の角度・鋭さを組み合わせて切れ長度を計算
      // 改善5: 比率の正規化を厳しくする（2.5〜5.0 → 0.0〜1.0、切れ長の目は通常3.5以上）
      // アーモンド型の目（2.0〜2.5）は0.0にクランプされる
      final normalizedRatio = ((widthHeightRatio - 2.5) / 2.5).clamp(0.0, 1.0);

      // 改善6: 両方の指標が高い場合のみ切れ長と判定
      // 比率と角度・鋭さの両方が高い場合のみ、切れ長と判定
      // 両方の指標の最小値を使用し、スケーリングを調整（0.0〜1.0に正規化）
      final minIndicator = math.min(normalizedRatio, combinedAngle);
      // 両方の指標が0.5以上の場合のみ、切れ長度を高く評価
      final eyeShape = minIndicator > 0.5
          ? (minIndicator - 0.5) * 2.0 // 0.5〜1.0 → 0.0〜1.0
          : minIndicator * 0.5; // 0.0〜0.5 → 0.0〜0.25（低評価）

      return eyeShape.clamp(0.0, 1.0);
    } catch (e) {
      print('[Calculate Eye Shape] Error: $e');
      return null;
    }
  }

  // 目のバランス（左右の目の位置の対称性・高精度版）
  static double _estimateEyeBalanceAdvanced(Face f) {
    final leftEye = f.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = f.landmarks[FaceLandmarkType.rightEye]?.position;
    if (leftEye == null || rightEye == null) return 0.5;

    // 輪郭ポイントも活用（左右の目の輪郭）
    final leftEyeContour = f.contours[FaceContourType.leftEye]?.points ?? [];
    final rightEyeContour = f.contours[FaceContourType.rightEye]?.points ?? [];

    double balance = 0.0;
    final box = f.boundingBox;
    final eyeYDiff = (leftEye.y - rightEye.y).abs() / box.height;

    // 対称性スコア（Y軸位置の差）: 40%
    final ySymmetryScore = (1.0 - eyeYDiff.clamp(0.0, 0.3)) / 0.3;
    balance += ySymmetryScore * 0.4;

    // 面積比（左右の目の輪郭面積）: 30%
    if (leftEyeContour.isNotEmpty && rightEyeContour.isNotEmpty) {
      final double leftArea = _estimateContourArea(leftEyeContour);
      final double rightArea = _estimateContourArea(rightEyeContour);
      final areaRatio = math.min<double>(leftArea, rightArea) / (math.max<double>(leftArea, rightArea) + 1e-6);
      balance += areaRatio * 0.3;
    } else {
      balance += 0.15; // データがない場合は中間値
    }

    // 目の開き具合の差（重要）: 30%
    final leftEyeOpen = f.leftEyeOpenProbability ?? 0.5;
    final rightEyeOpen = f.rightEyeOpenProbability ?? 0.5;
    final eyeOpenDiff = (leftEyeOpen - rightEyeOpen).abs();
    // 開き具合の差が小さいほど高スコア（差0.0で1.0、差0.5以上で0.0）
    final eyeOpenBalanceScore = (1.0 - eyeOpenDiff.clamp(0.0, 0.5) * 2.0).clamp(0.0, 1.0);
    balance += eyeOpenBalanceScore * 0.3;

    return balance.clamp(0.0, 1.0);
  }

  // 輪郭の面積を推定（ML KitのPoint型）
  static double _estimateContourArea(List points) {
    if (points.isEmpty || points.length < 3) return 0.0;
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      final p1 = points[i];
      final p2 = points[j];
      area += (p1.x as int) * (p2.y as int) - (p2.x as int) * (p1.y as int);
    }
    return area.abs() / 2.0;
  }

  // 口幅の推定（左右の口角から）
  static double _estimateMouthWidth(Face f) {
    final leftMouth = f.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = f.landmarks[FaceLandmarkType.rightMouth]?.position;
    if (leftMouth == null || rightMouth == null) return 0.5;
    final box = f.boundingBox;
    final width = (rightMouth.x - leftMouth.x).abs() / box.width;
    return width.clamp(0.0, 1.0);
  }

  // 口の大きさを判定（人相学の本から学習：両目の瞳孔の内側の角から下に引いた線の幅を標準として判定）
  // MediaPipe Face Mesh + Google ML Kit統合版
  // 標準より大きいか小さいかを判定（0.0-1.0: 0.0=非常に小さい、0.5=標準、1.0=非常に大きい）
  static double estimateMouthSizeStandard(Face f) {
    final box = f.boundingBox;

    // MediaPipe Face Mesh相当のデータを推定
    final mediaPipeMesh = MediaPipeFaceMeshEstimator.estimateFromMLKit(
      f,
      imageWidth: box.width,
      imageHeight: box.height,
    );

    // Google ML Kitのデータを取得
    final leftMouth = f.landmarks[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = f.landmarks[FaceLandmarkType.rightMouth]?.position;
    final leftEye = f.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = f.landmarks[FaceLandmarkType.rightEye]?.position;

    if (leftMouth == null || rightMouth == null || leftEye == null || rightEye == null) {
      return 0.5; // デフォルトは標準
    }

    // MediaPipe Face Meshのデータから口の特徴を抽出（優先）
    double mouthSizeFromMediaPipe = 0.5;
    if (mediaPipeMesh != null) {
      try {
        final mouthLandmarks = mediaPipeMesh.getMouth();
        if (mouthLandmarks.length >= 2) {
          // 口の幅を計算（MediaPipeのランドマークから）
          final mouthLeft = mouthLandmarks.map((p) => p.x).reduce((a, b) => a < b ? a : b);
          final mouthRight = mouthLandmarks.map((p) => p.x).reduce((a, b) => a > b ? a : b);
          final mouthWidth = (mouthRight - mouthLeft) * box.width;

          // 目の内側の角を取得（MediaPipeのランドマークから）
          final leftEyeInner = mediaPipeMesh.getLeftEyeInner();
          final rightEyeInner = mediaPipeMesh.getRightEyeInner();

          if (leftEyeInner.isNotEmpty && rightEyeInner.isNotEmpty) {
            final leftEyeInnerX = leftEyeInner.map((p) => p.x).reduce((a, b) => a + b) / leftEyeInner.length;
            final rightEyeInnerX = rightEyeInner.map((p) => p.x).reduce((a, b) => a + b) / rightEyeInner.length;
            final standardMouthWidth = (rightEyeInnerX - leftEyeInnerX).abs() * box.width;

            if (standardMouthWidth > 1e-6) {
              final ratio = mouthWidth / standardMouthWidth;
              // 0.0-1.0の範囲に正規化
              // より小さな口を「小」と判定できるように、閾値を調整
              if (ratio < 0.8) {
                // ratio < 0.8の場合、0.0-0.4の範囲にマッピング（より小さな口が0.4未満になるように）
                mouthSizeFromMediaPipe = (ratio / 0.8 * 0.4).clamp(0.0, 0.4);
              } else if (ratio > 1.3) {
                mouthSizeFromMediaPipe = (0.6 + (ratio - 1.3) / 1.3 * 0.4).clamp(0.6, 1.0);
              } else {
                // 0.8-1.3の範囲を0.4-0.6にマッピング
                mouthSizeFromMediaPipe = (0.4 + (ratio - 0.8) / 0.5 * 0.2).clamp(0.4, 0.6);
              }
            }
          }
        }
      } catch (e) {
        print('[Mouth Size] MediaPipe error: $e');
      }
    }

    // Google ML Kitのデータから口の大きさを計算（フォールバック）
    double mouthSizeFromMLKit = 0.5;
    final leftEyeContour = f.contours[FaceContourType.leftEye]?.points ?? [];
    final rightEyeContour = f.contours[FaceContourType.rightEye]?.points ?? [];

    // 目の内側の角（鼻に近い側）を推定
    double leftEyeInnerX = leftEye.x.toDouble();
    double rightEyeInnerX = rightEye.x.toDouble();

    if (leftEyeContour.isNotEmpty) {
      final leftEyeInner = leftEyeContour.reduce((a, b) => a.x < b.x ? a : b);
      leftEyeInnerX = leftEyeInner.x.toDouble();
    }

    if (rightEyeContour.isNotEmpty) {
      final rightEyeInner = rightEyeContour.reduce((a, b) => a.x > b.x ? a : b);
      rightEyeInnerX = rightEyeInner.x.toDouble();
    }

    final standardMouthWidth = (rightEyeInnerX - leftEyeInnerX).abs();
    final actualMouthWidth = (rightMouth.x - leftMouth.x).abs();

    if (standardMouthWidth > 1e-6) {
      final ratio = actualMouthWidth / standardMouthWidth;
      // より小さな口を「小」と判定できるように、閾値を調整
      if (ratio < 0.8) {
        // ratio < 0.8の場合、0.0-0.4の範囲にマッピング（より小さな口が0.4未満になるように）
        mouthSizeFromMLKit = (ratio / 0.8 * 0.4).clamp(0.0, 0.4);
      } else if (ratio > 1.3) {
        mouthSizeFromMLKit = (0.6 + (ratio - 1.3) / 1.3 * 0.4).clamp(0.6, 1.0);
      } else {
        // 0.8-1.3の範囲を0.4-0.6にマッピング
        mouthSizeFromMLKit = (0.4 + (ratio - 0.8) / 0.5 * 0.2).clamp(0.4, 0.6);
      }
    }

    // MediaPipeとML Kitの結果を統合（MediaPipe 70%、ML Kit 30%）
    return (mouthSizeFromMediaPipe * 0.7 + mouthSizeFromMLKit * 0.3).clamp(0.0, 1.0);
  }

  // 眉の詳細特徴を抽出（人相学の本から学習・Google ML Kit + MediaPipe Face Mesh統合版）
  static Map<String, double> extractBrowFeaturesAdvanced(Face f) {
    // Google ML Kitのデータを取得
    final leftBrow = f.contours[FaceContourType.leftEyebrowTop]?.points ?? [];
    final rightBrow = f.contours[FaceContourType.rightEyebrowTop]?.points ?? [];
    final leftEye = f.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = f.landmarks[FaceLandmarkType.rightEye]?.position;

    // MediaPipe Face Mesh相当のデータを推定
    final box = f.boundingBox;
    final mediaPipeMesh = MediaPipeFaceMeshEstimator.estimateFromMLKit(
      f,
      imageWidth: box.width,
      imageHeight: box.height,
    );

    // 両方のデータソースから特徴を抽出
    final mlKitFeatures = _extractBrowFeaturesFromMLKit(f, leftBrow, rightBrow, leftEye, rightEye, box);
    final mediaPipeFeatures = mediaPipeMesh != null ? _extractBrowFeaturesFromMediaPipe(mediaPipeMesh, box) : null;

    // MediaPipe Face Meshの眉認識を確認（デバッグログ）
    if (mediaPipeMesh != null) {
      final leftBrowLandmarks = mediaPipeMesh.getLeftEyebrow();
      final rightBrowLandmarks = mediaPipeMesh.getRightEyebrow();
      print('[MediaPipe Face Mesh] 左眉のランドマーク数: ${leftBrowLandmarks.length}');
      print('[MediaPipe Face Mesh] 右眉のランドマーク数: ${rightBrowLandmarks.length}');
      if (leftBrowLandmarks.isNotEmpty && rightBrowLandmarks.isNotEmpty) {
        print(
            '[MediaPipe Face Mesh] 左眉の範囲: x=${leftBrowLandmarks.map((p) => p.x).reduce((a, b) => a < b ? a : b).toStringAsFixed(3)}-${leftBrowLandmarks.map((p) => p.x).reduce((a, b) => a > b ? a : b).toStringAsFixed(3)}, y=${leftBrowLandmarks.map((p) => p.y).reduce((a, b) => a < b ? a : b).toStringAsFixed(3)}-${leftBrowLandmarks.map((p) => p.y).reduce((a, b) => a > b ? a : b).toStringAsFixed(3)}');
        print(
            '[MediaPipe Face Mesh] 右眉の範囲: x=${rightBrowLandmarks.map((p) => p.x).reduce((a, b) => a < b ? a : b).toStringAsFixed(3)}-${rightBrowLandmarks.map((p) => p.x).reduce((a, b) => a > b ? a : b).toStringAsFixed(3)}, y=${rightBrowLandmarks.map((p) => p.y).reduce((a, b) => a < b ? a : b).toStringAsFixed(3)}-${rightBrowLandmarks.map((p) => p.y).reduce((a, b) => a > b ? a : b).toStringAsFixed(3)}');
      }
    } else {
      print('[MediaPipe Face Mesh] 眉のランドマークを取得できませんでした');
    }
    print('[Google ML Kit] 左眉のポイント数: ${leftBrow.length}');
    print('[Google ML Kit] 右眉のポイント数: ${rightBrow.length}');

    // 両方のデータソースを統合（MediaPipeのデータがあれば優先的に使用、なければML Kitのデータを使用）
    if (mediaPipeFeatures != null) {
      // MediaPipeのデータを50%、ML Kitのデータを50%で統合（よりバランスの取れた統合）
      // 眉の太さが1.00にクランプされないように、統合前に確認
      final mlKitThickness = mlKitFeatures['thickness']!;
      final mediaPipeThickness = mediaPipeFeatures['thickness']!;
      final integratedThickness = mediaPipeThickness * 0.5 + mlKitThickness * 0.5;
      // 1.00にクランプされている場合は、より細かい値に調整
      final finalThickness = integratedThickness >= 0.99
          ? (integratedThickness * 0.95).clamp(0.0, 0.99) // 1.00にクランプされている場合は0.95倍
          : integratedThickness;

      final integratedFeatures = <String, double>{
        'angle': mediaPipeFeatures['angle']! * 0.5 + mlKitFeatures['angle']! * 0.5,
        'length': mediaPipeFeatures['length']! * 0.5 + mlKitFeatures['length']! * 0.5,
        'thickness': finalThickness,
        'shape': mediaPipeFeatures['shape']! * 0.5 + mlKitFeatures['shape']! * 0.5,
        'glabellaWidth': mediaPipeFeatures['glabellaWidth']! * 0.5 + mlKitFeatures['glabellaWidth']! * 0.5,
        'neatness': mediaPipeFeatures['neatness']! * 0.5 + mlKitFeatures['neatness']! * 0.5,
        'eyeDistance': mediaPipeFeatures['eyeDistance']! * 0.5 + mlKitFeatures['eyeDistance']! * 0.5,
      };
      print(
          '[統合特徴] angle=${integratedFeatures['angle']!.toStringAsFixed(3)}, length=${integratedFeatures['length']!.toStringAsFixed(3)}, thickness=${integratedFeatures['thickness']!.toStringAsFixed(3)}, shape=${integratedFeatures['shape']!.toStringAsFixed(3)}, glabellaWidth=${integratedFeatures['glabellaWidth']!.toStringAsFixed(3)}, neatness=${integratedFeatures['neatness']!.toStringAsFixed(3)}');
      return integratedFeatures;
    }

    // MediaPipeのデータが取得できない場合はML Kitのデータのみを使用
    print('[統合特徴] MediaPipeのデータが取得できないため、ML Kitのデータのみを使用');
    return mlKitFeatures;
  }

  // Google ML Kitのデータから眉の特徴を抽出
  static Map<String, double> _extractBrowFeaturesFromMLKit(
    Face f,
    List leftBrow,
    List rightBrow,
    dynamic leftEye,
    dynamic rightEye,
    ui.Rect box,
  ) {
    if (leftBrow.isEmpty || rightBrow.isEmpty || leftEye == null || rightEye == null) {
      return {
        'angle': 0.0,
        'length': 0.5,
        'thickness': 0.5,
        'shape': 0.5,
        'glabellaWidth': 0.5,
        'neatness': 0.5,
        'eyeDistance': 0.5,
      };
    }

    // 目の輪郭を取得（眉と目の距離の計算に必要）
    final leftEyeContour = f.contours[FaceContourType.leftEye]?.points ?? [];
    final rightEyeContour = f.contours[FaceContourType.rightEye]?.points ?? [];

    // 1. 眉の角度（眉尻が上がっているか下がっているか）
    // X座標を使って、最も内側（鼻側）と最も外側（こめかみ側）を正確に特定
    // 左眉：X座標が小さい方が内側（鼻側）、大きい方が外側（こめかみ側）
    // 右眉：X座標が大きい方が内側（鼻側）、小さい方が外側（こめかみ側）
    final leftBrowXs = leftBrow.map((p) => p.x.toDouble()).toList();
    final leftBrowYs = leftBrow.map((p) => p.y.toDouble()).toList();
    final rightBrowXs = rightBrow.map((p) => p.x.toDouble()).toList();
    final rightBrowYs = rightBrow.map((p) => p.y.toDouble()).toList();

    // 左眉の内側（X座標が最小）と外側（X座標が最大）を特定
    final leftBrowInnerIndex = leftBrowXs.indexWhere((x) => x == leftBrowXs.reduce((a, b) => a < b ? a : b));
    final leftBrowOuterIndex = leftBrowXs.indexWhere((x) => x == leftBrowXs.reduce((a, b) => a > b ? a : b));

    // 右眉の内側（X座標が最大）と外側（X座標が最小）を特定
    final rightBrowInnerIndex = rightBrowXs.indexWhere((x) => x == rightBrowXs.reduce((a, b) => a > b ? a : b));
    final rightBrowOuterIndex = rightBrowXs.indexWhere((x) => x == rightBrowXs.reduce((a, b) => a < b ? a : b));

    // 内側と外側のY座標とX座標を取得
    final leftBrowInnerY = leftBrowYs[leftBrowInnerIndex];
    final leftBrowOuterY = leftBrowYs[leftBrowOuterIndex];
    final leftBrowInnerX = leftBrowXs[leftBrowInnerIndex];
    final leftBrowOuterX = leftBrowXs[leftBrowOuterIndex];

    final rightBrowInnerY = rightBrowYs[rightBrowInnerIndex];
    final rightBrowOuterY = rightBrowYs[rightBrowOuterIndex];
    final rightBrowInnerX = rightBrowXs[rightBrowInnerIndex];
    final rightBrowOuterX = rightBrowXs[rightBrowOuterIndex];

    // 眉の角度を計算（内側から外側への角度）
    // より正確な角度計算のため、眉の全体的な傾きを計算
    // 眉の輪郭ポイント全体を使用して、最小二乗法で直線を近似し、その傾きを計算

    // 左眉の傾きを計算（複数のポイントを使用してより正確に）
    double leftBrowAngle = 0.0;
    if (leftBrowXs.length >= 3) {
      // 最小二乗法で直線を近似して、より正確な角度を計算
      double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
      final n = leftBrowXs.length.toDouble();

      for (int i = 0; i < leftBrowXs.length; i++) {
        final x = leftBrowXs[i] / box.width; // 正規化
        final y = leftBrowYs[i] / box.height; // 正規化
        sumX += x;
        sumY += y;
        sumXY += x * y;
        sumX2 += x * x;
      }

      final denominator = n * sumX2 - sumX * sumX;
      if (denominator.abs() > 1e-6) {
        // 最小二乗法で傾きを計算
        final slope = (n * sumXY - sumX * sumY) / denominator;
        // 傾きから角度を計算（ラジアン）
        final angleRad = math.atan(slope);
        // -0.52ラジアン（-30度）から+0.52ラジアン（+30度）を-1.0から+1.0にマッピング
        leftBrowAngle = (angleRad / 0.52).clamp(-1.0, 1.0);
      }
    } else if (leftBrowXs.length >= 2) {
      // ポイントが少ない場合は、最初と最後のポイントを使用
      final leftBrowStartY = leftBrowYs.first;
      final leftBrowEndY = leftBrowYs.last;
      final leftBrowStartX = leftBrowXs.first;
      final leftBrowEndX = leftBrowXs.last;

      final leftBrowWidth = (leftBrowEndX - leftBrowStartX).abs();
      if (leftBrowWidth > 0.0) {
        final leftBrowHeight = leftBrowStartY - leftBrowEndY;

        final normalizedHeight = leftBrowHeight / box.height;
        final normalizedWidth = leftBrowWidth / box.width;

        final angleRad = math.atan2(normalizedHeight, normalizedWidth);
        leftBrowAngle = (angleRad / 0.52).clamp(-1.0, 1.0);
      }
    }

    // 右眉の傾きを計算（複数のポイントを使用してより正確に）
    double rightBrowAngle = 0.0;
    if (rightBrowXs.length >= 3) {
      // 最小二乗法で直線を近似して、より正確な角度を計算
      double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
      final n = rightBrowXs.length.toDouble();

      for (int i = 0; i < rightBrowXs.length; i++) {
        final x = rightBrowXs[i] / box.width; // 正規化
        final y = rightBrowYs[i] / box.height; // 正規化
        sumX += x;
        sumY += y;
        sumXY += x * y;
        sumX2 += x * x;
      }

      final denominator = n * sumX2 - sumX * sumX;
      if (denominator.abs() > 1e-6) {
        // 最小二乗法で傾きを計算
        final slope = (n * sumXY - sumX * sumY) / denominator;
        // 傾きから角度を計算（ラジアン）
        final angleRad = math.atan(slope);
        // 右眉は逆方向なので、符号を反転
        rightBrowAngle = (-angleRad / 0.52).clamp(-1.0, 1.0);
      }
    } else if (rightBrowXs.length >= 2) {
      // ポイントが少ない場合は、最初と最後のポイントを使用
      final rightBrowStartY = rightBrowYs.first;
      final rightBrowEndY = rightBrowYs.last;
      final rightBrowStartX = rightBrowXs.first;
      final rightBrowEndX = rightBrowXs.last;

      final rightBrowWidth = (rightBrowStartX - rightBrowEndX).abs();
      if (rightBrowWidth > 0.0) {
        final rightBrowHeight = rightBrowStartY - rightBrowEndY;

        final normalizedHeight = rightBrowHeight / box.height;
        final normalizedWidth = rightBrowWidth / box.width;

        final angleRad = math.atan2(normalizedHeight, normalizedWidth);
        rightBrowAngle = (angleRad / 0.52).clamp(-1.0, 1.0);
      }
    }

    final avgBrowAngle = (leftBrowAngle + rightBrowAngle) / 2.0;

    // デバッグログ（実際の値を確認）
    print(
        '[眉の角度計算(ML Kit)] leftBrowAngle: ${leftBrowAngle.toStringAsFixed(4)}, rightBrowAngle: ${rightBrowAngle.toStringAsFixed(4)}, avgBrowAngle: ${avgBrowAngle.toStringAsFixed(4)}');

    // 2. 眉の長さ（目の幅との比較）
    final leftBrowLength = _dist(leftBrow.first.x, leftBrow.first.y, leftBrow.last.x, leftBrow.last.y);
    final rightBrowLength = _dist(rightBrow.first.x, rightBrow.first.y, rightBrow.last.x, rightBrow.last.y);
    final avgBrowLength = (leftBrowLength + rightBrowLength) / 2.0;
    final eyeWidth = (rightEye.x - leftEye.x).abs();
    final browLengthRatio = eyeWidth > 0 ? (avgBrowLength / eyeWidth) : 1.0;
    // 標準は目の幅より少し長め（1.0-1.2程度）
    // より細かい数値を出すため、範囲を広げて正規化（0.5-2.0の範囲を0.0-1.0にマッピング）
    final normalizedLength = ((browLengthRatio - 0.5) / 1.5).clamp(0.0, 1.0);

    // 3. 眉の太さ（濃さ）- 輪郭の面積から推定
    final leftBrowArea = _estimateContourArea(leftBrow);
    final rightBrowArea = _estimateContourArea(rightBrow);
    final avgBrowArea = (leftBrowArea + rightBrowArea) / 2.0;
    // 基準値を調整：眉の面積は顔の面積の0.01-0.05程度が標準範囲
    // より濃い眉を検出できるように、基準値を調整
    final baseArea = box.width * box.height * 0.015; // 基準値を0.02から0.015に調整（より濃い眉が検出されやすく）
    // 範囲を調整：0.2-2.0の範囲を0.0-1.0にマッピング（より濃い眉が0.65以上になりやすく）
    // 標準的な眉の面積比は約0.5-1.0程度（baseAreaの0.5-1.0倍 = rawRatio 0.5-1.0）
    // これが0.17-0.33の範囲にマッピングされる（中（標準的））
    final rawRatio = avgBrowArea / baseArea;
    // 0.2-2.0の範囲を0.0-1.0にマッピング（範囲を狭くして、より濃い眉が0.65以上になりやすく）
    // 標準的な眉（rawRatio 0.5-1.0）は0.17-0.33の範囲にマッピング（中（標準的））
    // 薄い眉（rawRatio < 0.5）は0.17未満（小（淡い））
    // 濃い眉（rawRatio > 1.0）は0.33以上（大（濃い））- rawRatio > 1.4で0.65以上になる
    final browThickness = ((rawRatio - 0.2) / 1.8).clamp(0.0, 1.0);

    // デバッグログ（実際の値を確認）
    print(
        '[眉の濃さ計算] avgBrowArea: ${avgBrowArea.toStringAsFixed(2)}, baseArea: ${baseArea.toStringAsFixed(2)}, rawRatio: ${rawRatio.toStringAsFixed(2)}, browThickness: ${browThickness.toStringAsFixed(2)}');

    // 4. 眉の形状（曲線/直線）- カーブの度合い（根本的改善版：全ランドマークから直線への偏差を計算）
    double browCurvature = 0.5;
    if (leftBrow.length >= 3 && rightBrow.length >= 3) {
      // 【根本的改善】眉のランドマークポイント全体を使って、直線からの偏差を計算
      // これにより、眉山の位置に関係なく、眉全体の曲線度を正確に評価できる

      final leftBrowPoints = leftBrow.map((p) => ui.Offset(p.x.toDouble(), p.y.toDouble())).toList();
      final rightBrowPoints = rightBrow.map((p) => ui.Offset(p.x.toDouble(), p.y.toDouble())).toList();

      // 左眉の曲線度を計算
      double leftCurvature = TutorialClassifier._calculateBrowCurvature(leftBrowPoints, box);
      // 右眉の曲線度を計算
      double rightCurvature = TutorialClassifier._calculateBrowCurvature(rightBrowPoints, box);

      // 左右の平均を取る
      browCurvature = (leftCurvature + rightCurvature) / 2.0;
    }

    // 5. 眉間の幅（眉頭と眉頭の間の距離）
    // leftBrowInnerXとrightBrowInnerXは既に眉の角度計算で定義済み
    // ML Kitのランドマークはピクセル座標で提供されているため、box.widthで正規化
    final glabellaWidthRaw = (rightBrowInnerX - leftBrowInnerX).abs() / box.width;
    // より多様な値を得るため、正規化範囲を調整
    // 実際の眉間の幅は通常0.05-0.15（顔幅の5-15%）の範囲
    // 0.05-0.20の範囲を0.0-1.0にマッピング（より多様な値を得るため）
    final normalizedGlabellaWidth = ((glabellaWidthRaw - 0.05) / 0.15).clamp(0.0, 1.0);

    // デバッグログ
    print('[ML Kit] 眉間の幅: raw=$glabellaWidthRaw, normalized=$normalizedGlabellaWidth');
    if (glabellaWidthRaw < 0.05 || glabellaWidthRaw > 0.20) {
      print('[ML Kit] 眉間の幅が範囲外: raw=$glabellaWidthRaw, normalized=$normalizedGlabellaWidth');
    }

    // 6. 眉の整い（乱れているか）- ポイントの分散から推定
    double browNeatness = 0.5;
    if (leftBrow.length >= 3 && rightBrow.length >= 3) {
      // 眉のポイントのY座標の標準偏差を計算
      final leftBrowYs = leftBrow.map((p) => p.y.toDouble()).toList();
      final rightBrowYs = rightBrow.map((p) => p.y.toDouble()).toList();
      final leftAvgY = leftBrowYs.reduce((a, b) => a + b) / leftBrowYs.length;
      final rightAvgY = rightBrowYs.reduce((a, b) => a + b) / rightBrowYs.length;

      final leftVariance = leftBrowYs.map((y) => math.pow(y - leftAvgY, 2)).reduce((a, b) => a + b) / leftBrowYs.length;
      final rightVariance =
          rightBrowYs.map((y) => math.pow(y - rightAvgY, 2)).reduce((a, b) => a + b) / rightBrowYs.length;
      final avgVariance = (leftVariance + rightVariance) / 2.0;

      // 分散が小さいほど整っている
      // より細かい数値を出すため、基準値を調整（0.0-0.0002の範囲を0.0-1.0にマッピング）
      final baseVariance = box.height * box.height * 0.0001;
      final varianceNormalized = (avgVariance / baseVariance).clamp(0.0, 2.0) / 2.0;
      browNeatness = (1.0 - varianceNormalized).clamp(0.0, 1.0);
    }

    // 7. 眉と目の距離（眉の下縁から目の上縁までの距離）
    double browEyeDistance = 0.5;
    if (leftEyeContour.isNotEmpty && rightEyeContour.isNotEmpty && leftBrow.isNotEmpty && rightBrow.isNotEmpty) {
      // 眉の下縁をより正確に取得
      // 眉の上縁のY座標（最小Y座標）を取得
      final leftBrowTopY = leftBrow.map((p) => p.y.toDouble()).reduce((a, b) => a < b ? a : b);
      final rightBrowTopY = rightBrow.map((p) => p.y.toDouble()).reduce((a, b) => a < b ? a : b);

      // 眉の厚みを推定（眉のY座標の範囲から）
      final leftBrowYRange = leftBrow.map((p) => p.y.toDouble()).reduce((a, b) => a > b ? a : b) -
          leftBrow.map((p) => p.y.toDouble()).reduce((a, b) => a < b ? a : b);
      final rightBrowYRange = rightBrow.map((p) => p.y.toDouble()).reduce((a, b) => a > b ? a : b) -
          rightBrow.map((p) => p.y.toDouble()).reduce((a, b) => a < b ? a : b);
      final avgBrowThickness = ((leftBrowYRange + rightBrowYRange) / 2.0) / box.height;

      // 眉の下縁 = 眉の上縁 + 眉の厚み（顔の高さの2-5%程度を標準として使用）
      // 眉の厚みが小さい場合は、標準的な厚み（顔の高さの3%）を使用
      final estimatedBrowThickness = avgBrowThickness > 0.01 ? avgBrowThickness : 0.03;
      final leftBrowBottomY = leftBrowTopY + (box.height * estimatedBrowThickness);
      final rightBrowBottomY = rightBrowTopY + (box.height * estimatedBrowThickness);
      final avgBrowBottomY = (leftBrowBottomY + rightBrowBottomY) / 2.0;

      // 目の上縁（最も高いY座標 = 最小Y座標）
      final leftEyeTopY = leftEyeContour.map((p) => p.y.toDouble()).reduce((a, b) => a < b ? a : b);
      final rightEyeTopY = rightEyeContour.map((p) => p.y.toDouble()).reduce((a, b) => a < b ? a : b);
      final avgEyeTopY = (leftEyeTopY + rightEyeTopY) / 2.0;

      // 眉と目の距離（顔の高さで正規化）
      // 距離が正の値であることを確認（目の上縁が眉の下縁より下にある）
      final rawDistance = (avgEyeTopY - avgBrowBottomY) / box.height;

      // 距離が負の値（眉と目が重なっている）場合は、最小距離として0.01を使用
      final distance = rawDistance > 0 ? rawDistance : 0.01;

      // 標準は顔の高さの0.03-0.18程度（0.03=近い、0.18=遠い）
      // 範囲を調整：0.01-0.25の範囲を0.0-1.0にマッピング（距離が近い=高値、距離が遠い=低値）
      // より正確な距離計算のため、実際の距離範囲に合わせて正規化
      final normalizedDistance = ((distance - 0.01) / 0.24).clamp(0.0, 1.0);
      // 反転（距離が近い=高値、距離が遠い=低値）
      // eyeDistanceは値が高いほど距離が近いことを示す
      browEyeDistance = 1.0 - normalizedDistance;

      // 極端な値を防ぐため、最終的な値を0.1-0.9の範囲に制限
      // これにより、0.01や0.99などの極端な値が出ないようにする
      browEyeDistance = browEyeDistance.clamp(0.1, 0.9);

      // デバッグログ（実際の値を確認）
      print(
          '[眉と目の距離計算(ML Kit)] rawDistance: ${rawDistance.toStringAsFixed(4)}, distance: ${distance.toStringAsFixed(4)}, normalizedDistance: ${normalizedDistance.toStringAsFixed(4)}, browEyeDistance: ${browEyeDistance.toStringAsFixed(4)}, estimatedBrowThickness: ${estimatedBrowThickness.toStringAsFixed(4)}');
    }

    return {
      'angle': avgBrowAngle.clamp(-1.0, 1.0),
      'length': normalizedLength,
      'thickness': browThickness,
      'shape': browCurvature,
      'glabellaWidth': normalizedGlabellaWidth,
      'neatness': browNeatness,
      'eyeDistance': browEyeDistance,
    };
  }

  // MediaPipe Face Meshのデータから眉の特徴を抽出（10個のランドマークを使用）
  static Map<String, double> _extractBrowFeaturesFromMediaPipe(MediaPipeFaceMesh mesh, ui.Rect box) {
    final leftBrowLandmarks = mesh.getLeftEyebrow();
    final rightBrowLandmarks = mesh.getRightEyebrow();
    final leftEyeLandmarks = mesh.getLeftEye();
    final rightEyeLandmarks = mesh.getRightEye();

    if (leftBrowLandmarks.isEmpty ||
        rightBrowLandmarks.isEmpty ||
        leftEyeLandmarks.isEmpty ||
        rightEyeLandmarks.isEmpty) {
      return {
        'angle': 0.0,
        'length': 0.5,
        'thickness': 0.5,
        'shape': 0.5,
        'glabellaWidth': 0.5,
        'neatness': 0.5,
        'eyeDistance': 0.5,
      };
    }

    // 1. 眉の角度（10個のランドマークからより正確に計算）
    // 最小二乗法で直線を近似して、より正確な角度を計算
    double leftBrowAngle = 0.0;
    if (leftBrowLandmarks.length >= 3) {
      // 最小二乗法で直線を近似
      double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
      final n = leftBrowLandmarks.length.toDouble();

      for (final landmark in leftBrowLandmarks) {
        final x = landmark.x;
        final y = landmark.y;
        sumX += x;
        sumY += y;
        sumXY += x * y;
        sumX2 += x * x;
      }

      final denominator = n * sumX2 - sumX * sumX;
      if (denominator.abs() > 1e-6) {
        // 最小二乗法で傾きを計算
        final slope = (n * sumXY - sumX * sumY) / denominator;
        // 傾きから角度を計算（ラジアン）
        final angleRad = math.atan(slope);
        // -0.52ラジアン（-30度）から+0.52ラジアン（+30度）を-1.0から+1.0にマッピング
        leftBrowAngle = (angleRad / 0.52).clamp(-1.0, 1.0);
      }
    } else if (leftBrowLandmarks.length >= 2) {
      // ポイントが少ない場合は、最初と最後のポイントを使用
      final leftBrowStart = leftBrowLandmarks.first;
      final leftBrowEnd = leftBrowLandmarks.last;
      final leftBrowWidth = (leftBrowEnd.x - leftBrowStart.x).abs();
      if (leftBrowWidth > 0.0) {
        final leftBrowHeight = leftBrowStart.y - leftBrowEnd.y;
        final angleRad = math.atan2(leftBrowHeight, leftBrowWidth);
        leftBrowAngle = (angleRad / 0.52).clamp(-1.0, 1.0);
      }
    }

    double rightBrowAngle = 0.0;
    if (rightBrowLandmarks.length >= 3) {
      // 最小二乗法で直線を近似
      double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
      final n = rightBrowLandmarks.length.toDouble();

      for (final landmark in rightBrowLandmarks) {
        final x = landmark.x;
        final y = landmark.y;
        sumX += x;
        sumY += y;
        sumXY += x * y;
        sumX2 += x * x;
      }

      final denominator = n * sumX2 - sumX * sumX;
      if (denominator.abs() > 1e-6) {
        // 最小二乗法で傾きを計算
        final slope = (n * sumXY - sumX * sumY) / denominator;
        // 傾きから角度を計算（ラジアン）
        final angleRad = math.atan(slope);
        // 右眉は逆方向なので、符号を反転
        rightBrowAngle = (-angleRad / 0.52).clamp(-1.0, 1.0);
      }
    } else if (rightBrowLandmarks.length >= 2) {
      // ポイントが少ない場合は、最初と最後のポイントを使用
      final rightBrowStart = rightBrowLandmarks.first;
      final rightBrowEnd = rightBrowLandmarks.last;
      final rightBrowWidth = (rightBrowStart.x - rightBrowEnd.x).abs();
      if (rightBrowWidth > 0.0) {
        final rightBrowHeight = rightBrowStart.y - rightBrowEnd.y;
        final angleRad = math.atan2(rightBrowHeight, rightBrowWidth);
        rightBrowAngle = (angleRad / 0.52).clamp(-1.0, 1.0);
      }
    }

    final avgBrowAngle = (leftBrowAngle + rightBrowAngle) / 2.0;

    // デバッグログ（実際の値を確認）
    print(
        '[眉の角度計算(MediaPipe)] leftBrowAngle: ${leftBrowAngle.toStringAsFixed(4)}, rightBrowAngle: ${rightBrowAngle.toStringAsFixed(4)}, avgBrowAngle: ${avgBrowAngle.toStringAsFixed(4)}');

    // 2. 眉の長さ（10個のランドマークからより正確に計算）
    double leftBrowLength = 0.0;
    for (int i = 0; i < leftBrowLandmarks.length - 1; i++) {
      leftBrowLength += leftBrowLandmarks[i].distanceTo(leftBrowLandmarks[i + 1]);
    }
    double rightBrowLength = 0.0;
    for (int i = 0; i < rightBrowLandmarks.length - 1; i++) {
      rightBrowLength += rightBrowLandmarks[i].distanceTo(rightBrowLandmarks[i + 1]);
    }
    final avgBrowLength = (leftBrowLength + rightBrowLength) / 2.0;

    // 目の幅を計算（目のランドマークから）- 正規化された座標を使用
    final leftEyeWidth =
        leftEyeLandmarks.map((p) => p.x).reduce(math.max) - leftEyeLandmarks.map((p) => p.x).reduce(math.min);
    final rightEyeWidth =
        rightEyeLandmarks.map((p) => p.x).reduce(math.max) - rightEyeLandmarks.map((p) => p.x).reduce(math.min);
    final eyeWidth = ((leftEyeWidth + rightEyeWidth) / 2.0) * box.width;

    // 眉の長さは正規化された座標での距離なので、box.widthを掛けて実際の距離に変換
    final browLengthActual = avgBrowLength * box.width;
    final browLengthRatio = eyeWidth > 0 ? (browLengthActual / eyeWidth) : 1.0;
    // より細かい数値を出すため、範囲を広げて正規化（0.5-2.0の範囲を0.0-1.0にマッピング）
    final normalizedLength = ((browLengthRatio - 0.5) / 1.5).clamp(0.0, 1.0);

    // 3. 眉の太さ（10個のランドマークのY座標の範囲から推定）- 正規化された座標を使用
    final leftBrowYRange =
        leftBrowLandmarks.map((p) => p.y).reduce(math.max) - leftBrowLandmarks.map((p) => p.y).reduce(math.min);
    final rightBrowYRange =
        rightBrowLandmarks.map((p) => p.y).reduce(math.max) - rightBrowLandmarks.map((p) => p.y).reduce(math.min);
    final avgBrowYRange = (leftBrowYRange + rightBrowYRange) / 2.0;
    // 正規化された座標（0.0-1.0）なので、そのまま使用
    // 範囲を調整：0.005-0.06の範囲を0.0-1.0にマッピング（より濃い眉が0.65以上になりやすく）
    // より濃い眉を検出できるように、正規化範囲を調整
    // 標準的な眉のY座標範囲は約0.01-0.03程度（0.09-0.45の範囲にマッピング）
    // 薄い眉は0.005-0.01（0.0-0.09）、濃い眉は0.04-0.06（0.64-1.0）- より濃い眉が0.65以上になりやすい
    final browThickness = ((avgBrowYRange - 0.005) / 0.055).clamp(0.0, 1.0);

    // デバッグログ（実際の値を確認）
    print(
        '[眉の濃さ計算(MediaPipe)] avgBrowYRange: ${avgBrowYRange.toStringAsFixed(4)}, browThickness: ${browThickness.toStringAsFixed(2)}');

    // 4. 眉の形状（10個のランドマークからより正確に計算・根本的改善版：全ランドマークから直線への偏差を計算）
    // 【根本的改善】眉のランドマークポイント全体を使って、直線からの偏差を計算
    // これにより、眉山の位置に関係なく、眉全体の曲線度を正確に評価できる

    final leftBrowPoints = leftBrowLandmarks.map((p) => ui.Offset(p.x, p.y)).toList();
    final rightBrowPoints = rightBrowLandmarks.map((p) => ui.Offset(p.x, p.y)).toList();

    // 左眉の曲線度を計算（正規化された座標なので、box.heightで割る必要はない）
    double leftCurvature = TutorialClassifier._calculateBrowCurvatureNormalized(leftBrowPoints);
    // 右眉の曲線度を計算
    double rightCurvature = TutorialClassifier._calculateBrowCurvatureNormalized(rightBrowPoints);

    // 左右の平均を取る
    final browCurvature = (leftCurvature + rightCurvature) / 2.0;

    // 5. 眉間の幅（10個のランドマークからより正確に計算）
    final leftBrowInnerX = leftBrowLandmarks.first.x;
    final rightBrowInnerX = rightBrowLandmarks.first.x;
    // MediaPipeのランドマークは画像全体の正規化座標（0.0-1.0）で提供されている
    // 顔のバウンディングボックス内の相対座標に変換する必要がある
    // ただし、MediaPipeの座標は既に正規化されているので、そのまま使用
    final glabellaWidthRaw = (rightBrowInnerX - leftBrowInnerX).abs();

    // より多様な値を得るため、正規化範囲を調整
    // MediaPipeの値は0.1-0.4の範囲が多いため、この範囲を0.0-1.0にマッピング
    // 0.1-0.4の範囲を0.0-1.0にマッピング（より多様な値を得るため）
    final normalizedGlabellaWidth = ((glabellaWidthRaw - 0.1) / 0.3).clamp(0.0, 1.0);

    // デバッグログ
    print('[MediaPipe] 眉間の幅: raw=$glabellaWidthRaw, normalized=$normalizedGlabellaWidth');
    if (glabellaWidthRaw < 0.1 || glabellaWidthRaw > 0.4) {
      print('[MediaPipe] 眉間の幅が範囲外: raw=$glabellaWidthRaw, normalized=$normalizedGlabellaWidth');
    }

    // 6. 眉の整い（10個のランドマークの分散からより正確に計算）
    final leftBrowYs = leftBrowLandmarks.map((p) => p.y).toList();
    final rightBrowYs = rightBrowLandmarks.map((p) => p.y).toList();
    final leftAvgY = leftBrowYs.reduce((a, b) => a + b) / leftBrowYs.length;
    final rightAvgY = rightBrowYs.reduce((a, b) => a + b) / rightBrowYs.length;
    final leftVariance = leftBrowYs.map((y) => math.pow(y - leftAvgY, 2)).reduce((a, b) => a + b) / leftBrowYs.length;
    final rightVariance =
        rightBrowYs.map((y) => math.pow(y - rightAvgY, 2)).reduce((a, b) => a + b) / rightBrowYs.length;
    final avgVariance = (leftVariance + rightVariance) / 2.0;

    // 7. 眉と目の距離（眉の下縁から目の上縁までの距離）
    // より正確な距離計算のため、目の上端専用ランドマークを使用
    double browEyeDistance = 0.5;

    // 目の上端ランドマークを取得（専用のランドマークを使用）
    final leftEyeTopLandmarks = mesh.getLeftEyeTop();
    final rightEyeTopLandmarks = mesh.getRightEyeTop();

    if (leftEyeTopLandmarks.isNotEmpty && rightEyeTopLandmarks.isNotEmpty) {
      // 眉の下縁をより正確に取得
      // 眉の上縁のY座標（最小Y座標）を取得
      final leftBrowTopY = leftBrowYs.reduce((a, b) => a < b ? a : b);
      final rightBrowTopY = rightBrowYs.reduce((a, b) => a < b ? a : b);

      // 眉の厚みを推定（眉のY座標の範囲から）
      final leftBrowYRange = leftBrowYs.reduce((a, b) => a > b ? a : b) - leftBrowYs.reduce((a, b) => a < b ? a : b);
      final rightBrowYRange = rightBrowYs.reduce((a, b) => a > b ? a : b) - rightBrowYs.reduce((a, b) => a < b ? a : b);
      final avgBrowThickness = (leftBrowYRange + rightBrowYRange) / 2.0;

      // 眉の下縁 = 眉の上縁 + 眉の厚み
      // 眉の厚みが小さい場合は、標準的な厚み（0.02）を使用
      final estimatedBrowThickness = avgBrowThickness > 0.01 ? avgBrowThickness : 0.02;
      final leftBrowBottomY = leftBrowTopY + estimatedBrowThickness;
      final rightBrowBottomY = rightBrowTopY + estimatedBrowThickness;
      final avgBrowBottomY = (leftBrowBottomY + rightBrowBottomY) / 2.0;

      // 目の上縁（専用のランドマークから最小Y座標を取得）
      final leftEyeTopY = leftEyeTopLandmarks.map((p) => p.y).reduce((a, b) => a < b ? a : b);
      final rightEyeTopY = rightEyeTopLandmarks.map((p) => p.y).reduce((a, b) => a < b ? a : b);
      final avgEyeTopY = (leftEyeTopY + rightEyeTopY) / 2.0;

      // 眉と目の距離（正規化された座標なので、そのまま使用）
      // 距離が正の値であることを確認（目の上縁が眉の下縁より下にある）
      final rawDistance = avgEyeTopY - avgBrowBottomY;

      // 距離が負の値（眉と目が重なっている）場合は、最小距離として0.01を使用
      final distance = rawDistance > 0 ? rawDistance : 0.01;

      // 標準は0.03-0.18程度（0.03=近い、0.18=遠い）
      // 範囲を調整：0.01-0.25の範囲を0.0-1.0にマッピング（距離が近い=高値、距離が遠い=低値）
      // より正確な距離計算のため、実際の距離範囲に合わせて正規化
      final normalizedDistance = ((distance - 0.01) / 0.24).clamp(0.0, 1.0);
      // 反転（距離が近い=高値、距離が遠い=低値）
      // eyeDistanceは値が高いほど距離が近いことを示す
      browEyeDistance = 1.0 - normalizedDistance;

      // 極端な値を防ぐため、最終的な値を0.1-0.9の範囲に制限
      // これにより、0.01や0.99などの極端な値が出ないようにする
      browEyeDistance = browEyeDistance.clamp(0.1, 0.9);

      // デバッグログ（実際の値を確認）
      print(
          '[眉と目の距離計算(MediaPipe)] rawDistance: ${rawDistance.toStringAsFixed(4)}, distance: ${distance.toStringAsFixed(4)}, normalizedDistance: ${normalizedDistance.toStringAsFixed(4)}, browEyeDistance: ${browEyeDistance.toStringAsFixed(4)}, estimatedBrowThickness: ${estimatedBrowThickness.toStringAsFixed(4)}');
    }

    // より細かい数値を出すため、基準値を調整（0.0-0.0002の範囲を0.0-1.0にマッピング）
    final baseVariance = box.height * box.height * 0.0001;
    final varianceNormalized = (avgVariance / baseVariance).clamp(0.0, 2.0) / 2.0;
    final browNeatness = (1.0 - varianceNormalized).clamp(0.0, 1.0);

    return {
      'angle': avgBrowAngle.clamp(-1.0, 1.0),
      'length': normalizedLength,
      'thickness': browThickness,
      'shape': browCurvature,
      'glabellaWidth': normalizedGlabellaWidth,
      'neatness': browNeatness,
      'eyeDistance': browEyeDistance,
    };
  }

  // 眉角度の推定（左右の眉の位置から・高精度版）
  static double _estimateBrowAngleAdvanced(Face f) {
    final browFeatures = extractBrowFeaturesAdvanced(f);
    return browFeatures['angle'] ?? 0.0;
  }

  // 三停推定: 額〜眉 / 眉〜鼻下 / 鼻下〜顎先 の比率（MediaPipe Face Mesh相当・高精度版）
  /// 実際の顔の特徴から陰陽を推定
  static String _estimatePolarityAdvanced(Face f) {
    final browFeatures = extractBrowFeaturesAdvanced(f);
    final browAngle = browFeatures['angle'] ?? 0.0;
    final browThickness = browFeatures['thickness'] ?? 0.5;
    final browShape = browFeatures['shape'] ?? 0.5;
    final glabellaWidth = browFeatures['glabellaWidth'] ?? 0.5;
    final browNeatness = browFeatures['neatness'] ?? 0.5;

    double yangScore = 0.0;

    // 眉が上がっている → 陽
    if (browAngle > 0.2) yangScore += 0.3;
    if (browAngle < -0.2) yangScore -= 0.3;

    // 眉が濃い（太い） → 陽
    if (browThickness > 0.7) yangScore += 0.2;
    if (browThickness < 0.3) yangScore -= 0.2;

    // 眉が直線 → 陽（積極的）
    if (browShape < 0.3) yangScore += 0.15;
    if (browShape > 0.7) yangScore -= 0.15;

    // 眉間が広い → 陽（楽天家、社交性）
    if (glabellaWidth > 0.7) yangScore += 0.2;
    if (glabellaWidth < 0.3) yangScore -= 0.2;

    // 眉が整っている → 陽（協調性）
    if (browNeatness > 0.7) yangScore += 0.15;
    if (browNeatness < 0.3) yangScore -= 0.15;

    // 目の特徴も考慮
    final eyeBalance = _estimateEyeBalanceAdvanced(f);
    final eyeFeatures = extractEyeFeaturesForDiagnosis(f);
    final eyeSize = eyeFeatures['size'] ?? 0.5;

    if (eyeBalance > 0.7 && eyeSize > 0.6) yangScore += 0.1;
    if (eyeBalance < 0.3 && eyeSize < 0.4) yangScore -= 0.1;

    // 閾値で判定
    if (yangScore > 0.3) return '陽';
    if (yangScore < -0.3) return '陰';
    return yangScore > 0 ? '陽' : '陰';
  }

  static String _estimateZoneAdvanced(Face f) {
    final box = f.boundingBox;
    final facePts = f.contours[FaceContourType.face]?.points ?? [];
    final jawBottomY = facePts.isNotEmpty ? facePts.map((p) => p.y).reduce(math.max).toDouble() : box.bottom;

    // 眉の推定（左右の目頭/目尻から眉中央を推定）
    final leftEyeInner = f.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEyeInner = f.landmarks[FaceLandmarkType.rightEye]?.position;
    final browY = leftEyeInner != null && rightEyeInner != null
        ? ((leftEyeInner.y + rightEyeInner.y) / 2.0 - box.height * 0.08).clamp(box.top, box.bottom)
        : (box.top + box.height * 0.25);

    // 鼻の基部（鼻先より上）
    final noseBase = f.landmarks[FaceLandmarkType.noseBase]?.position;
    final noseY = noseBase != null ? noseBase.y : (box.center.dy); // フォールバック

    final foreheadTopY = box.top;
    final upper = (browY - foreheadTopY).abs();
    final middle = (noseY - browY).abs();
    final lower = (jawBottomY - noseY).abs();

    // より正確な比率判定（誤差許容範囲を考慮）
    final total = upper + middle + lower;
    if (total < 1e-6) return '中停'; // フォールバック
    final upperRatio = upper / total;
    final middleRatio = middle / total;
    final lowerRatio = lower / total;

    if (upperRatio >= middleRatio && upperRatio >= lowerRatio) return '上停';
    if (middleRatio >= lowerRatio) return '中停';
    return '下停';
  }

  // 顎曲率の高精度推定（輪郭が直線的=小、丸い=大・MediaPipe相当）
  static double _estimateJawCurvatureAdvanced(Face f) {
    final pts = f.contours[FaceContourType.face]?.points ?? [];
    if (pts.length < 4) return 0.4;

    // 複数セグメントで曲率を計算（より高精度）
    double totalCurvature = 0.0;
    int segments = 0;
    for (int i = 0; i < pts.length - 2; i += math.max(1, pts.length ~/ 10)) {
      final a = pts[i];
      final b = pts[math.min(i + 1, pts.length - 1)];
      final c = pts[math.min(i + 2, pts.length - 1)];
      final ab = _dist(a.x, a.y, b.x, b.y);
      final bc = _dist(b.x, b.y, c.x, c.y);
      final ac = _dist(a.x, a.y, c.x, c.y);
      if (ac > 1e-6) {
        final detour = (ab + bc) / ac;
        totalCurvature += (detour - 1.0).clamp(0.0, 1.0);
        segments++;
      }
    }

    return segments > 0 ? (totalCurvature / segments).clamp(0.0, 1.0) : 0.4;
  }

  // 顔形の高精度推定
  // 顔の形を判定（MediaPipe Face Mesh + Google ML Kit統合版）
  static String _estimateFaceShapeAdvanced(Face f) {
    final box = f.boundingBox;

    // MediaPipe Face Mesh相当のデータを推定
    final mediaPipeMesh = MediaPipeFaceMeshEstimator.estimateFromMLKit(
      f,
      imageWidth: box.width,
      imageHeight: box.height,
    );

    // Google ML Kitのデータから曲率を計算
    final curv = _estimateJawCurvatureAdvanced(f);
    final width = box.width;
    final height = box.height;
    final aspectRatio = width / height;

    // MediaPipe Face Meshのデータから顔の輪郭を取得（優先）
    double curvFromMediaPipe = curv;
    if (mediaPipeMesh != null) {
      try {
        final faceOval = mediaPipeMesh.getFaceOval();
        if (faceOval.length >= 10) {
          // 顔の輪郭から曲率を計算
          final faceOvalYs = faceOval.map((p) => p.y).toList();
          final faceOvalXs = faceOval.map((p) => p.x).toList();
          final minY = faceOvalYs.reduce((a, b) => a < b ? a : b);
          final maxY = faceOvalYs.reduce((a, b) => a > b ? a : b);
          final centerX = faceOvalXs.reduce((a, b) => a + b) / faceOvalXs.length;

          // 顎の部分（下1/3）の曲率を計算
          final jawPoints = faceOval.where((p) => p.y > minY + (maxY - minY) * 0.67).toList();
          if (jawPoints.length >= 3) {
            final jawXs = jawPoints.map((p) => p.x).toList();
            final jawLeft = jawXs.reduce((a, b) => a < b ? a : b);
            final jawRight = jawXs.reduce((a, b) => a > b ? a : b);
            final jawWidth = (jawRight - jawLeft) * box.width;
            final faceWidth =
                (faceOvalXs.reduce((a, b) => a > b ? a : b) - faceOvalXs.reduce((a, b) => a < b ? a : b)) * box.width;

            // 顎の幅が顔の幅に近いほど角ばっている（曲率が低い）
            if (faceWidth > 1e-6) {
              curvFromMediaPipe = (1.0 - (jawWidth / faceWidth).clamp(0.0, 1.0)).clamp(0.0, 1.0);
            }
          }
        }
      } catch (e) {
        print('[Face Shape] MediaPipe error: $e');
        curvFromMediaPipe = curv;
      }
    }

    // MediaPipeとML Kitの結果を統合（MediaPipe 70%、ML Kit 30%）
    final combinedCurv = (curvFromMediaPipe * 0.7 + curv * 0.3).clamp(0.0, 1.0);

    // アスペクト比と曲率を組み合わせ
    if (combinedCurv > 0.5 && aspectRatio > 0.75) return '丸';
    if (combinedCurv < 0.25 && aspectRatio < 0.65) return '角';
    return '卵';
  }

  // 鼻の形状推定（ML Kitランドマーク活用）
  static double _estimateNoseShape(Face f) {
    final noseBase = f.landmarks[FaceLandmarkType.noseBase]?.position;
    final leftCheek = f.landmarks[FaceLandmarkType.leftCheek]?.position;
    final rightCheek = f.landmarks[FaceLandmarkType.rightCheek]?.position;

    if (noseBase == null) return 0.5;

    // 鼻の幅を頬の位置から推定
    double width = f.boundingBox.width * 0.15; // デフォルト
    if (leftCheek != null && rightCheek != null) {
      width = (rightCheek.x - leftCheek.x).abs() * 0.3;
    }

    // 鼻の高さをbounding boxから推定
    final height = f.boundingBox.height * 0.15;
    if (height < 1e-6) return 0.5;

    final ratio = width / height;
    return (ratio / 1.5).clamp(0.0, 1.0); // 横長=高スコア
  }

  // 頬の突出度推定
  static double _estimateCheekProminence(Face f) {
    final facePts = f.contours[FaceContourType.face]?.points ?? [];
    if (facePts.length < 10) return 0.5;

    final box = f.boundingBox;
    final centerX = box.left + box.width / 2;

    // 左右の頬領域のポイントを抽出
    final leftCheekPts = facePts
        .where((p) => p.x < centerX && p.y > box.top + box.height * 0.3 && p.y < box.top + box.height * 0.7)
        .toList();
    final rightCheekPts = facePts
        .where((p) => p.x > centerX && p.y > box.top + box.height * 0.3 && p.y < box.top + box.height * 0.7)
        .toList();

    if (leftCheekPts.isEmpty || rightCheekPts.isEmpty) return 0.5;

    // 頬の最も外側のポイントまでの距離
    final leftMax = leftCheekPts.map((p) => centerX - p.x).reduce(math.max);
    final rightMax = rightCheekPts.map((p) => p.x - centerX).reduce(math.max);

    final prominence = ((leftMax + rightMax) / 2.0) / (box.width / 2.0);
    return prominence.clamp(0.0, 1.0);
  }

  // 額の幅推定
  static double _estimateForeheadWidth(Face f) {
    final facePts = f.contours[FaceContourType.face]?.points ?? [];
    if (facePts.isEmpty) return 0.5;

    final box = f.boundingBox;
    final foreheadY = box.top + box.height * 0.15;

    final foreheadPts = facePts.where((p) => (p.y - foreheadY).abs() < box.height * 0.1).toList();
    if (foreheadPts.isEmpty) return 0.5;

    final minX = foreheadPts.map((p) => p.x).reduce(math.min);
    final maxX = foreheadPts.map((p) => p.x).reduce(math.max);
    final foreheadWidth = maxX - minX;

    return (foreheadWidth / box.width).clamp(0.0, 1.0);
  }

  static double _dist(num ax, num ay, num bx, num by) {
    final dx = ax - bx;
    final dy = ay - by;
    return math.sqrt(dx * dx + dy * dy).toDouble();
  }

  static List<String> _candidates(String zone, String polarity) {
    if (zone == '上停' && polarity == '陽') return ['Amatera', 'Yatael', 'Skura'];
    if (zone == '上停' && polarity == '陰') return ['Delphos', 'Amanoira', 'Noirune'];
    if (zone == '中停' && polarity == '陽') return ['Ragias', 'Verdatsu', 'Osiria'];
    // Fatemisはより厳しい条件でのみ追加（中停×陰は補助的）
    if (zone == '中停' && polarity == '陰') return ['Kanonis', 'Sylna', 'Noirune'];
    if (zone == '下停' && polarity == '陽') return ['Yorusi', 'Tenkora', 'Shisaru']; // Yorusiを優先
    return ['Mimika', 'Tenmira', 'Shiran'];
  }

  // 代替候補（候補が少ない場合に追加）
  static List<String> _getAlternativeCandidates(String zone, String polarity) {
    final alt = <String>[];
    // 隣接する三停から候補を追加
    if (zone == '上停') {
      alt.addAll(['Yatael', 'Ragias', 'Tenkora']);
    } else if (zone == '中停') {
      alt.addAll(['Skura', 'Osiria', 'Shisaru']);
    } else {
      alt.addAll(['Verdatsu', 'Kanonis', 'Sylna']);
    }
    return alt;
  }

  static double _shapeBonus(String faceShape, String deityId) {
    switch (faceShape) {
      case '丸':
        if (['Skura', 'Sylna', 'Kanonis', 'Shiran'].contains(deityId)) return 0.05;
        return 0.0;
      case '卵':
        if (['Amatera', 'Verdatsu', 'Tenmira'].contains(deityId)) return 0.05;
        return 0.0;
      case '角':
        // Fatemisはより厳しい条件でのみ補正（角顔 + 眉が直線的）
        if (['Ragias', 'Delphos'].contains(deityId)) return 0.05;
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// スコアが近い候補の中から、三停や陰陽を活用して最適な柱を選択
  /// [candidates] スコアが近い候補のリスト（スコア順にソート済み）
  /// [zone] 三停（上停・中停・下停）
  /// [polarity] 陰陽（陽・陰）
  static String _selectByZoneAndPolarity(
    List<MapEntry<String, double>> candidates,
    String zone,
    String polarity,
  ) {
    // 各柱の陰陽分類
    final yangDeities = ['Amatera', 'Yatael', 'Skura', 'Ragias', 'Osiria', 'Fatemis', 'Tenkora', 'Verdatsu', 'Yorusi'];
    final yinDeities = ['Delphos', 'Amanoira', 'Noirune', 'Mimika', 'Kanonis', 'Sylna', 'Tenmira', 'Shiran', 'Shisaru'];

    // 各柱の三停分類（一般的な特性から推測）
    // 上停が長い（額が広い）→ 知的、創造的
    final upperZoneDeities = ['Mimika', 'Delphos', 'Amanoira', 'Verdatsu', 'Tenmira', 'Shisaru'];
    // 中停が長い（鼻が長い）→ 実行力、指導力
    final middleZoneDeities = ['Ragias', 'Fatemis', 'Yatael', 'Osiria', 'Amatera', 'Yorusi', 'Tenkora'];
    // 下停が長い（顎が長い）→ 忍耐力、継続力
    final lowerZoneDeities = ['Kanonis', 'Sylna', 'Noirune', 'Skura', 'Shiran'];

    // まず、陰陽でフィルタリング
    List<MapEntry<String, double>> filtered = candidates;
    if (polarity == '陽') {
      filtered = candidates.where((e) => yangDeities.contains(e.key)).toList();
      if (filtered.isEmpty) {
        // 陽の柱がない場合は、元の候補を使用
        filtered = candidates;
      }
    } else if (polarity == '陰') {
      filtered = candidates.where((e) => yinDeities.contains(e.key)).toList();
      if (filtered.isEmpty) {
        // 陰の柱がない場合は、元の候補を使用
        filtered = candidates;
      }
    }

    // 三停でさらにフィルタリング
    List<MapEntry<String, double>> zoneFiltered = filtered;
    if (zone == '上停') {
      final zoneMatch = filtered.where((e) => upperZoneDeities.contains(e.key)).toList();
      if (zoneMatch.isNotEmpty) {
        zoneFiltered = zoneMatch;
      }
    } else if (zone == '中停') {
      final zoneMatch = filtered.where((e) => middleZoneDeities.contains(e.key)).toList();
      if (zoneMatch.isNotEmpty) {
        zoneFiltered = zoneMatch;
      }
    } else if (zone == '下停') {
      final zoneMatch = filtered.where((e) => lowerZoneDeities.contains(e.key)).toList();
      if (zoneMatch.isNotEmpty) {
        zoneFiltered = zoneMatch;
      }
    }

    // フィルタリング後の候補から、最高スコアのものを選択
    if (zoneFiltered.isNotEmpty) {
      // スコア順にソート（既にソート済みだが、念のため）
      zoneFiltered.sort((a, b) => b.value.compareTo(a.value));
      return zoneFiltered.first.key;
    }

    // フィルタリング後も候補がない場合は、元の候補から最高スコアを選択
    return candidates.first.key;
  }

  /// 各柱の眉の特徴に対するスコアを計算（すべての柱が計算される）
  /// 【重要】極端な特徴のみでスコアを計算し、普通の値はスキップ（0.0を返す）
  static double _calculateBrowScore(String deityId, double browAngle, double browLength, double browThickness,
      double browShape, double glabellaWidth, double browNeatness) {
    final scores = <double>[];

    // 【重要】複合条件を優先的にチェック（マークダウンファイルの判定基準に基づく）
    final compositeScore =
        _getBrowCompositeScore(deityId, browAngle, browLength, browThickness, browShape, glabellaWidth, browNeatness);
    if (compositeScore > 0.0) {
      scores.add(compositeScore);
    }

    // 極端な特徴のみをスコア計算に使用（普通の値はスキップ）
    // 眉の角度：極端な特徴のみ（右上がり>0.2、右下がり<-0.2、非常に水平-0.1~0.1、水平-0.15~0.15、八字眉<-0.3）
    if (browAngle > 0.2 ||
        browAngle < -0.2 ||
        (browAngle >= -0.1 && browAngle <= 0.1) ||
        (browAngle >= -0.15 && browAngle <= 0.15) ||
        browAngle < -0.3) {
      final angleScore = _getBrowAngleScore(deityId, browAngle);
      if (angleScore > 0.0) scores.add(angleScore);
    }

    // 眉の長さ：極端な特徴のみ（>0.9 または <0.3）
    if (browLength > 0.9 || browLength < 0.3) {
      final lengthScore = _getBrowLengthScore(deityId, browLength);
      if (lengthScore > 0.0) scores.add(lengthScore);
    }

    // 眉の太さ：極端な特徴のみ（>0.95 または <0.2）
    if (browThickness > 0.95 || browThickness < 0.2) {
      final thicknessScore = _getBrowThicknessScore(deityId, browThickness);
      if (thicknessScore > 0.0) scores.add(thicknessScore);
    }

    // 眉の形状：極端な特徴のみ（曲線的>0.6 または 直線的<0.2）
    if (browShape > 0.6 || browShape < 0.2) {
      final shapeScore = _getBrowShapeScore(deityId, browShape);
      if (shapeScore > 0.0) scores.add(shapeScore);
    }

    // 眉間の幅：極端な特徴のみ（>0.9 または <0.2）
    if (glabellaWidth > 0.9 || glabellaWidth < 0.2) {
      final glabellaScore = _getGlabellaWidthScore(deityId, glabellaWidth);
      if (glabellaScore > 0.0) scores.add(glabellaScore);
    }

    // 眉の整い：極端な特徴のみ（>0.95 または <0.15）
    if (browNeatness > 0.95 || browNeatness < 0.15) {
      final neatnessScore = _getBrowNeatnessScore(deityId, browNeatness);
      if (neatnessScore > 0.0) scores.add(neatnessScore);
    }

    // 極端な特徴が1つ以上ある場合のみスコアを計算
    if (scores.isEmpty) return 0.0;
    // 複合条件のスコアがある場合は、それを優先（最大値を返す）
    if (compositeScore > 0.0) {
      return math.max(compositeScore, scores.reduce((a, b) => a + b) / scores.length);
    }
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  /// 複合条件による眉のスコアを計算（マークダウンファイルの判定基準に基づく）
  static double _getBrowCompositeScore(String deityId, double browAngle, double browLength, double browThickness,
      double browShape, double glabellaWidth, double browNeatness) {
    switch (deityId) {
      case 'Amatera':
        // 眉が右上がり + 太い + 直線的
        if (browAngle > 0.2 && browThickness > 0.8 && browShape < 0.2) {
          return TutorialClassifier._gradientScore((browAngle - 0.2) / 0.8) * 0.4 +
              TutorialClassifier._gradientScore((browThickness - 0.8) / 0.2) * 0.3 +
              TutorialClassifier._gradientScore((0.2 - browShape) / 0.2) * 0.3;
        }
        // 眉が非常に長い + 整っている + 眉間が広い
        if (browLength > 0.9 && browNeatness > 0.85 && glabellaWidth > 0.75) {
          return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1) * 0.4 +
              TutorialClassifier._gradientScore((browNeatness - 0.85) / 0.15) * 0.3 +
              TutorialClassifier._gradientScore((glabellaWidth - 0.75) / 0.25) * 0.3;
        }
        // 眉が非常に濃い + 整っている + 眉間が広い
        if (browThickness > 0.95 && browNeatness > 0.85 && glabellaWidth > 0.8) {
          return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05) * 0.4 +
              TutorialClassifier._gradientScore((browNeatness - 0.85) / 0.15) * 0.3 +
              TutorialClassifier._gradientScore((glabellaWidth - 0.8) / 0.2) * 0.3;
        }
        // 眉が非常に曲線的 + 整っている + 眉間が広い
        if (browShape > 0.9 && browNeatness > 0.85 && glabellaWidth > 0.75) {
          return TutorialClassifier._gradientScore((browShape - 0.9) / 0.1) * 0.4 +
              TutorialClassifier._gradientScore((browNeatness - 0.85) / 0.15) * 0.3 +
              TutorialClassifier._gradientScore((glabellaWidth - 0.75) / 0.25) * 0.3;
        }
        // 眉間が非常に広い + 整っている + 長い
        if (glabellaWidth > 0.9 && browNeatness > 0.85 && browLength > 0.8) {
          return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1) * 0.4 +
              TutorialClassifier._gradientScore((browNeatness - 0.85) / 0.15) * 0.3 +
              TutorialClassifier._gradientScore((browLength - 0.8) / 0.2) * 0.3;
        }
        // 眉が非常に整っている + 眉間が広い + 長い
        if (browNeatness > 0.95 && glabellaWidth > 0.8 && browLength > 0.8) {
          return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05) * 0.4 +
              TutorialClassifier._gradientScore((glabellaWidth - 0.8) / 0.2) * 0.3 +
              TutorialClassifier._gradientScore((browLength - 0.8) / 0.2) * 0.3;
        }
        // 眉が右上がり + 太い
        if (browAngle > 0.5 && browThickness > 0.85 && browShape < 0.2) {
          return TutorialClassifier._gradientScore((browAngle - 0.5) / 0.5) * 0.5 +
              TutorialClassifier._gradientScore((browThickness - 0.85) / 0.15) * 0.5;
        }
        return 0.0;

      case 'Yatael':
        // 眉が非常に整っている + 眉間が広い + 長い
        if (browNeatness > 0.95 && glabellaWidth > 0.8 && browLength > 0.8) {
          return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05) * 0.4 +
              TutorialClassifier._gradientScore((glabellaWidth - 0.8) / 0.2) * 0.3 +
              TutorialClassifier._gradientScore((browLength - 0.8) / 0.2) * 0.3;
        }
        // 眉が非常に整っている + 長い
        if (browNeatness > 0.95 && browLength > 0.8) {
          return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05) * 0.5 +
              TutorialClassifier._gradientScore((browLength - 0.8) / 0.2) * 0.5;
        }
        return 0.0;

      case 'Kanonis':
        // 眉が非常に長い + 整っている + 眉間が広い
        if (browLength > 0.9 && browNeatness > 0.85 && glabellaWidth > 0.75) {
          return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1) * 0.4 +
              TutorialClassifier._gradientScore((browNeatness - 0.85) / 0.15) * 0.3 +
              TutorialClassifier._gradientScore((glabellaWidth - 0.75) / 0.25) * 0.3;
        }
        // 眉が非常に整っている + 眉間が広い + 長い
        if (browNeatness > 0.95 && glabellaWidth > 0.8 && browLength > 0.8) {
          return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05) * 0.4 +
              TutorialClassifier._gradientScore((glabellaWidth - 0.8) / 0.2) * 0.3 +
              TutorialClassifier._gradientScore((browLength - 0.8) / 0.2) * 0.3;
        }
        // 眉が非常に整っている + 長い
        if (browNeatness > 0.95 && browLength > 0.8) {
          return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05) * 0.5 +
              TutorialClassifier._gradientScore((browLength - 0.8) / 0.2) * 0.5;
        }
        // 眉が非常に薄い + 水平 + 整っている
        if (browThickness < 0.2 && browAngle >= -0.15 && browAngle <= 0.15 && browNeatness > 0.8) {
          return TutorialClassifier._gradientScore((0.2 - browThickness) / 0.2) * 0.4 +
              TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.15)) * 0.3 +
              TutorialClassifier._gradientScore((browNeatness - 0.8) / 0.2) * 0.3;
        }
        // 眉が非常に曲線的 + 整っている + 眉間が広い
        if (browShape > 0.9 && browNeatness > 0.85 && glabellaWidth > 0.75) {
          return TutorialClassifier._gradientScore((browShape - 0.9) / 0.1) * 0.4 +
              TutorialClassifier._gradientScore((browNeatness - 0.85) / 0.15) * 0.3 +
              TutorialClassifier._gradientScore((glabellaWidth - 0.75) / 0.25) * 0.3;
        }
        // 眉間が非常に広い + 整っている + 長い
        if (glabellaWidth > 0.9 && browNeatness > 0.85 && browLength > 0.8) {
          return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1) * 0.4 +
              TutorialClassifier._gradientScore((browNeatness - 0.85) / 0.15) * 0.3 +
              TutorialClassifier._gradientScore((browLength - 0.8) / 0.2) * 0.3;
        }
        return 0.0;

      case 'Sylna':
        // 眉が非常に長い + 整っている + 眉間が広い
        if (browLength > 0.9 && browNeatness > 0.85 && glabellaWidth > 0.75) {
          return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1) * 0.4 +
              TutorialClassifier._gradientScore((browNeatness - 0.85) / 0.15) * 0.3 +
              TutorialClassifier._gradientScore((glabellaWidth - 0.75) / 0.25) * 0.3;
        }
        // 眉が非常に整っている + 長い
        if (browNeatness > 0.95 && browLength > 0.8) {
          return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05) * 0.5 +
              TutorialClassifier._gradientScore((browLength - 0.8) / 0.2) * 0.5;
        }
        // 眉が非常に曲線的 + 整っている
        if (browShape > 0.9 && browNeatness > 0.85) {
          return TutorialClassifier._gradientScore((browShape - 0.9) / 0.1) * 0.5 +
              TutorialClassifier._gradientScore((browNeatness - 0.85) / 0.15) * 0.5;
        }
        return 0.0;

      case 'Ragias':
        // 眉が非常に短い + 右上がり + 直線的
        if (browLength < 0.2 && browAngle > 0.3 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((0.2 - browLength) / 0.2) * 0.4 +
              TutorialClassifier._gradientScore((browAngle - 0.3) / 0.7) * 0.3 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.3;
        }
        // 眉が非常に太い + 右上がり + 直線的
        if (browThickness > 0.9 && browAngle > 0.3 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((browThickness - 0.9) / 0.1) * 0.4 +
              TutorialClassifier._gradientScore((browAngle - 0.3) / 0.7) * 0.3 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.3;
        }
        // 眉が非常に直線的 + 右上がり + 太い
        if (browShape < 0.15 && browAngle > 0.3 && browThickness > 0.7) {
          return TutorialClassifier._gradientScore((0.15 - browShape) / 0.15) * 0.4 +
              TutorialClassifier._gradientScore((browAngle - 0.3) / 0.7) * 0.3 +
              TutorialClassifier._gradientScore((browThickness - 0.7) / 0.3) * 0.3;
        }
        // 眉が非常に乱れている + 右上がり + 太い
        if (browNeatness < 0.15 && browAngle > 0.3 && browThickness > 0.7) {
          return TutorialClassifier._gradientScore((0.15 - browNeatness) / 0.15) * 0.4 +
              TutorialClassifier._gradientScore((browAngle - 0.3) / 0.7) * 0.3 +
              TutorialClassifier._gradientScore((browThickness - 0.7) / 0.3) * 0.3;
        }
        return 0.0;

      case 'Fatemis':
        // 眉が右上がり + 非常に太い + 直線的
        if (browAngle > 0.2 && browThickness > 0.8 && browShape < 0.2) {
          return TutorialClassifier._gradientScore((browAngle - 0.2) / 0.8) * 0.4 +
              TutorialClassifier._gradientScore((browThickness - 0.8) / 0.2) * 0.3 +
              TutorialClassifier._gradientScore((0.2 - browShape) / 0.2) * 0.3;
        }
        // 眉が非常に短い + 右上がり + 直線的
        if (browLength < 0.2 && browAngle > 0.3 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((0.2 - browLength) / 0.2) * 0.4 +
              TutorialClassifier._gradientScore((browAngle - 0.3) / 0.7) * 0.3 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.3;
        }
        // 眉が非常に直線的 + 右上がり
        if (browShape < 0.15 && browAngle > 0.5 && browThickness > 0.7) {
          return TutorialClassifier._gradientScore((0.15 - browShape) / 0.15) * 0.4 +
              TutorialClassifier._gradientScore((browAngle - 0.5) / 0.5) * 0.3 +
              TutorialClassifier._gradientScore((browThickness - 0.7) / 0.3) * 0.3;
        }
        // 眉が非常に乱れている + 右上がり + 太い
        if (browNeatness < 0.15 && browAngle > 0.3 && browThickness > 0.7) {
          return TutorialClassifier._gradientScore((0.15 - browNeatness) / 0.15) * 0.4 +
              TutorialClassifier._gradientScore((browAngle - 0.3) / 0.7) * 0.3 +
              TutorialClassifier._gradientScore((browThickness - 0.7) / 0.3) * 0.3;
        }
        return 0.0;

      case 'Delphos':
        // 眉が非常に濃い + 整っている + 眉間が広い
        if (browThickness > 0.95 && browNeatness > 0.85 && glabellaWidth > 0.8) {
          return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05) * 0.4 +
              TutorialClassifier._gradientScore((browNeatness - 0.85) / 0.15) * 0.3 +
              TutorialClassifier._gradientScore((glabellaWidth - 0.8) / 0.2) * 0.3;
        }
        // 眉が濃い + 右上がり + 直線的
        if (browThickness > 0.9 && browAngle > 0.3 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((browThickness - 0.9) / 0.1) * 0.4 +
              TutorialClassifier._gradientScore((browAngle - 0.3) / 0.7) * 0.3 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.3;
        }
        return 0.0;

      default:
        return 0.0;
    }
  }

  /// 眉と目の複合条件によるスコアを計算（マークダウンファイルの判定基準に基づく）
  /// 眉と目の組み合わせ条件を統合的に評価
  static double _calculateEyeBrowCompositeScore(
    String deityId,
    double browAngle,
    double browLength,
    double browThickness,
    double browShape,
    double glabellaWidth,
    double browNeatness,
    double eyeBalance,
    double eyeSize,
    double eyeShape,
  ) {
    switch (deityId) {
      case 'Amatera':
        // 眉が右上がり + 目が大きい + 目のバランスが良い + 眉が直線的
        if (browAngle > 0.4 && eyeSize > 0.6 && eyeBalance > 0.65 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.3 +
              TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.3 +
              TutorialClassifier._gradientScore((eyeBalance - 0.65) / 0.35) * 0.2 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.2;
        }
        // 眉が右上がり + 目のバランスが良い
        if (browAngle > 0.4 && eyeBalance > 0.75) {
          return TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.5 +
              TutorialClassifier._gradientScore((eyeBalance - 0.75) / 0.25) * 0.5;
        }
        // 眉が右上がり + 目が大きい + 切れ長
        if (browAngle > 0.5 && eyeSize > 0.6 && eyeShape > 0.85) {
          return TutorialClassifier._gradientScore((browAngle - 0.5) / 0.5) * 0.4 +
              TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.3 +
              TutorialClassifier._gradientScore((eyeShape - 0.85) / 0.15) * 0.3;
        }
        // 眉が長い（眉と目の組み合わせ条件）
        if (browLength > 0.7) {
          return TutorialClassifier._gradientScore((browLength - 0.7) / 0.3);
        }
        // 眉が曲線的（眉と目の組み合わせ条件）
        if (browShape > 0.7) {
          return TutorialClassifier._gradientScore((browShape - 0.7) / 0.3);
        }
        // 眉間が広い（眉と目の組み合わせ条件）
        if (glabellaWidth > 0.7) {
          return TutorialClassifier._gradientScore((glabellaWidth - 0.7) / 0.3);
        }
        // 眉が整っている（眉と目の組み合わせ条件）
        if (browNeatness > 0.7) {
          return TutorialClassifier._gradientScore((browNeatness - 0.7) / 0.3);
        }
        return 0.0;

      case 'Yatael':
        // 眉が水平に近い（眉と目の組み合わせ条件）
        if (browAngle >= -0.2 && browAngle <= 0.2) {
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2));
        }
        // 眉が長い（眉と目の組み合わせ条件）
        if (browLength > 0.7) {
          return TutorialClassifier._gradientScore((browLength - 0.7) / 0.3);
        }
        // 眉が曲線的（眉と目の組み合わせ条件）
        if (browShape > 0.7) {
          return TutorialClassifier._gradientScore((browShape - 0.7) / 0.3);
        }
        // 眉間が広い（眉と目の組み合わせ条件）
        if (glabellaWidth > 0.7) {
          return TutorialClassifier._gradientScore((glabellaWidth - 0.7) / 0.3);
        }
        // 眉が整っている（眉と目の組み合わせ条件）
        if (browNeatness > 0.7) {
          return TutorialClassifier._gradientScore((browNeatness - 0.7) / 0.3);
        }
        // 目のバランスが良い（眉と目の組み合わせ条件）
        if (eyeBalance > 0.65) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.65) / 0.35);
        }
        // 目が大きい（眉と目の組み合わせ条件）
        if (eyeSize > 0.6) {
          return TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4);
        }
        return 0.0;

      case 'Delphos':
        // 眉が右下がり + 目が小さい + 目のバランスが悪い
        if (browAngle < -0.2 && eyeSize < 0.4 && eyeBalance < 0.35) {
          return TutorialClassifier._gradientScore((browAngle.abs() - 0.2) / 0.8) * 0.4 +
              TutorialClassifier._gradientScore((0.4 - eyeSize) / 0.4) * 0.3 +
              TutorialClassifier._gradientScore((0.35 - eyeBalance) / 0.35) * 0.3;
        }
        // 目のバランスが良い + 眉が右上がり
        if (eyeBalance > 0.75 && browAngle > 0.4) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.75) / 0.25) * 0.5 +
              TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.5;
        }
        // 目が切れ長 + 眉が右上がり
        if (eyeShape > 0.85 && browAngle > 0.4) {
          return TutorialClassifier._gradientScore((eyeShape - 0.85) / 0.15) * 0.5 +
              TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.5;
        }
        // 眉が濃い（眉と目の組み合わせ条件）
        if (browThickness > 0.7) {
          return TutorialClassifier._gradientScore((browThickness - 0.7) / 0.3);
        }
        // 眉が直線的（眉と目の組み合わせ条件）
        if (browShape < 0.3) {
          return TutorialClassifier._gradientScore((0.3 - browShape) / 0.3);
        }
        // 眉間が狭い（眉と目の組み合わせ条件）
        if (glabellaWidth < 0.3) {
          return TutorialClassifier._gradientScore((0.3 - glabellaWidth) / 0.3);
        }
        return 0.0;

      case 'Amanoira':
        // 眉が右下がり + 目が小さい + 目のバランスが悪い
        if (browAngle < -0.2 && eyeSize < 0.4 && eyeBalance < 0.35) {
          return TutorialClassifier._gradientScore((browAngle.abs() - 0.2) / 0.8) * 0.4 +
              TutorialClassifier._gradientScore((0.4 - eyeSize) / 0.4) * 0.3 +
              TutorialClassifier._gradientScore((0.35 - eyeBalance) / 0.35) * 0.3;
        }
        // 眉が右下がり + 目のバランスが悪い + 目が小さい
        if (browAngle < -0.3 && eyeSize < 0.4 && eyeBalance < 0.35) {
          return TutorialClassifier._gradientScore((browAngle.abs() - 0.3) / 0.7) * 0.4 +
              TutorialClassifier._gradientScore((0.4 - eyeSize) / 0.4) * 0.3 +
              TutorialClassifier._gradientScore((0.35 - eyeBalance) / 0.35) * 0.3;
        }
        // 目が切れ長 + 眉が右上がり
        if (eyeShape > 0.85 && browAngle > 0.4) {
          return TutorialClassifier._gradientScore((eyeShape - 0.85) / 0.15) * 0.5 +
              TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.5;
        }
        // 目が切れ長 + 眉が水平
        if (eyeShape > 0.8 && browAngle >= -0.2 && browAngle <= 0.2) {
          return TutorialClassifier._gradientScore((eyeShape - 0.8) / 0.2) * 0.5 +
              TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2)) * 0.5;
        }
        // 眉間が狭い（眉と目の組み合わせ条件）
        if (glabellaWidth < 0.3) {
          return TutorialClassifier._gradientScore((0.3 - glabellaWidth) / 0.3);
        }
        return 0.0;

      case 'Ragias':
        // 眉が非常に右上がり + 目が大きい + 目のバランスが良い + 眉が直線的
        if (browAngle > 0.4 && eyeSize > 0.6 && eyeBalance > 0.65 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.3 +
              TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.3 +
              TutorialClassifier._gradientScore((eyeBalance - 0.65) / 0.35) * 0.2 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.2;
        }
        // 目のバランスが良い + 眉が右上がり
        if (eyeBalance > 0.65 && browAngle > 0.4) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.65) / 0.35) * 0.5 +
              TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.5;
        }
        // 目が大きい + 眉が右上がり
        if (eyeSize > 0.6 && browAngle > 0.4) {
          return TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.5 +
              TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.5;
        }
        // 目が非常に切れ長 + 眉が右上がり + 眉が直線的
        if (eyeShape > 0.85 && browAngle > 0.4 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((eyeShape - 0.85) / 0.15) * 0.4 +
              TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.3 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.3;
        }
        // 目が大きい + 非常に切れ長 + 眉が非常に右上がり + 眉が直線的
        if (eyeSize > 0.6 && eyeShape > 0.85 && browAngle > 0.5 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.25 +
              TutorialClassifier._gradientScore((eyeShape - 0.85) / 0.15) * 0.25 +
              TutorialClassifier._gradientScore((browAngle - 0.5) / 0.5) * 0.25 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.25;
        }
        // 眉が短い + 直線的（眉と目の組み合わせ条件）
        if (browLength < 0.2 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((0.2 - browLength) / 0.2) * 0.5 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.5;
        }
        // 眉が太い（眉と目の組み合わせ条件）
        if (browThickness > 0.7) {
          return TutorialClassifier._gradientScore((browThickness - 0.7) / 0.3);
        }
        return 0.0;

      case 'Fatemis':
        // 眉が右上がり + 目が大きい + 目のバランスが良い + 眉が直線的
        if (browAngle > 0.4 && eyeSize > 0.6 && eyeBalance > 0.65 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.3 +
              TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.3 +
              TutorialClassifier._gradientScore((eyeBalance - 0.65) / 0.35) * 0.2 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.2;
        }
        // 眉が右上がり + 目のバランスが良い + 眉が直線的
        if (browAngle > 0.4 && eyeBalance > 0.75 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.4 +
              TutorialClassifier._gradientScore((eyeBalance - 0.75) / 0.25) * 0.3 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.3;
        }
        // 眉が右上がり + 目が切れ長
        if (browAngle > 0.4 && eyeShape > 0.85) {
          return TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.5 +
              TutorialClassifier._gradientScore((eyeShape - 0.85) / 0.15) * 0.5;
        }
        // 眉が右上がり + 目が大きい + 切れ長
        if (browAngle > 0.5 && eyeSize > 0.6 && eyeShape > 0.85) {
          return TutorialClassifier._gradientScore((browAngle - 0.5) / 0.5) * 0.4 +
              TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.3 +
              TutorialClassifier._gradientScore((eyeShape - 0.85) / 0.15) * 0.3;
        }
        // 目が切れ長 + 眉が水平
        if (eyeShape > 0.8 && browAngle >= -0.2 && browAngle <= 0.2) {
          return TutorialClassifier._gradientScore((eyeShape - 0.8) / 0.2) * 0.5 +
              TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2)) * 0.5;
        }
        // 眉が短い + 直線的（眉と目の組み合わせ条件）
        if (browLength < 0.2 && browShape < 0.3) {
          return TutorialClassifier._gradientScore((0.2 - browLength) / 0.2) * 0.5 +
              TutorialClassifier._gradientScore((0.3 - browShape) / 0.3) * 0.5;
        }
        // 眉が濃い（眉と目の組み合わせ条件）
        if (browThickness > 0.7) {
          return TutorialClassifier._gradientScore((browThickness - 0.7) / 0.3);
        }
        // 眉が直線的（眉と目の組み合わせ条件）
        if (browShape < 0.3) {
          return TutorialClassifier._gradientScore((0.3 - browShape) / 0.3);
        }
        // 眉が乱れている（眉と目の組み合わせ条件）
        if (browNeatness < 0.2) {
          return TutorialClassifier._gradientScore((0.2 - browNeatness) / 0.2);
        }
        return 0.0;

      case 'Verdatsu':
        // 目が切れ長 + 眉が右上がり
        if (eyeShape > 0.85 && browAngle > 0.4) {
          return TutorialClassifier._gradientScore((eyeShape - 0.85) / 0.15) * 0.5 +
              TutorialClassifier._gradientScore((browAngle - 0.4) / 0.6) * 0.5;
        }
        // 目が切れ長 + 眉が水平
        if (eyeShape > 0.8 && browAngle >= -0.2 && browAngle <= 0.2) {
          return TutorialClassifier._gradientScore((eyeShape - 0.8) / 0.2) * 0.5 +
              TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2)) * 0.5;
        }
        // 眉が濃い（眉と目の組み合わせ条件）
        if (browThickness > 0.7) {
          return TutorialClassifier._gradientScore((browThickness - 0.7) / 0.3);
        }
        // 眉が直線的（眉と目の組み合わせ条件）
        if (browShape < 0.3) {
          return TutorialClassifier._gradientScore((0.3 - browShape) / 0.3);
        }
        return 0.0;

      case 'Kanonis':
      case 'Sylna':
        // 眉が水平に近い（眉と目の組み合わせ条件）
        if (browAngle >= -0.2 && browAngle <= 0.2) {
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2));
        }
        // 眉が長い（眉と目の組み合わせ条件）
        if (browLength > 0.7) {
          return TutorialClassifier._gradientScore((browLength - 0.7) / 0.3);
        }
        // 眉が薄い（眉と目の組み合わせ条件）
        if (browThickness < 0.3) {
          return TutorialClassifier._gradientScore((0.3 - browThickness) / 0.3);
        }
        // 眉が曲線的（眉と目の組み合わせ条件）
        if (browShape > 0.7) {
          return TutorialClassifier._gradientScore((browShape - 0.7) / 0.3);
        }
        // 目のバランスが良い（眉と目の組み合わせ条件）
        if (eyeBalance > 0.65) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.65) / 0.35);
        }
        // 目のバランスが良い + 眉が水平
        if (eyeBalance > 0.65 && browAngle >= -0.2 && browAngle <= 0.2) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.65) / 0.35) * 0.5 +
              TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2)) * 0.5;
        }
        // 目が大きい（眉と目の組み合わせ条件）
        if (eyeSize > 0.6) {
          return TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4);
        }
        return 0.0;

      case 'Tenmira':
      case 'Shiran':
        // 眉が水平に近い（眉と目の組み合わせ条件）
        if (browAngle >= -0.2 && browAngle <= 0.2) {
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2));
        }
        // 目のバランスが良い（眉と目の組み合わせ条件）
        if (eyeBalance > 0.65) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.65) / 0.35);
        }
        // 目のバランスが良い + 眉が水平
        if (eyeBalance > 0.65 && browAngle >= -0.2 && browAngle <= 0.2) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.65) / 0.35) * 0.5 +
              TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2)) * 0.5;
        }
        // 目が大きい + 眉が水平
        if (eyeSize > 0.6 && browAngle >= -0.2 && browAngle <= 0.2) {
          return TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.5 +
              TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2)) * 0.5;
        }
        // 目が大きい（眉と目の組み合わせ条件）
        if (eyeSize > 0.6) {
          return TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4);
        }
        return 0.0;

      default:
        return 0.0;
    }
  }

  /// 目の複合条件によるスコアを計算（マークダウンファイルの判定基準に基づく）
  static double _calculateEyeCompositeScore(String deityId, double eyeBalance, double eyeSize, double eyeShape) {
    switch (deityId) {
      case 'Amatera':
        // 目のバランスが非常に良い + 目が大きい
        if (eyeBalance > 0.85 && eyeSize > 0.7) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15) * 0.5 +
              TutorialClassifier._gradientScore((eyeSize - 0.7) / 0.3) * 0.5;
        }
        // 目のバランスが良い + 目が大きい
        if (eyeBalance > 0.75 && eyeSize > 0.6) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.75) / 0.25) * 0.5 +
              TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.5;
        }
        // 目が非常に大きい + バランスが良い
        if (eyeSize > 0.8 && eyeBalance > 0.75) {
          return TutorialClassifier._gradientScore((eyeSize - 0.8) / 0.2) * 0.5 +
              TutorialClassifier._gradientScore((eyeBalance - 0.75) / 0.25) * 0.5;
        }
        // 目が大きい + バランスが良い
        if (eyeSize > 0.6 && eyeBalance > 0.65) {
          return TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.5 +
              TutorialClassifier._gradientScore((eyeBalance - 0.65) / 0.35) * 0.5;
        }
        // 目が大きい + 切れ長
        if (eyeSize > 0.6 && eyeShape > 0.6) {
          return TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.5 +
              TutorialClassifier._gradientScore((eyeShape - 0.6) / 0.4) * 0.5;
        }
        return 0.0;

      case 'Yatael':
        // 目のバランスが非常に良い + 目が非常に大きい
        if (eyeBalance > 0.85 && eyeSize > 0.8) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15) * 0.5 +
              TutorialClassifier._gradientScore((eyeSize - 0.8) / 0.2) * 0.5;
        }
        return 0.0;

      case 'Skura':
        // 目のバランスが非常に良い + 目が大きい
        if (eyeBalance > 0.8 && eyeSize > 0.75) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.8) / 0.2) * 0.5 +
              TutorialClassifier._gradientScore((eyeSize - 0.75) / 0.25) * 0.5;
        }
        // 目が非常に大きい + バランスが非常に良い
        if (eyeSize > 0.85 && eyeBalance > 0.8) {
          return TutorialClassifier._gradientScore((eyeSize - 0.85) / 0.15) * 0.5 +
              TutorialClassifier._gradientScore((eyeBalance - 0.8) / 0.2) * 0.5;
        }
        return 0.0;

      case 'Osiria':
        // 目のバランスが非常に良い + 目が大きい
        if (eyeBalance > 0.85 && eyeSize > 0.75) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15) * 0.5 +
              TutorialClassifier._gradientScore((eyeSize - 0.75) / 0.25) * 0.5;
        }
        // 目のバランスが良い + 目が大きい
        if (eyeBalance > 0.75 && eyeSize > 0.6) {
          return TutorialClassifier._gradientScore((eyeBalance - 0.75) / 0.25) * 0.5 +
              TutorialClassifier._gradientScore((eyeSize - 0.6) / 0.4) * 0.5;
        }
        // 目が非常に大きい + バランスが非常に良い
        if (eyeSize > 0.85 && eyeBalance > 0.8) {
          return TutorialClassifier._gradientScore((eyeSize - 0.85) / 0.15) * 0.5 +
              TutorialClassifier._gradientScore((eyeBalance - 0.8) / 0.2) * 0.5;
        }
        return 0.0;

      default:
        return 0.0;
    }
  }

  /// 各柱の眉の角度に対するスコアを計算
  /// 【重要】極端な特徴のみでスコアを計算し、普通の値はスキップ（0.0を返す）
  static double _getBrowAngleScore(String deityId, double browAngle) {
    switch (deityId) {
      case 'Amatera':
        if (browAngle > 0.2) return TutorialClassifier._gradientScore((browAngle - 0.2) / 0.8);
        return 0.0;
      case 'Yatael':
        if (browAngle > 0.2) return TutorialClassifier._gradientScore((browAngle - 0.2) / 0.8);
        if (browAngle >= -0.1 && browAngle <= 0.1)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.1));
        if (browAngle < -0.3) return TutorialClassifier._gradientScore((browAngle.abs() - 0.3) / 0.7);
        return 0.0;
      case 'Skura':
        if (browAngle >= -0.2 && browAngle <= 0.2)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2));
        if (browAngle < -0.3 && browAngle > -0.5)
          return TutorialClassifier._gradientScore((browAngle.abs() - 0.3) / 0.2);
        return 0.0;
      case 'Delphos':
        if (browAngle > 0.2) return TutorialClassifier._gradientScore((browAngle - 0.2) / 0.8);
        return 0.0;
      case 'Amanoira':
        if (browAngle < -0.2) return TutorialClassifier._gradientScore((browAngle.abs() - 0.2) / 0.8);
        return 0.0;
      case 'Noirune':
        if (browAngle < -0.2) return TutorialClassifier._gradientScore((browAngle.abs() - 0.2) / 0.8);
        return 0.0;
      case 'Ragias':
        if (browAngle > 0.2) return TutorialClassifier._gradientScore((browAngle - 0.2) / 0.8);
        return 0.0;
      case 'Verdatsu':
        if (browAngle > 0.2) return TutorialClassifier._gradientScore((browAngle - 0.2) / 0.8);
        return 0.0;
      case 'Osiria':
        if (browAngle >= -0.2 && browAngle <= 0.2)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2));
        return 0.0;
      case 'Fatemis':
        if (browAngle > 0.2) return TutorialClassifier._gradientScore((browAngle - 0.2) / 0.8);
        return 0.0;
      case 'Kanonis':
        if (browAngle < -0.2) return TutorialClassifier._gradientScore((browAngle.abs() - 0.2) / 0.8);
        if (browAngle >= -0.15 && browAngle <= 0.15)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.15));
        if (browAngle < -0.3) return TutorialClassifier._gradientScore((browAngle.abs() - 0.3) / 0.7);
        return 0.0;
      case 'Sylna':
        if (browAngle < -0.2) return TutorialClassifier._gradientScore((browAngle.abs() - 0.2) / 0.8);
        if (browAngle >= -0.15 && browAngle <= 0.15)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.15));
        if (browAngle < -0.3) return TutorialClassifier._gradientScore((browAngle.abs() - 0.3) / 0.7);
        return 0.0;
      case 'Yorusi':
        if (browAngle >= -0.2 && browAngle <= 0.2)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2));
        return 0.0;
      case 'Tenkora':
        if (browAngle > 0.2) return TutorialClassifier._gradientScore((browAngle - 0.2) / 0.8);
        return 0.0;
      case 'Shisaru':
        if (browAngle >= -0.2 && browAngle <= 0.2)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2));
        return 0.0;
      case 'Mimika':
        if (browAngle < -0.2) return TutorialClassifier._gradientScore((browAngle.abs() - 0.2) / 0.8);
        return 0.0;
      case 'Tenmira':
        if (browAngle >= -0.15 && browAngle <= 0.15)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.15));
        if (browAngle >= -0.2 && browAngle <= 0.2)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2));
        return 0.0;
      case 'Shiran':
        if (browAngle >= -0.15 && browAngle <= 0.15)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.15));
        if (browAngle >= -0.2 && browAngle <= 0.2)
          return TutorialClassifier._gradientScore(1.0 - (browAngle.abs() / 0.2));
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// 各柱の眉の長さに対するスコアを計算
  static double _getBrowLengthScore(String deityId, double browLength) {
    switch (deityId) {
      case 'Amatera':
        if (browLength > 0.9) return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1);
        return 0.0;
      case 'Yatael':
        if (browLength > 0.9) return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1);
        return 0.0;
      case 'Skura':
        if (browLength > 0.9) return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Delphos':
        if (browLength < 0.3) return TutorialClassifier._gradientScore((0.3 - browLength) / 0.3);
        return 0.0;
      case 'Amanoira':
        if (browLength < 0.3) return TutorialClassifier._gradientScore((0.3 - browLength) / 0.3);
        return 0.0;
      case 'Noirune':
        if (browLength < 0.3) return TutorialClassifier._gradientScore((0.3 - browLength) / 0.3);
        return 0.0;
      case 'Ragias':
        if (browLength < 0.2) return TutorialClassifier._gradientScore((0.2 - browLength) / 0.2);
        if (browLength < 0.3) return TutorialClassifier._gradientScore((0.3 - browLength) / 0.3) * 0.7;
        return 0.0;
      case 'Verdatsu':
        if (browLength < 0.3) return TutorialClassifier._gradientScore((0.3 - browLength) / 0.3);
        return 0.0;
      case 'Osiria':
        if (browLength > 0.9) return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Fatemis':
        if (browLength < 0.2) return TutorialClassifier._gradientScore((0.2 - browLength) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Kanonis':
        if (browLength > 0.9) return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Sylna':
        if (browLength > 0.9) return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Yorusi':
        if (browLength > 0.9) return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Tenkora':
        if (browLength < 0.2) return TutorialClassifier._gradientScore((0.2 - browLength) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Shisaru':
        if (browLength > 0.9) return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Mimika':
        if (browLength < 0.3) return TutorialClassifier._gradientScore((0.3 - browLength) / 0.3);
        return 0.0;
      case 'Tenmira':
        if (browLength > 0.9) return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Shiran':
        if (browLength > 0.9) return TutorialClassifier._gradientScore((browLength - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// 各柱の眉の太さに対するスコアを計算
  static double _getBrowThicknessScore(String deityId, double browThickness) {
    switch (deityId) {
      case 'Amatera':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        return 0.0;
      case 'Yatael':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        return 0.0;
      case 'Skura':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        return 0.0;
      case 'Delphos':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        return 0.0;
      case 'Amanoira':
        if (browThickness < 0.3) return TutorialClassifier._gradientScore((0.3 - browThickness) / 0.3);
        return 0.0;
      case 'Noirune':
        if (browThickness < 0.2) return TutorialClassifier._gradientScore((0.2 - browThickness) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Ragias':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Verdatsu':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Osiria':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Fatemis':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Kanonis':
        if (browThickness < 0.2) return TutorialClassifier._gradientScore((0.2 - browThickness) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Sylna':
        if (browThickness < 0.2) return TutorialClassifier._gradientScore((0.2 - browThickness) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Yorusi':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Tenkora':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Shisaru':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Mimika':
        if (browThickness < 0.2) return TutorialClassifier._gradientScore((0.2 - browThickness) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Tenmira':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Shiran':
        if (browThickness > 0.95) return TutorialClassifier._gradientScore((browThickness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// 各柱の眉の形状に対するスコアを計算
  static double _getBrowShapeScore(String deityId, double browShape) {
    switch (deityId) {
      case 'Amatera':
        if (browShape > 0.9) return TutorialClassifier._gradientScore((browShape - 0.9) / 0.1);
        if (browShape < 0.2) return TutorialClassifier._gradientScore((0.2 - browShape) / 0.2);
        return 0.0;
      case 'Yatael':
        if (browShape > 0.6) return TutorialClassifier._gradientScore((browShape - 0.6) / 0.4);
        return 0.0;
      case 'Skura':
        if (browShape > 0.7) return TutorialClassifier._gradientScore((browShape - 0.7) / 0.3);
        return 0.0;
      case 'Delphos':
        if (browShape < 0.2) return TutorialClassifier._gradientScore((0.2 - browShape) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Amanoira':
        if (browShape < 0.3) return TutorialClassifier._gradientScore((0.3 - browShape) / 0.3);
        return 0.0;
      case 'Noirune':
        if (browShape > 0.6) return TutorialClassifier._gradientScore((browShape - 0.6) / 0.4);
        // 極端な特徴のみで判定（0.6~0.7は普通の値なのでスキップ）
        return 0.0;
      case 'Ragias':
        if (browShape < 0.2) return TutorialClassifier._gradientScore((0.2 - browShape) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Verdatsu':
        if (browShape < 0.2) return TutorialClassifier._gradientScore((0.2 - browShape) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Osiria':
        if (browShape > 0.6) return TutorialClassifier._gradientScore((browShape - 0.6) / 0.4);
        // 極端な特徴のみで判定（0.6~0.7は普通の値なのでスキップ）
        return 0.0;
      case 'Fatemis':
        if (browShape < 0.2) return TutorialClassifier._gradientScore((0.2 - browShape) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Kanonis':
        if (browShape > 0.6) return TutorialClassifier._gradientScore((browShape - 0.6) / 0.4);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Sylna':
        if (browShape > 0.6) return TutorialClassifier._gradientScore((browShape - 0.6) / 0.4);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Yorusi':
        if (browShape > 0.6) return TutorialClassifier._gradientScore((browShape - 0.6) / 0.4);
        // 極端な特徴のみで判定（0.6~0.7は普通の値なのでスキップ）
        return 0.0;
      case 'Tenkora':
        if (browShape < 0.3) return TutorialClassifier._gradientScore((0.3 - browShape) / 0.3);
        return 0.0;
      case 'Shisaru':
        if (browShape > 0.6) return TutorialClassifier._gradientScore((browShape - 0.6) / 0.4);
        // 極端な特徴のみで判定（0.6~0.7は普通の値なのでスキップ）
        return 0.0;
      case 'Mimika':
        if (browShape > 0.6) return TutorialClassifier._gradientScore((browShape - 0.6) / 0.4);
        // 極端な特徴のみで判定（0.6~0.7は普通の値なのでスキップ）
        return 0.0;
      case 'Tenmira':
        if (browShape > 0.6) return TutorialClassifier._gradientScore((browShape - 0.6) / 0.4);
        // 極端な特徴のみで判定（0.6~0.7は普通の値なのでスキップ）
        return 0.0;
      case 'Shiran':
        if (browShape > 0.6) return TutorialClassifier._gradientScore((browShape - 0.6) / 0.4);
        // 極端な特徴のみで判定（0.6~0.7は普通の値なのでスキップ）
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// 各柱の眉間の幅に対するスコアを計算
  static double _getGlabellaWidthScore(String deityId, double glabellaWidth) {
    switch (deityId) {
      case 'Amatera':
        if (glabellaWidth > 0.9) return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1);
        return 0.0;
      case 'Yatael':
        if (glabellaWidth > 0.9) return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1);
        return 0.0;
      case 'Skura':
        if (glabellaWidth > 0.9) return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Delphos':
        if (glabellaWidth < 0.2) return TutorialClassifier._gradientScore((0.2 - glabellaWidth) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Amanoira':
        if (glabellaWidth < 0.2) return TutorialClassifier._gradientScore((0.2 - glabellaWidth) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Noirune':
        if (glabellaWidth < 0.2) return TutorialClassifier._gradientScore((0.2 - glabellaWidth) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Ragias':
        if (glabellaWidth < 0.3) return TutorialClassifier._gradientScore((0.3 - glabellaWidth) / 0.3);
        return 0.0;
      case 'Verdatsu':
        if (glabellaWidth < 0.3) return TutorialClassifier._gradientScore((0.3 - glabellaWidth) / 0.3);
        return 0.0;
      case 'Osiria':
        if (glabellaWidth > 0.9) return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Fatemis':
        if (glabellaWidth < 0.3) return TutorialClassifier._gradientScore((0.3 - glabellaWidth) / 0.3);
        return 0.0;
      case 'Kanonis':
        if (glabellaWidth > 0.9) return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1);
        return 0.0;
      case 'Sylna':
        if (glabellaWidth > 0.9) return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Yorusi':
        if (glabellaWidth > 0.9) return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Tenkora':
        if (glabellaWidth < 0.3) return TutorialClassifier._gradientScore((0.3 - glabellaWidth) / 0.3);
        return 0.0;
      case 'Shisaru':
        if (glabellaWidth > 0.9) return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Mimika':
        if (glabellaWidth < 0.2) return TutorialClassifier._gradientScore((0.2 - glabellaWidth) / 0.2);
        // 極端な特徴のみで判定（0.2~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Tenmira':
        if (glabellaWidth > 0.9) return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Shiran':
        if (glabellaWidth > 0.9) return TutorialClassifier._gradientScore((glabellaWidth - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.7~0.9は普通の値なのでスキップ）
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// 各柱の眉の整いに対するスコアを計算
  static double _getBrowNeatnessScore(String deityId, double browNeatness) {
    switch (deityId) {
      case 'Amatera':
        if (browNeatness > 0.95) return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05);
        return 0.0;
      case 'Yatael':
        if (browNeatness > 0.95) return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.9~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Skura':
        if (browNeatness > 0.95) return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Delphos':
        if (browNeatness < 0.3) return TutorialClassifier._gradientScore((0.3 - browNeatness) / 0.3);
        return 0.0;
      case 'Amanoira':
        if (browNeatness < 0.3) return TutorialClassifier._gradientScore((0.3 - browNeatness) / 0.3);
        return 0.0;
      case 'Noirune':
        if (browNeatness < 0.3) return TutorialClassifier._gradientScore((0.3 - browNeatness) / 0.3);
        return 0.0;
      case 'Ragias':
        if (browNeatness < 0.15) return TutorialClassifier._gradientScore((0.15 - browNeatness) / 0.15);
        // 極端な特徴のみで判定（0.15~0.2は普通の値なのでスキップ）
        return 0.0;
      case 'Verdatsu':
        if (browNeatness < 0.3) return TutorialClassifier._gradientScore((0.3 - browNeatness) / 0.3);
        return 0.0;
      case 'Osiria':
        if (browNeatness > 0.95) return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Fatemis':
        if (browNeatness < 0.15) return TutorialClassifier._gradientScore((0.15 - browNeatness) / 0.15);
        // 極端な特徴のみで判定（0.15~0.2は普通の値なのでスキップ）
        return 0.0;
      case 'Kanonis':
        if (browNeatness > 0.95) return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05);
        return 0.0;
      case 'Sylna':
        if (browNeatness > 0.95) return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Yorusi':
        if (browNeatness > 0.95) return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Tenkora':
        if (browNeatness < 0.15) return TutorialClassifier._gradientScore((0.15 - browNeatness) / 0.15);
        // 極端な特徴のみで判定（0.15~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Shisaru':
        if (browNeatness > 0.95) return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Mimika':
        if (browNeatness < 0.3) return TutorialClassifier._gradientScore((0.3 - browNeatness) / 0.3);
        return 0.0;
      case 'Tenmira':
        if (browNeatness > 0.95) return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Shiran':
        if (browNeatness > 0.95) return TutorialClassifier._gradientScore((browNeatness - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// 各柱の目の特徴に対するスコアを計算（すべての柱が計算される）
  /// 【重要】極端な特徴のみでスコアを計算し、普通の値はスキップ（0.0を返す）
  static double _calculateEyeScore(String deityId, double eyeBalance, double eyeSize, double eyeShape) {
    final scores = <double>[];

    // 極端な特徴のみをスコア計算に使用（普通の値はスキップ）
    // 目のバランス：極端な特徴のみ（>0.85 または <0.35）
    if (eyeBalance > 0.85 || eyeBalance < 0.35) {
      final balanceScore = _getEyeBalanceScore(deityId, eyeBalance);
      if (balanceScore > 0.0) scores.add(balanceScore);
    }

    // 目のサイズ：極端な特徴のみ（>0.9 または <0.3）- 判断基準を厳しくする
    if (eyeSize > 0.9 || eyeSize < 0.3) {
      final sizeScore = _getEyeSizeScore(deityId, eyeSize);
      if (sizeScore > 0.0) scores.add(sizeScore);
    }

    // 目の形状：極端な特徴のみ（>0.95、判断基準を厳しくする）
    if (eyeShape > 0.95) {
      final shapeScore = _getEyeShapeScore(deityId, eyeShape);
      if (shapeScore > 0.0) scores.add(shapeScore);
    }

    // 極端な特徴が1つ以上ある場合のみスコアを計算
    if (scores.isEmpty) return 0.0;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  /// 各柱の目のバランスに対するスコアを計算
  static double _getEyeBalanceScore(String deityId, double eyeBalance) {
    switch (deityId) {
      case 'Amatera':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.75~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Yatael':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Skura':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.8~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Delphos':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Amanoira':
        if (eyeBalance < 0.35) return TutorialClassifier._gradientScore((0.35 - eyeBalance) / 0.35);
        return 0.0;
      case 'Noirune':
        if (eyeBalance < 0.35) return TutorialClassifier._gradientScore((0.35 - eyeBalance) / 0.35);
        return 0.0;
      case 'Ragias':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Verdatsu':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Osiria':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.75~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Fatemis':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Kanonis':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Sylna':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        if (eyeBalance < 0.35) return TutorialClassifier._gradientScore((0.35 - eyeBalance) / 0.35);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Yorusi':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Tenkora':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Shisaru':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Mimika':
        if (eyeBalance < 0.35) return TutorialClassifier._gradientScore((0.35 - eyeBalance) / 0.35);
        return 0.0;
      case 'Tenmira':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      case 'Shiran':
        if (eyeBalance > 0.85) return TutorialClassifier._gradientScore((eyeBalance - 0.85) / 0.15);
        // 極端な特徴のみで判定（0.65~0.85は普通の値なのでスキップ）
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// 各柱の目のサイズに対するスコアを計算
  static double _getEyeSizeScore(String deityId, double eyeSize) {
    switch (deityId) {
      case 'Amatera':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Yatael':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Skura':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        return 0.0;
      case 'Delphos':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Amanoira':
        if (eyeSize < 0.3) return TutorialClassifier._gradientScore((0.3 - eyeSize) / 0.3);
        return 0.0;
      case 'Noirune':
        if (eyeSize < 0.3) return TutorialClassifier._gradientScore((0.3 - eyeSize) / 0.3);
        return 0.0;
      case 'Ragias':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Verdatsu':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Osiria':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Fatemis':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Kanonis':
        if (eyeSize < 0.3) return TutorialClassifier._gradientScore((0.3 - eyeSize) / 0.3);
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.3~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Sylna':
        if (eyeSize < 0.3) return TutorialClassifier._gradientScore((0.3 - eyeSize) / 0.3);
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.3~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Yorusi':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Tenkora':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Shisaru':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Mimika':
        if (eyeSize < 0.3) return TutorialClassifier._gradientScore((0.3 - eyeSize) / 0.3);
        return 0.0;
      case 'Tenmira':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      case 'Shiran':
        if (eyeSize > 0.9) return TutorialClassifier._gradientScore((eyeSize - 0.9) / 0.1);
        // 極端な特徴のみで判定（0.6~0.9は普通の値なのでスキップ）
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// 各柱の目の形状に対するスコアを計算
  static double _getEyeShapeScore(String deityId, double eyeShape) {
    switch (deityId) {
      case 'Amatera':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Yatael':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Skura':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Delphos':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.85~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Amanoira':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Noirune':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Ragias':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.85~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Verdatsu':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Osiria':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Fatemis':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Kanonis':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Sylna':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Yorusi':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Tenkora':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Shisaru':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Mimika':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Tenmira':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      case 'Shiran':
        if (eyeShape > 0.95) return TutorialClassifier._gradientScore((eyeShape - 0.95) / 0.05);
        // 極端な特徴のみで判定（0.7~0.95は普通の値なのでスキップ）
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// 各柱の口の大きさに対するスコアを計算（すべての柱が計算される）
  /// 【重要】極端な特徴のみでスコアを計算し、普通の値はスキップ（0.0を返す）
  static double _calculateMouthScore(String deityId, double mouthSize) {
    // 極端な特徴のみをスコア計算に使用（>0.8 または <0.25、普通の値0.25~0.8はスキップ）
    if (mouthSize <= 0.8 && mouthSize >= 0.25) return 0.0;

    switch (deityId) {
      case 'Amatera':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.75~0.8は普通の値なのでスキップ）
        return 0.0;
      case 'Yatael':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        return 0.0;
      case 'Skura':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        return 0.0;
      case 'Delphos':
        if (mouthSize < 0.25) return TutorialClassifier._gradientScore((0.25 - mouthSize) / 0.25);
        return 0.0;
      case 'Amanoira':
        if (mouthSize < 0.25) return TutorialClassifier._gradientScore((0.25 - mouthSize) / 0.25);
        // 極端な特徴のみで判定（0.25~0.4は普通の値なのでスキップ）
        return 0.0;
      case 'Noirune':
        if (mouthSize < 0.25) return TutorialClassifier._gradientScore((0.25 - mouthSize) / 0.25);
        // 極端な特徴のみで判定（0.25~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Ragias':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.6~0.8は普通の値なのでスキップ）
        return 0.0;
      case 'Verdatsu':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.6~0.8は普通の値なのでスキップ）
        return 0.0;
      case 'Osiria':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.75~0.8は普通の値なのでスキップ）
        return 0.0;
      case 'Fatemis':
        if (mouthSize < 0.25) return TutorialClassifier._gradientScore((0.25 - mouthSize) / 0.25);
        // 極端な特徴のみで判定（0.25~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Kanonis':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.6~0.8は普通の値なのでスキップ）
        return 0.0;
      case 'Sylna':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.6~0.8は普通の値なのでスキップ）
        return 0.0;
      case 'Yorusi':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.6~0.8は普通の値なのでスキップ）
        return 0.0;
      case 'Tenkora':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.6~0.8は普通の値なのでスキップ）
        return 0.0;
      case 'Shisaru':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.6~0.8は普通の値なのでスキップ）
        return 0.0;
      case 'Mimika':
        if (mouthSize < 0.25) return TutorialClassifier._gradientScore((0.25 - mouthSize) / 0.25);
        // 極端な特徴のみで判定（0.25~0.3は普通の値なのでスキップ）
        return 0.0;
      case 'Tenmira':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.6~0.8は普通の値なのでスキップ）
        return 0.0;
      case 'Shiran':
        if (mouthSize > 0.8) return TutorialClassifier._gradientScore((mouthSize - 0.8) / 0.2);
        // 極端な特徴のみで判定（0.6~0.8は普通の値なのでスキップ）
        return 0.0;
      default:
        return 0.0;
    }
  }

  /// 各柱の顔の型に対するスコアを計算（すべての柱が計算される）
  static double _calculateFaceTypeScore(String deityId, String faceType, double faceTypeConfidence) {
    // 信頼度が低い場合はスコアを計算しない
    if (faceTypeConfidence < 0.5) return 0.0;

    // 各柱がどの顔の型に合致するかを判定
    final matchScore = _getFaceTypeMatchScore(deityId, faceType);
    if (matchScore > 0.0) {
      // 信頼度とマッチスコアを組み合わせて最終スコアを計算
      return TutorialClassifier._gradientScore(faceTypeConfidence) * matchScore;
    }
    return 0.0;
  }

  /// 各柱がどの顔の型に合致するかを判定（0.0-1.0）
  static double _getFaceTypeMatchScore(String deityId, String faceType) {
    switch (deityId) {
      case 'Amatera':
        if (faceType == '丸顔' || faceType == '台座顔' || faceType == '三角形顔') return 1.0;
        if (faceType == '卵顔') return 0.5;
        return 0.0;
      case 'Yatael':
        if (faceType == '丸顔') return 1.0;
        return 0.0;
      case 'Skura':
        if (faceType == '丸顔' || faceType == '台座顔' || faceType == '三角形顔') return 1.0;
        return 0.0;
      case 'Delphos':
        if (faceType == '細長顔' || faceType == '卵顔' || faceType == '逆三角形顔' || faceType == '四角顔') return 1.0;
        return 0.0;
      case 'Amanoira':
        if (faceType == '細長顔' || faceType == '逆三角形顔') return 1.0;
        return 0.0;
      case 'Noirune':
        // 顔の型による判定なし（補助的）
        return 0.0;
      case 'Ragias':
        if (faceType == '長方形顔' || faceType == '台座顔' || faceType == '卵顔' || faceType == '四角顔') return 1.0;
        return 0.0;
      case 'Verdatsu':
        if (faceType == '細長顔' || faceType == '長方形顔' || faceType == '卵顔' || faceType == '逆三角形顔') return 1.0;
        return 0.0;
      case 'Osiria':
        if (faceType == '長方形顔' || faceType == '台座顔' || faceType == '三角形顔') return 1.0;
        return 0.0;
      case 'Fatemis':
        // 眉が直線的な場合のみ追加されるため、ここでは低いスコア
        if (faceType == '細長顔' || faceType == '卵顔' || faceType == '逆三角形顔' || faceType == '四角顔') return 0.5;
        return 0.0;
      case 'Kanonis':
        if (faceType == '丸顔' || faceType == '三角形顔') return 1.0;
        return 0.0;
      case 'Sylna':
        if (faceType == '丸顔' || faceType == '三角形顔') return 1.0;
        return 0.0;
      case 'Yorusi':
        // 顔の型による判定なし（補助的）
        return 0.0;
      case 'Tenkora':
        if (faceType == '長方形顔' || faceType == '四角顔') return 1.0;
        return 0.0;
      case 'Shisaru':
        if (faceType == '四角顔') return 1.0;
        return 0.0;
      case 'Mimika':
        // 顔の型による判定なし（補助的）
        return 0.0;
      case 'Tenmira':
        // 顔の型による判定なし（補助的）
        return 0.0;
      case 'Shiran':
        // 顔の型による判定なし（補助的）
        return 0.0;
      default:
        return 0.0;
    }
  }
}
