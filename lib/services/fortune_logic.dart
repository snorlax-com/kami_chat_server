import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kami_face_oracle/models/face_data_model.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';

/// 運勢診断ロジック（人相学に基づく）
class FortuneLogic {
  /// 初回の基礎相から基礎神（陽占）を判定
  static String determineBaselineDeity(FaceData baseline) {
    // 上停/中停/下停の判定
    final upperStop = (baseline.foreheadBrightness + baseline.browAngle * 0.5).clamp(0.0, 1.0);
    final middleStop = ((baseline.eyeOpen + baseline.noseHeight + baseline.mouthCorner.abs()) / 3).clamp(0.0, 1.0);
    final lowerStop = (baseline.jawSharpness + baseline.jawContour) / 2;

    // 輪郭の判定（角ばり/卵型/丸み）
    final shapeScore = baseline.jawContour;
    String faceShape;
    if (shapeScore > 0.6) {
      faceShape = 'angular'; // 角ばり
    } else if (shapeScore > 0.4) {
      faceShape = 'oval'; // 卵型
    } else {
      faceShape = 'round'; // 丸み
    }

    // 陰陽の判定（肌の明るさとツヤで判定）
    final yinYang = (baseline.skinBrightness + baseline.skinGloss) / 2 > 0.5 ? 'yang' : 'yin';

    // 三停の主軸を決定
    String sanTei;
    if (upperStop >= middleStop && upperStop >= lowerStop) {
      sanTei = 'upper';
    } else if (middleStop >= upperStop && middleStop >= lowerStop) {
      sanTei = 'middle';
    } else {
      sanTei = 'lower';
    }

    // 18神のマッピング
    return _mapToDeityByCategory(sanTei, faceShape, yinYang);
  }

  /// 毎日の運勢を計算（baselineとcurrentの比較）
  static Map<String, dynamic> calculateDailyFortune(FaceData baseline, FaceData current) {
    // 差分を計算
    final deltaBrow = current.browAngle - baseline.browAngle;
    final deltaEye = current.eyeOpen - baseline.eyeOpen;
    final deltaMouth = current.mouthCorner - baseline.mouthCorner;
    final deltaSkin = current.skinBrightness - baseline.skinBrightness;
    final deltaNose = current.noseShine - baseline.noseShine;
    final deltaJaw = baseline.jawSharpness - current.jawSharpness;
    final deltaForehead = current.foreheadBrightness - baseline.foreheadBrightness;
    final deltaCheek = current.cheekColor - baseline.cheekColor;
    final deltaLip = current.lipMoisture - baseline.lipMoisture;

    // 各運勢スコアを計算
    // 精神運：眉角度 + 目の開き + 額の明るさ
    final mental = _normalize(deltaBrow + deltaEye + deltaForehead * 0.5);

    // 感情運：口角角度 + 唇の潤い
    final emotional = _normalize(deltaMouth + deltaLip);

    // 健康運：肌の明るさ + 鼻のツヤ + 頬の血色
    final physical = _normalize(deltaSkin + deltaNose + deltaCheek * 0.5);

    // 対人運：口角 + 肌の明るさ + 頬の血色
    final social = _normalize(deltaMouth + deltaSkin + deltaCheek);

    // 安定運：顎のシャープさ（むくみの逆数）
    final stability = _normalize(-deltaJaw);

    // 総合運勢
    final total = (mental + emotional + physical + social + stability) / 5.0;

    // 三停の判定（変動相から）
    final upperStop = (current.foreheadBrightness + current.browAngle * 0.5).clamp(0.0, 1.0);
    final middleStop = ((current.eyeOpen + current.noseHeight + current.mouthCorner.abs()) / 3).clamp(0.0, 1.0);
    final lowerStop = (current.jawSharpness + current.jawContour) / 2;

    String sanTei;
    if (upperStop >= middleStop && upperStop >= lowerStop) {
      sanTei = 'upper';
    } else if (middleStop >= upperStop && middleStop >= lowerStop) {
      sanTei = 'middle';
    } else {
      sanTei = 'lower';
    }

    // 輪郭の判定
    final shapeScore = current.jawContour;
    String faceShape;
    if (shapeScore > 0.6) {
      faceShape = 'angular';
    } else if (shapeScore > 0.4) {
      faceShape = 'oval';
    } else {
      faceShape = 'round';
    }

    // 陰陽の判定（総合運勢と肌状態から）
    final skinScore = (current.skinBrightness + current.skinGloss) / 2;
    final yinYang = (total > 0.5 && skinScore > 0.5) ? 'yang' : 'yin';

    // 神を判定
    final deity = _mapToDeityByCategory(sanTei, faceShape, yinYang);

    return {
      'mental': mental,
      'emotional': emotional,
      'physical': physical,
      'social': social,
      'stability': stability,
      'total': total,
      'deity': deity,
    };
  }

  /// 値を0..1の範囲に正規化
  static double _normalize(double v) {
    // 差分は-2から+2の範囲になりうるので、それを0..1にマッピング
    return (v.clamp(-2.0, 2.0) + 2.0) / 4.0;
  }

  /// カテゴリから神IDをマッピング
  static String _mapToDeityByCategory(String sanTei, String faceShape, String yinYang) {
    // 18神の分類表に基づく
    final Map<String, Map<String, Map<String, String>>> deityMap = {
      'upper': {
        'angular': {
          'yang': 'amatera',
          'yin': 'delphos',
        },
        'oval': {
          'yang': 'yatael',
          'yin': 'amanoira',
        },
        'round': {
          'yang': 'skura',
          'yin': 'noirune',
        },
      },
      'middle': {
        'angular': {
          'yang': 'ragias',
          'yin': 'fatemis',
        },
        'oval': {
          'yang': 'verdatsu',
          'yin': 'kanonis',
        },
        'round': {
          'yang': 'osiria',
          'yin': 'sylna',
        },
      },
      'lower': {
        'angular': {
          'yang': 'tenkora',
          'yin': 'mimika',
        },
        'oval': {
          'yang': 'yorusi',
          'yin': 'tenmira',
        },
        'round': {
          'yang': 'shisaru',
          'yin': 'shiran',
        },
      },
    };

    return deityMap[sanTei]?[faceShape]?[yinYang] ?? 'amatera';
  }

  /// 神IDからDeityオブジェクトを取得
  static Deity getDeityById(String id) {
    return deities.firstWhere(
      (d) => d.id == id,
      orElse: () => deities.first,
    );
  }

  /// スコアを星の数（1-5）に変換
  static int scoreToStars(double score) {
    if (score >= 0.9) return 5;
    if (score >= 0.7) return 4;
    if (score >= 0.5) return 3;
    if (score >= 0.3) return 2;
    return 1;
  }

  /// 神に応じたメッセージを生成
  static String generateMessage(String deityId, double total) {
    final deity = getDeityById(deityId);
    final baseMessage = deity.shortMessage;

    if (total >= 0.8) {
      return '$baseMessage 今日は特に運気が上昇しています。';
    } else if (total >= 0.6) {
      return '$baseMessage 良い一日になりそうです。';
    } else if (total >= 0.4) {
      return '$baseMessage 小さな変化に気を配りましょう。';
    } else {
      return '$baseMessage 静かに過ごすのも一つの選択です。';
    }
  }

  /// 連続降臨チェック（過去3日間の履歴から）
  static bool checkConsecutiveVisits(List<FortuneResult> history, String deityId) {
    if (history.length < 3) return false;
    final recent = history.sublist(history.length - 3);
    return recent.every((r) => r.deity == deityId);
  }

  /// 連続降臨時の特別メッセージ
  static String getConsecutiveMessage(String deityId) {
    final deity = getDeityById(deityId);
    return '${deity.role}${deity.nameJa}が3日連続で降臨しています。特別な絆が生まれています。';
  }

  /// 4軸（表情、肌、顔骨格、主張）に基づいて神を判定
  ///
  /// 軸1: 表情軸（明/静）- 口角、目の開き、眉角度から判定
  /// 軸2: 肌軸（潤/乾）- ツヤ、潤い、明度から判定
  /// 軸3: 顔骨格軸（直/丸）- 輪郭のシャープさから判定
  /// 軸4: 主張軸（強/柔）- 眉角度、口角、表情の強さから判定
  static String determineDeityByFourAxes(
    FaceData faceData,
    img.Image? image,
    Face? face,
  ) {
    // 軸1: 表情軸（明=1, 静=0）
    final expr = _calculateExpressionAxis(faceData);

    // 軸2: 肌軸（潤=1, 乾=0）
    final skin = _calculateSkinAxis(faceData);

    // 軸3: 顔骨格軸（直=1, 丸=0）
    final shape = _calculateShapeAxis(faceData);

    // 軸4: 主張軸（強=1, 柔=0）
    final claim = _calculateClaimAxis(faceData);

    // 18柱の神から最も近いものを選定（マンハッタン距離を使用）
    return _findClosestDeity(expr, skin, shape, claim);
  }

  /// 表情軸を計算（明=1, 静=0）
  static int _calculateExpressionAxis(FaceData faceData) {
    // 口角が上向き、目の開きが大きい、眉が上がっている → 明（1）
    final mouthScore = (faceData.mouthCorner + 1.0) / 2.0; // -1..1 -> 0..1
    final eyeScore = faceData.eyeOpen;
    final browScore = (faceData.browAngle + math.pi) / (2 * math.pi); // 角度を0..1に正規化

    final expressionScore = (mouthScore * 0.4 + eyeScore * 0.4 + browScore * 0.2);
    return expressionScore > 0.5 ? 1 : 0;
  }

  /// 肌軸を計算（潤=1, 乾=0）
  static int _calculateSkinAxis(FaceData faceData) {
    // ツヤ、明度、反射率が高い → 潤（1）
    final glossScore = faceData.skinGloss;
    final brightnessScore = faceData.skinBrightness;
    final reflectionScore = faceData.foreheadReflection;

    final skinScore = (glossScore * 0.4 + brightnessScore * 0.3 + reflectionScore * 0.3);
    return skinScore > 0.5 ? 1 : 0;
  }

  /// 顔骨格軸を計算（直=1, 丸=0）
  static int _calculateShapeAxis(FaceData faceData) {
    // 輪郭がシャープ、顎がシャープ → 直（1）
    final contourScore = faceData.jawContour;
    final sharpnessScore = faceData.jawSharpness;

    final shapeScore = (contourScore * 0.6 + sharpnessScore * 0.4);
    return shapeScore > 0.5 ? 1 : 0;
  }

  /// 主張軸を計算（強=1, 柔=0）
  static int _calculateClaimAxis(FaceData faceData) {
    // 眉角度が強く、口角が強く、表情がはっきり → 強（1）
    final browStrength = (faceData.browAngle.abs()) / math.pi; // 0..1
    final mouthStrength = faceData.mouthCorner.abs(); // 0..1
    final overallStrength = (faceData.eyeOpen + faceData.skinBrightness) / 2.0;

    final claimScore = (browStrength * 0.3 + mouthStrength * 0.3 + overallStrength * 0.4);
    return claimScore > 0.5 ? 1 : 0;
  }

  /// 4軸の値に最も近い神を選定
  static String _findClosestDeity(int expr, int skin, int shape, int claim) {
    Deity? closestDeity;
    int minDistance = 1000;

    for (final deity in deities) {
      // マンハッタン距離を計算
      final distance = (deity.expr - expr).abs() +
          (deity.skin - skin).abs() +
          (deity.shape - shape).abs() +
          (deity.claim - claim).abs();

      if (distance < minDistance) {
        minDistance = distance;
        closestDeity = deity;
      }
    }

    return closestDeity?.id ?? 'amatera';
  }
}
