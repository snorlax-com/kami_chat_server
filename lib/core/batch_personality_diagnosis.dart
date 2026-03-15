import 'dart:math' as math;
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/core/deity.dart';

/// 画像説明から推測した顔の特徴
class EstimatedFaceFeatures {
  final double browAngle; // 眉の角度 (-1.0 to 1.0)
  final double browShape; // 眉の形状 (0.0 to 1.0)
  final double browThickness; // 眉の濃さ (0.0 to 1.0)
  final double browLength; // 眉の長さ (0.0 to 1.0)
  final double glabellaWidth; // 眉間の幅 (0.0 to 1.0)
  final double browEyeDistance; // 眉と目の距離 (0.0 to 1.0)
  final double eyeSize; // 目のサイズ (0.0 to 1.0)
  final double eyeShape; // 目の形状 (0.0 to 1.0)
  final double mouthSize; // 口の大きさ (0.0 to 1.0)
  final String faceType; // 顔の型

  EstimatedFaceFeatures({
    required this.browAngle,
    required this.browShape,
    required this.browThickness,
    required this.browLength,
    required this.glabellaWidth,
    required this.browEyeDistance,
    required this.eyeSize,
    required this.eyeShape,
    required this.mouthSize,
    required this.faceType,
  });
}

/// 画像説明から顔の特徴を推測して性格診断を行う
class BatchPersonalityDiagnosis {
  /// 画像説明から顔の特徴を推測
  static EstimatedFaceFeatures estimateFeaturesFromDescription(String description) {
    // デフォルト値（中程度）
    double browAngle = 0.0; // 水平
    double browShape = 0.5; // 標準
    double browThickness = 0.5; // 標準
    double browLength = 0.5; // 標準
    double glabellaWidth = 0.5; // 標準
    double browEyeDistance = 0.5; // 標準
    double eyeSize = 0.5; // 標準
    double eyeShape = 0.5; // 標準
    double mouthSize = 0.5; // 標準
    String faceType = 'oval'; // 卵顔（デフォルト）

    final desc = description.toLowerCase();

    // 眉の角度の推測
    if (desc.contains('upward') || desc.contains('raised') || desc.contains('arched')) {
      browAngle = 0.3; // 右上がり
    } else if (desc.contains('downward') || desc.contains('drooping') || desc.contains('sad')) {
      browAngle = -0.3; // 右下がり
    } else {
      browAngle = 0.0; // 水平
    }

    // 眉の形状の推測
    if (desc.contains('arched') || desc.contains('curved') || desc.contains('feminine')) {
      browShape = 0.8; // アーチが強い
    } else if (desc.contains('straight') || desc.contains('horizontal') || desc.contains('flat')) {
      browShape = 0.3; // 直線的
    } else {
      browShape = 0.5; // 標準
    }

    // 眉の濃さの推測
    if (desc.contains('thick') || desc.contains('bold') || desc.contains('dark') || desc.contains('well-defined')) {
      browThickness = 0.7; // 濃い
    } else if (desc.contains('thin') || desc.contains('light') || desc.contains('sparse')) {
      browThickness = 0.3; // 薄い
    } else {
      browThickness = 0.5; // 標準
    }

    // 眉の長さの推測（説明からは推測困難、デフォルト）
    browLength = 0.5;

    // 眉間の幅の推測
    if (desc.contains('wide') || desc.contains('broad') || desc.contains('open')) {
      glabellaWidth = 0.7; // 広い
    } else if (desc.contains('narrow') || desc.contains('close') || desc.contains('tight')) {
      glabellaWidth = 0.3; // 狭い
    } else {
      glabellaWidth = 0.5; // 標準
    }

    // 眉と目の距離の推測
    if (desc.contains('wide forehead') || desc.contains('high forehead') || desc.contains('distance')) {
      browEyeDistance = 0.7; // 離れている
    } else if (desc.contains('close') || desc.contains('low forehead')) {
      browEyeDistance = 0.3; // 近い
    } else {
      browEyeDistance = 0.5; // 標準
    }

    // 目のサイズの推測
    if (desc.contains('large') ||
        desc.contains('big') ||
        desc.contains('wide') ||
        desc.contains('round') ||
        desc.contains('almond')) {
      eyeSize = 0.7; // 大きい
    } else if (desc.contains('small') || desc.contains('narrow') || desc.contains('thin')) {
      eyeSize = 0.3; // 小さい
    } else {
      eyeSize = 0.5; // 標準
    }

    // 目の形状の推測
    if (desc.contains('round') || desc.contains('circular') || desc.contains('wide')) {
      eyeShape = 0.2; // 丸い（大きく丸い）
    } else if (desc.contains('almond') ||
        desc.contains('narrow') ||
        desc.contains('slanted') ||
        desc.contains('upturned')) {
      eyeShape = 0.8; // 切れ長
    } else {
      eyeShape = 0.5; // 標準
    }

    // 口の大きさの推測
    if (desc.contains('wide smile') ||
        desc.contains('broad smile') ||
        desc.contains('full lips') ||
        desc.contains('large mouth')) {
      mouthSize = 0.7; // 大きい
    } else if (desc.contains('small') || desc.contains('thin lips') || desc.contains('narrow')) {
      mouthSize = 0.3; // 小さい
    } else {
      mouthSize = 0.5; // 標準
    }

    // 顔の型の推測
    if (desc.contains('round') || desc.contains('circular')) {
      faceType = 'round';
    } else if (desc.contains('oval')) {
      faceType = 'oval';
    } else if (desc.contains('square') || desc.contains('angular')) {
      faceType = 'square';
    } else if (desc.contains('long') || desc.contains('oblong')) {
      faceType = 'oblong';
    } else if (desc.contains('triangle') || desc.contains('pointed')) {
      faceType = 'triangle';
    } else if (desc.contains('inverted triangle') || desc.contains('heart')) {
      faceType = 'inverted_triangle';
    } else {
      faceType = 'oval'; // デフォルト
    }

    return EstimatedFaceFeatures(
      browAngle: browAngle,
      browShape: browShape,
      browThickness: browThickness,
      browLength: browLength,
      glabellaWidth: glabellaWidth,
      browEyeDistance: browEyeDistance,
      eyeSize: eyeSize,
      eyeShape: eyeShape,
      mouthSize: mouthSize,
      faceType: faceType,
    );
  }

  /// 推測した特徴から性格タイプを判定
  static int diagnoseFromFeatures(EstimatedFaceFeatures features) {
    // 各層の判定
    final layer1 = _judgeLayer1(features.browAngle);
    final layer2 = _judgeLayer2(features.browShape);
    final layer3 = _judgeLayer3(features.browThickness);
    final layer4 = _judgeLayer4(features.browLength);
    final layer5 = _judgeLayer5(features.glabellaWidth);
    final layer6 = _judgeLayer6(features.browEyeDistance);
    final layer7 = _judgeLayer7(features.eyeSize, features.eyeShape);
    final layer8 = _judgeLayer8(features.mouthSize);
    final layer9 = _judgeLayer9(features.faceType);

    // 性格タイプを分類
    return _classifyPersonalityType(
      layer1,
      layer2,
      layer3,
      layer4,
      layer5,
      layer6,
      layer7,
      layer8,
      layer9,
    );
  }

  /// 第1層: 眉の角度を判定
  static String _judgeLayer1(double browAngle) {
    if (browAngle > 0.2) return '大（右上がり）';
    if (browAngle < -0.2) return '小（右下がり）';
    return '中（水平）';
  }

  /// 第2層: 眉の形状を判定
  static String _judgeLayer2(double browShape) {
    if (browShape > 0.7) return '大（アーチが強い）';
    if (browShape < 0.3) return '小（緩やかなカーブ）';
    return '中（直線的）';
  }

  /// 第3層: 眉の濃さを判定
  static String _judgeLayer3(double browThickness) {
    if (browThickness > 0.7) return '大（濃い）';
    if (browThickness < 0.3) return '小（淡い）';
    return '中（標準的）';
  }

  /// 第4層: 眉の長さを判定
  static String _judgeLayer4(double browLength) {
    if (browLength > 0.7) return '大（長い）';
    if (browLength < 0.3) return '小（短い）';
    return '中（標準）';
  }

  /// 第5層: 眉間の幅を判定
  static String _judgeLayer5(double glabellaWidth) {
    if (glabellaWidth > 0.7) return '大（広い）';
    if (glabellaWidth < 0.3) return '小（狭い）';
    return '中（標準）';
  }

  /// 第6層: 眉と目の距離を判定
  static String _judgeLayer6(double browEyeDistance) {
    if (browEyeDistance > 0.7) return '大（離れている）';
    if (browEyeDistance < 0.3) return '小（近い）';
    return '中（標準）';
  }

  /// 第7層: 目の形状を判定
  static String _judgeLayer7(double eyeSize, double eyeShape) {
    if (eyeSize > 0.7 && eyeShape < 0.3) return '大（大きく丸い）';
    if (eyeSize < 0.3 && eyeShape > 0.7) return '小（細く切れ長）';
    return '中（標準）';
  }

  /// 第8層: 口の大きさを判定
  static String _judgeLayer8(double mouthSize) {
    if (mouthSize > 0.7) return '大（大きい）';
    if (mouthSize < 0.3) return '小（小さい）';
    return '中（標準）';
  }

  /// 第9層: 顔の型を判定
  static String _judgeLayer9(String faceType) {
    final faceTypeMap = {
      'round': '丸顔',
      'inverted_triangle': '逆三角形顔',
      'triangle': '三角形顔',
      'oval': '卵顔',
      'square': '四角顔',
      'oblong': '細長顔',
      'rectangle': '長方形顔',
      'trapezoid': '台座顔',
    };
    return faceTypeMap[faceType] ?? '卵顔';
  }

  /// 18の性格タイプを分類
  static int _classifyPersonalityType(
    String layer1,
    String layer2,
    String layer3,
    String layer4,
    String layer5,
    String layer6,
    String layer7,
    String layer8,
    String layer9,
  ) {
    // 各層の値を数値化（大=2, 中=1, 小=0）
    final l1 = _layerValueToInt(layer1);
    final l2 = _layerValueToInt(layer2);
    final l3 = _layerValueToInt(layer3);
    final l4 = _layerValueToInt(layer4);
    final l5 = _layerValueToInt(layer5);
    final l6 = _layerValueToInt(layer6);
    final l7 = _layerValueToInt(layer7);
    final l8 = _layerValueToInt(layer8);
    final l9 = _faceTypeToInt(layer9);

    // 積極性スコア（高=2, 中=1, 低=0）
    final aggressiveness = (l1 == 2 ? 2 : (l1 == 1 ? 1 : 0)) + (l3 == 2 ? 1 : 0) + (l8 == 2 ? 1 : 0);

    // 協調性スコア（高=2, 中=1, 低=0）
    final cooperativeness = (l1 == 0 ? 1 : 0) +
        (l2 == 2 ? 2 : (l2 == 0 ? 1 : 0)) +
        (l4 == 2 ? 1 : 0) +
        (l5 == 2 ? 1 : 0) +
        (l7 == 2 ? 1 : 0);

    // 思考スタイル（感情的=2, バランス=1, 理性的=0）
    final thinkingStyle =
        (l6 == 0 ? 2 : (l6 == 2 ? 0 : 1)) + (l7 == 2 ? 1 : (l7 == 0 ? 0 : 0)) + (l8 == 2 ? 1 : (l8 == 0 ? 0 : 0));

    // 社交性スコア（高=2, 中=1, 低=0）
    final sociality = (l5 == 2 ? 1 : 0) + (l7 == 2 ? 1 : 0) + (l8 == 2 ? 1 : 0) + (_isSocialFaceType(layer9) ? 1 : 0);

    // 行動パターン（行動的=2, バランス=1, 慎重=0）
    final actionPattern = (l1 == 2 ? 2 : (l1 == 0 ? 0 : 1)) + (l3 == 2 ? 1 : 0) + (l4 == 0 ? 1 : 0) + (l8 == 2 ? 1 : 0);

    // 18タイプの分類ロジック
    if (aggressiveness >= 4 && cooperativeness >= 3 && sociality >= 3) {
      if (thinkingStyle >= 3) return 17; // 情熱的革新者型
      if (actionPattern >= 4) return 14; // 積極的開拓者型
      return 2; // 協調的リーダー型
    }

    if (aggressiveness >= 4 && cooperativeness < 2) {
      if (actionPattern >= 4) return 1; // 情熱的リーダー型
      return 6; // 実践的行動派型
    }

    if (aggressiveness < 2 && cooperativeness >= 3) {
      if (thinkingStyle >= 3) return 4; // 優しい協調者型
      if (sociality >= 3) return 13; // 寛大な支援者型
      return 15; // 内向的芸術家型
    }

    if (aggressiveness < 2 && cooperativeness < 2) {
      if (thinkingStyle < 2) return 3; // 冷静な分析家型
      if (actionPattern < 2) return 7; // 内向的思考家型
      return 12; // 冷静な観察者型
    }

    if (aggressiveness >= 3 && cooperativeness >= 2 && thinkingStyle >= 3) {
      return 11; // 情熱的表現者型
    }

    if (aggressiveness >= 2 && cooperativeness >= 2 && thinkingStyle < 2) {
      return 9; // 堅実な計画者型
    }

    if (aggressiveness >= 2 && cooperativeness >= 2 && thinkingStyle >= 2 && actionPattern < 2) {
      return 18; // 冷静な完璧主義者型
    }

    if (cooperativeness >= 3 && sociality >= 3) {
      return 8; // 社交的楽天家型
    }

    if (cooperativeness >= 2 && thinkingStyle >= 2) {
      return 5; // 創造的芸術家型
    }

    // デフォルト: バランス型実務家
    return 16;
  }

  /// 層の値を数値化（大=2, 中=1, 小=0）
  static int _layerValueToInt(String value) {
    if (value.contains('大')) return 2;
    if (value.contains('中')) return 1;
    if (value.contains('小')) return 0;
    return 1; // デフォルト
  }

  /// 顔の型を数値化
  static int _faceTypeToInt(String faceType) {
    final socialTypes = ['丸顔', '卵顔', '台座顔'];
    final balancedTypes = ['四角顔', '長方形顔'];
    final analyticalTypes = ['逆三角形顔', '細長顔'];

    if (socialTypes.contains(faceType)) return 2;
    if (balancedTypes.contains(faceType)) return 1;
    if (analyticalTypes.contains(faceType)) return 0;
    return 1; // デフォルト
  }

  /// 社交的な顔の型かどうか
  static bool _isSocialFaceType(String faceType) {
    return ['丸顔', '卵顔', '台座顔'].contains(faceType);
  }

  /// 複数の画像説明から診断を行い、柱の出現頻度をランキング化
  static Map<String, int> diagnoseBatch(List<String> descriptions) {
    final deityCounts = <String, int>{};

    for (final desc in descriptions) {
      final features = estimateFeaturesFromDescription(desc);
      final personalityType = diagnoseFromFeatures(features);
      final deity = PersonalityTreeClassifier.getDeityForPersonalityType(personalityType);

      deityCounts[deity.id] = (deityCounts[deity.id] ?? 0) + 1;
    }

    return deityCounts;
  }

  /// ランキングを表示用にフォーマット
  static List<Map<String, dynamic>> formatRanking(Map<String, int> deityCounts) {
    final ranking = <Map<String, dynamic>>[];

    // 出現回数でソート
    final sortedEntries = deityCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final deity = PersonalityTreeClassifier.getDeityForPersonalityType(_getPersonalityTypeFromDeityId(entry.key));

      ranking.add({
        'rank': i + 1,
        'deityId': entry.key,
        'deityName': deity.nameJa,
        'deityRole': deity.role,
        'count': entry.value,
        'percentage': (entry.value / deityCounts.values.reduce((a, b) => a + b) * 100).toStringAsFixed(1),
      });
    }

    return ranking;
  }

  /// 柱IDから性格タイプを取得（逆引き）
  static int _getPersonalityTypeFromDeityId(String deityId) {
    final typeToDeityIdMap = {
      1: 'yorusi',
      2: 'shisaru',
      3: 'osiria',
      4: 'skura',
      5: 'amatera',
      6: 'delphos',
      7: 'verdatsu',
      8: 'tenkora',
      9: 'amanoira',
      10: 'shiran',
      11: 'yatael',
      12: 'mimika',
      13: 'sylna',
      14: 'tenmira',
      15: 'noirune',
      16: 'kanonis',
      17: 'ragias',
      18: 'fatemis',
    };

    for (final entry in typeToDeityIdMap.entries) {
      if (entry.value == deityId) {
        return entry.key;
      }
    }
    return 1; // デフォルト
  }
}
