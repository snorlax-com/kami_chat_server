import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'tutorial_classifier.dart';
import 'face_type_classifier.dart';

/// 樹形図ルーティング型判定結果
class RouterTreeResult {
  final String pillar; // 選ばれた柱
  final double confidence; // 信頼度 0.0-1.0
  final List<String> route; // 通過したルート（例: ["上昇タイプ", "社交・包容", "外向表現型"]）
  final List<String> usedFeatures; // 使用された特徴（例: ["brow_angle", "brow_length", "eye_shape", "mouth_size"]）
  final Map<String, dynamic>? consistencyCheck; // 整合性チェック結果
  final String? reason; // 判定理由

  RouterTreeResult({
    required this.pillar,
    required this.confidence,
    required this.route,
    required this.usedFeatures,
    this.consistencyCheck,
    this.reason,
  });
}

/// 極端特徴抽出結果
class ExtremeFeatures {
  final double? browAngle;
  final double? browLength;
  final double? browThickness;
  final double? browShape;
  final double? browSpace; // glabellaWidth
  final double? browTidy; // browNeatness
  final double? eyeBalance;
  final double? eyeSize;
  final double? eyeShape;
  final double? mouthSize;
  final String? faceType;

  ExtremeFeatures({
    this.browAngle,
    this.browLength,
    this.browThickness,
    this.browShape,
    this.browSpace,
    this.browTidy,
    this.eyeBalance,
    this.eyeSize,
    this.eyeShape,
    this.mouthSize,
    this.faceType,
  });

  /// 極端特徴の数をカウント
  int get extremeFeatureCount {
    int count = 0;
    if (browAngle != null) count++;
    if (browLength != null) count++;
    if (browThickness != null) count++;
    if (browShape != null) count++;
    if (browSpace != null) count++;
    if (browTidy != null) count++;
    if (eyeBalance != null) count++;
    if (eyeSize != null) count++;
    if (eyeShape != null) count++;
    if (mouthSize != null) count++;
    if (faceType != null) count++;
    return count;
  }
}

/// 樹形図ルーティング型判定器（案A）
class RouterTreeClassifier {
  /// 極端特徴の閾値定義
  static const Map<String, dynamic> thresholds = {
    "brow_angle": {
      "up": 0.2,
      "down": -0.2,
      "very_flat": [-0.1, 0.1],
      "flat": [-0.15, 0.15],
      "hachi": -0.3,
    },
    "brow_length": {"high": 0.9, "low": 0.3},
    "brow_thickness": {"high": 0.95, "low": 0.2},
    "brow_shape": {"curve": 0.6, "line": 0.2},
    "brow_space": {"wide": 0.9, "narrow": 0.2},
    "brow_tidy": {"neat": 0.95, "messy": 0.15},
    "eye_balance": {"high": 0.85, "low": 0.35},
    "eye_size": {"high": 0.9, "low": 0.3},
    "eye_shape": {"sharp": 0.95},
    "mouth_size": {"large": 0.8, "small": 0.25},
  };

  /// Step1: 前処理 - 正常範囲チェック
  static bool _isValidValue(double? value) {
    if (value == null) return false;
    return value >= -1.0 && value <= 1.0;
  }

  /// Step2: 極端特徴抽出
  static ExtremeFeatures extractExtremeFeatures(
    double browAngle,
    double browLength,
    double browThickness,
    double browShape,
    double glabellaWidth,
    double browNeatness,
    double eyeBalance,
    double eyeSize,
    double eyeShape,
    double mouthSize,
    String? faceType,
  ) {
    // 眉の角度
    double? extremeBrowAngle;
    if (_isValidValue(browAngle)) {
      if (browAngle > thresholds["brow_angle"]!["up"] ||
          browAngle < thresholds["brow_angle"]!["down"] ||
          (browAngle >= thresholds["brow_angle"]!["very_flat"][0] &&
              browAngle <= thresholds["brow_angle"]!["very_flat"][1]) ||
          (browAngle >= thresholds["brow_angle"]!["flat"][0] && browAngle <= thresholds["brow_angle"]!["flat"][1]) ||
          browAngle < thresholds["brow_angle"]!["hachi"]) {
        extremeBrowAngle = browAngle;
      }
    }

    // 眉の長さ
    double? extremeBrowLength;
    if (_isValidValue(browLength)) {
      if (browLength > thresholds["brow_length"]!["high"] || browLength < thresholds["brow_length"]!["low"]) {
        extremeBrowLength = browLength;
      }
    }

    // 眉の太さ
    double? extremeBrowThickness;
    if (_isValidValue(browThickness)) {
      if (browThickness > thresholds["brow_thickness"]!["high"] ||
          browThickness < thresholds["brow_thickness"]!["low"]) {
        extremeBrowThickness = browThickness;
      }
    }

    // 眉の形状
    double? extremeBrowShape;
    if (_isValidValue(browShape)) {
      if (browShape > thresholds["brow_shape"]!["curve"] || browShape < thresholds["brow_shape"]!["line"]) {
        extremeBrowShape = browShape;
      }
    }

    // 眉間の幅
    double? extremeBrowSpace;
    if (_isValidValue(glabellaWidth)) {
      if (glabellaWidth > thresholds["brow_space"]!["wide"] || glabellaWidth < thresholds["brow_space"]!["narrow"]) {
        extremeBrowSpace = glabellaWidth;
      }
    }

    // 眉の整い
    double? extremeBrowTidy;
    if (_isValidValue(browNeatness)) {
      if (browNeatness > thresholds["brow_tidy"]!["neat"] || browNeatness < thresholds["brow_tidy"]!["messy"]) {
        extremeBrowTidy = browNeatness;
      }
    }

    // 目のバランス
    double? extremeEyeBalance;
    if (_isValidValue(eyeBalance)) {
      if (eyeBalance > thresholds["eye_balance"]!["high"] || eyeBalance < thresholds["eye_balance"]!["low"]) {
        extremeEyeBalance = eyeBalance;
      }
    }

    // 目のサイズ
    double? extremeEyeSize;
    if (_isValidValue(eyeSize)) {
      if (eyeSize > thresholds["eye_size"]!["high"] || eyeSize < thresholds["eye_size"]!["low"]) {
        extremeEyeSize = eyeSize;
      }
    }

    // 目の形状
    double? extremeEyeShape;
    if (_isValidValue(eyeShape)) {
      if (eyeShape > thresholds["eye_shape"]!["sharp"]) {
        extremeEyeShape = eyeShape;
      }
    }

    // 口の大きさ
    double? extremeMouthSize;
    if (_isValidValue(mouthSize)) {
      if (mouthSize > thresholds["mouth_size"]!["large"] || mouthSize < thresholds["mouth_size"]!["small"]) {
        extremeMouthSize = mouthSize;
      }
    }

    return ExtremeFeatures(
      browAngle: extremeBrowAngle,
      browLength: extremeBrowLength,
      browThickness: extremeBrowThickness,
      browShape: extremeBrowShape,
      browSpace: extremeBrowSpace,
      browTidy: extremeBrowTidy,
      eyeBalance: extremeEyeBalance,
      eyeSize: extremeEyeSize,
      eyeShape: extremeEyeShape,
      mouthSize: extremeMouthSize,
      faceType: faceType,
    );
  }

  /// 候補リストを取得（ハイブリッド判定用）
  static List<String> getCandidates(
    Face face,
  ) {
    // 特徴抽出
    final browFeatures = TutorialClassifier.extractBrowFeaturesAdvanced(face);
    final browAngle = browFeatures['angle'] ?? 0.0;
    final browLength = browFeatures['length'] ?? 0.5;
    final browThickness = browFeatures['thickness'] ?? 0.5;
    final browShape = browFeatures['shape'] ?? 0.5;
    final glabellaWidth = browFeatures['glabellaWidth'] ?? 0.5;
    final browNeatness = browFeatures['neatness'] ?? 0.5;

    final eyeFeatures = TutorialClassifier.extractEyeFeaturesForDiagnosis(face);
    final eyeBalance = eyeFeatures['balance'] ?? 0.5;
    final eyeSize = eyeFeatures['size'] ?? 0.5;
    final eyeShape = eyeFeatures['shape'] ?? 0.5;

    final mouthSize = TutorialClassifier.estimateMouthSizeStandard(face);

    final faceTypeResult = FaceTypeClassifier.classify(face);
    final faceType = faceTypeResult.faceType;

    // 極端特徴抽出
    final extremeFeatures = extractExtremeFeatures(
      browAngle,
      browLength,
      browThickness,
      browShape,
      glabellaWidth,
      browNeatness,
      eyeBalance,
      eyeSize,
      eyeShape,
      mouthSize,
      faceType,
    );

    // ルーティング
    final browShapeRoute = _getBrowShapeRoute(extremeFeatures.browShape);
    final browAngleRoute = _getBrowAngleRoute(extremeFeatures.browAngle);
    final glabellaWidthRoute = _getGlabellaWidthRoute(extremeFeatures.browSpace);
    final eyeRoute = _getEyeRoute(extremeFeatures.eyeShape, extremeFeatures.eyeBalance);
    final mouthRoute = _getMouthRoute(extremeFeatures.mouthSize);
    final faceTypeRoute = _getFaceTypeRoute(extremeFeatures.faceType);

    // 柱候補を取得
    final candidates = _getPillarCandidates(
      browShapeRoute,
      browAngleRoute,
      glabellaWidthRoute,
      eyeRoute,
      mouthRoute,
      faceTypeRoute,
      extremeFeatures,
    );

    return candidates;
  }

  /// Step3: 大分類ルーティング - 眉の形状で第一分岐
  static String? _getBrowShapeRoute(double? browShape) {
    if (browShape == null) return null;
    if (browShape > 0.6) return "曲線的";
    if (browShape < 0.2) return "直線的";
    return null;
  }

  /// Step3: 眉の角度で第二分岐
  static String? _getBrowAngleRoute(double? browAngle) {
    if (browAngle == null) return null;
    if (browAngle > 0.2) return "上昇タイプ";
    if (browAngle < -0.2) return "下降タイプ";
    if (browAngle >= -0.15 && browAngle <= 0.15) return "水平タイプ";
    return null;
  }

  /// Step3: 眉間の幅で第三分岐
  static String? _getGlabellaWidthRoute(double? glabellaWidth) {
    if (glabellaWidth == null) return null;
    if (glabellaWidth > 0.9) return "眉間広";
    if (glabellaWidth < 0.2) return "眉間狭";
    return null;
  }

  /// Step3: 目の特徴で第四分岐
  static String? _getEyeRoute(double? eyeShape, double? eyeBalance) {
    if (eyeShape != null && eyeShape > 0.95) return "洞察・集中";
    if (eyeBalance != null && eyeBalance > 0.85) return "積極・開放";
    if (eyeBalance != null && eyeBalance < 0.35) return "内向・沈静";
    return null;
  }

  /// Step3: 口の特徴で第五分岐
  static String? _getMouthRoute(double? mouthSize) {
    if (mouthSize == null) return null;
    if (mouthSize > 0.8) return "外向表現型";
    if (mouthSize < 0.25) return "内向沈静型";
    return null;
  }

  /// Step3: 顔型で最終絞り込み
  static String? _getFaceTypeRoute(String? faceType) {
    if (faceType == null) return null;
    switch (faceType) {
      case '丸顔':
      case '台座顔':
      case '三角形顔':
        return "社交・包容";
      case '細長顔':
      case '逆三角形顔':
        return "思考・分析";
      case '四角顔':
      case '長方形顔':
        return "意志・行動";
      default:
        return null;
    }
  }

  /// Step4: 各グループ内で柱候補を限定
  /// 分岐順: 眉の形状 → 眉の角度 → 眉間の幅 → 目の特徴 → 口の特徴 → 顔の型
  static List<String> _getPillarCandidates(
    String? browShapeRoute,
    String? browAngleRoute,
    String? glabellaWidthRoute,
    String? eyeRoute,
    String? mouthRoute,
    String? faceTypeRoute,
    ExtremeFeatures features,
  ) {
    final candidates = <String>[];

    // 全18柱を初期候補として開始
    final allPillars = [
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
    candidates.addAll(allPillars);

    // 【第一分岐：眉の形状】
    if (browShapeRoute == "曲線的") {
      // 曲線的眉の柱を優先
      final curvedBrowPillars = [
        'Amatera',
        'Yatael',
        'Skura',
        'Noirune',
        'Mimika',
        'Kanonis',
        'Sylna',
        'Tenmira',
        'Shiran'
      ];
      candidates.retainWhere((p) => curvedBrowPillars.contains(p));
    } else if (browShapeRoute == "直線的") {
      // 直線的眉の柱を優先
      final straightBrowPillars = [
        'Ragias',
        'Verdatsu',
        'Delphos',
        'Amanoira',
        'Fatemis',
        'Tenkora',
        'Shisaru',
        'Yorusi'
      ];
      candidates.retainWhere((p) => straightBrowPillars.contains(p));
    }

    // 【第二分岐：眉の角度】
    if (browAngleRoute == "上昇タイプ") {
      // 上昇タイプの柱を優先
      final risingPillars = ['Amatera', 'Ragias', 'Verdatsu', 'Fatemis', 'Tenkora', 'Osiria', 'Shisaru', 'Delphos'];
      candidates.retainWhere((p) => risingPillars.contains(p));
    } else if (browAngleRoute == "下降タイプ") {
      // 下降タイプの柱を優先
      final fallingPillars = ['Noirune', 'Mimika', 'Amanoira', 'Kanonis', 'Sylna'];
      candidates.retainWhere((p) => fallingPillars.contains(p));
    } else if (browAngleRoute == "水平タイプ") {
      // 水平タイプの柱を優先
      final flatPillars = ['Yatael', 'Skura', 'Tenmira', 'Shiran', 'Yorusi'];
      candidates.retainWhere((p) => flatPillars.contains(p));
    }

    // 【第三分岐：眉間の幅】
    if (glabellaWidthRoute == "眉間広") {
      // 眉間が広い柱を優先
      final wideGlabellaPillars = [
        'Amatera',
        'Yatael',
        'Skura',
        'Osiria',
        'Kanonis',
        'Sylna',
        'Tenmira',
        'Shiran',
        'Yorusi',
        'Shisaru'
      ];
      candidates.retainWhere((p) => wideGlabellaPillars.contains(p));
    } else if (glabellaWidthRoute == "眉間狭") {
      // 眉間が狭い柱を優先
      final narrowGlabellaPillars = [
        'Ragias',
        'Verdatsu',
        'Delphos',
        'Amanoira',
        'Fatemis',
        'Noirune',
        'Mimika',
        'Tenkora'
      ];
      candidates.retainWhere((p) => narrowGlabellaPillars.contains(p));
    }

    // 【第四分岐：目の特徴】
    if (eyeRoute == "洞察・集中") {
      // 洞察・集中タイプの柱を優先
      final insightPillars = ['Delphos', 'Amanoira', 'Verdatsu', 'Fatemis', 'Noirune', 'Mimika'];
      candidates.retainWhere((p) => insightPillars.contains(p));
    } else if (eyeRoute == "積極・開放") {
      // 積極・開放タイプの柱を優先
      final activePillars = [
        'Amatera',
        'Ragias',
        'Yatael',
        'Skura',
        'Osiria',
        'Tenmira',
        'Shiran',
        'Yorusi',
        'Shisaru'
      ];
      candidates.retainWhere((p) => activePillars.contains(p));
    } else if (eyeRoute == "内向・沈静") {
      // 内向・沈静タイプの柱を優先
      final introvertPillars = ['Noirune', 'Mimika', 'Amanoira', 'Kanonis', 'Sylna', 'Fatemis', 'Delphos'];
      candidates.retainWhere((p) => introvertPillars.contains(p));
    }

    // 【第五分岐：口の特徴】
    if (mouthRoute == "外向表現型") {
      // 外向表現型の柱を優先
      final extrovertPillars = [
        'Amatera',
        'Ragias',
        'Yatael',
        'Skura',
        'Osiria',
        'Kanonis',
        'Sylna',
        'Tenmira',
        'Shiran',
        'Yorusi',
        'Shisaru'
      ];
      candidates.retainWhere((p) => extrovertPillars.contains(p));
    } else if (mouthRoute == "内向沈静型") {
      // 内向沈静型の柱を優先
      final introvertMouthPillars = ['Fatemis', 'Verdatsu', 'Delphos', 'Noirune', 'Mimika', 'Amanoira', 'Yorusi'];
      candidates.retainWhere((p) => introvertMouthPillars.contains(p));
    }

    // 【最終絞り込み：顔の型】
    if (faceTypeRoute != null && candidates.isNotEmpty) {
      final filtered = <String>[];
      for (final candidate in candidates) {
        if (_matchesFaceType(candidate, faceTypeRoute)) {
          filtered.add(candidate);
        }
      }
      if (filtered.isNotEmpty) {
        candidates.clear();
        candidates.addAll(filtered);
      }
    }

    // 候補が空の場合は全柱を返す
    if (candidates.isEmpty) {
      return allPillars;
    }

    return candidates;
  }

  /// 柱が顔型ルートに一致するかチェック
  static bool _matchesFaceType(String pillar, String faceTypeRoute) {
    final faceTypeMap = {
      "社交・包容": ['Amatera', 'Yatael', 'Skura', 'Osiria', 'Kanonis', 'Sylna', 'Tenmira', 'Shiran'],
      "思考・分析": ['Delphos', 'Amanoira', 'Verdatsu', 'Fatemis', 'Mimika'],
      "意志・行動": ['Ragias', 'Tenkora', 'Shisaru', 'Yorusi'],
    };
    return faceTypeMap[faceTypeRoute]?.contains(pillar) ?? true;
  }

  /// Step5: 整合性レイヤー（Consistency Checker）
  static Map<String, dynamic> _checkConsistency(
    ExtremeFeatures features,
    String? browRoute,
    String? mouthRoute,
  ) {
    double confidencePenalty = 0.0;
    final issues = <String>[];

    // 眉と口の傾向が正反対
    if (browRoute == "上昇タイプ" && mouthRoute == "内向沈静型") {
      confidencePenalty += 0.3;
      issues.add("上がり眉と小口の矛盾");
    }
    if (browRoute == "下降タイプ" && mouthRoute == "外向表現型") {
      confidencePenalty += 0.3;
      issues.add("下がり眉と大口の矛盾");
    }

    // 目のバランスが低く、眉の角度が高い
    if (features.eyeBalance != null &&
        features.eyeBalance! < 0.35 &&
        features.browAngle != null &&
        features.browAngle! > 0.2) {
      confidencePenalty += 0.2;
      issues.add("集中 vs 行動の矛盾");
    }

    return {
      "penalty": confidencePenalty,
      "issues": issues,
      "isConsistent": issues.isEmpty,
    };
  }

  /// メイン判定関数
  static RouterTreeResult diagnose(
    Face face,
  ) {
    // 特徴抽出（既存のメソッドを使用）
    final browFeatures = TutorialClassifier.extractBrowFeaturesAdvanced(face);
    final browAngle = browFeatures['angle'] ?? 0.0;
    final browLength = browFeatures['length'] ?? 0.5;
    final browThickness = browFeatures['thickness'] ?? 0.5;
    final browShape = browFeatures['shape'] ?? 0.5;
    final glabellaWidth = browFeatures['glabellaWidth'] ?? 0.5;
    final browNeatness = browFeatures['neatness'] ?? 0.5;

    final eyeFeatures = TutorialClassifier.extractEyeFeaturesForDiagnosis(face);
    final eyeBalance = eyeFeatures['balance'] ?? 0.5;
    final eyeSize = eyeFeatures['size'] ?? 0.5;
    final eyeShape = eyeFeatures['shape'] ?? 0.5;

    final mouthSize = TutorialClassifier.estimateMouthSizeStandard(face);

    final faceTypeResult = FaceTypeClassifier.classify(face);
    final faceType = faceTypeResult.faceType;

    // 極端特徴抽出
    final extremeFeatures = extractExtremeFeatures(
      browAngle,
      browLength,
      browThickness,
      browShape,
      glabellaWidth,
      browNeatness,
      eyeBalance,
      eyeSize,
      eyeShape,
      mouthSize,
      faceType,
    );

    // 極端特徴が少ない場合は信頼度を下げる
    if (extremeFeatures.extremeFeatureCount < 2) {
      return RouterTreeResult(
        pillar: 'Yatael', // デフォルト
        confidence: 0.3,
        route: ["特徴不足"],
        usedFeatures: [],
        reason: "極端な特徴が少なく、判定が困難です。",
      );
    }

    // ルーティング（正しい順番：眉の形状 → 眉の角度 → 眉間の幅 → 目の特徴 → 口の特徴 → 顔の型）
    final browShapeRoute = _getBrowShapeRoute(extremeFeatures.browShape);
    final browAngleRoute = _getBrowAngleRoute(extremeFeatures.browAngle);
    final glabellaWidthRoute = _getGlabellaWidthRoute(extremeFeatures.browSpace);
    final eyeRoute = _getEyeRoute(extremeFeatures.eyeShape, extremeFeatures.eyeBalance);
    final mouthRoute = _getMouthRoute(extremeFeatures.mouthSize);
    final faceTypeRoute = _getFaceTypeRoute(extremeFeatures.faceType);

    // 眉の特徴が極端でない場合は保留
    if (browShapeRoute == null && browAngleRoute == null && glabellaWidthRoute == null) {
      return RouterTreeResult(
        pillar: 'Yatael', // デフォルト
        confidence: 0.2,
        route: ["判定保留"],
        usedFeatures: [],
        reason: "眉の特徴が極端でないため、判定が困難です。",
      );
    }

    // 柱候補を取得
    final candidates = _getPillarCandidates(
      browShapeRoute,
      browAngleRoute,
      glabellaWidthRoute,
      eyeRoute,
      mouthRoute,
      faceTypeRoute,
      extremeFeatures,
    );

    if (candidates.isEmpty) {
      return RouterTreeResult(
        pillar: 'Yatael', // デフォルト
        confidence: 0.3,
        route: [
          browShapeRoute ?? "不明",
          browAngleRoute ?? "不明",
          glabellaWidthRoute ?? "不明",
          eyeRoute ?? "不明",
          mouthRoute ?? "不明",
          faceTypeRoute ?? "不明"
        ],
        usedFeatures: _getUsedFeatures(extremeFeatures),
        reason: "候補が見つかりませんでした。",
      );
    }

    // 整合性チェック
    final consistency = _checkConsistency(extremeFeatures, browAngleRoute, mouthRoute);

    // 候補が複数ある場合、特徴の一致度で選択
    String selectedPillar = candidates.first;
    if (candidates.length > 1) {
      // より多くの極端特徴に一致する柱を選択
      selectedPillar = _selectBestPillar(candidates, extremeFeatures);
    }

    // 信頼度計算
    double confidence = 0.7 + (extremeFeatures.extremeFeatureCount * 0.05);
    confidence = (confidence - consistency["penalty"]).clamp(0.0, 1.0);

    // ルート情報を構築（正しい順番）
    final route = <String>[];
    if (browShapeRoute != null) route.add(browShapeRoute);
    if (browAngleRoute != null) route.add(browAngleRoute);
    if (glabellaWidthRoute != null) route.add(glabellaWidthRoute);
    if (eyeRoute != null) route.add(eyeRoute);
    if (mouthRoute != null) route.add(mouthRoute);
    if (faceTypeRoute != null) route.add(faceTypeRoute);

    // 使用された特徴を取得
    final usedFeatures = _getUsedFeatures(extremeFeatures);

    // 判定理由を生成
    final reason = _generateReason(selectedPillar, route, extremeFeatures);

    return RouterTreeResult(
      pillar: selectedPillar,
      confidence: confidence,
      route: route,
      usedFeatures: usedFeatures,
      consistencyCheck: consistency,
      reason: reason,
    );
  }

  /// 使用された特徴のリストを取得
  static List<String> _getUsedFeatures(ExtremeFeatures features) {
    final used = <String>[];
    if (features.browAngle != null) used.add("brow_angle");
    if (features.browLength != null) used.add("brow_length");
    if (features.browThickness != null) used.add("brow_thickness");
    if (features.browShape != null) used.add("brow_shape");
    if (features.browSpace != null) used.add("brow_space");
    if (features.browTidy != null) used.add("brow_tidy");
    if (features.eyeBalance != null) used.add("eye_balance");
    if (features.eyeSize != null) used.add("eye_size");
    if (features.eyeShape != null) used.add("eye_shape");
    if (features.mouthSize != null) used.add("mouth_size");
    if (features.faceType != null) used.add("face_type");
    return used;
  }

  /// 最適な柱を選択
  static String _selectBestPillar(
    List<String> candidates,
    ExtremeFeatures features,
  ) {
    // 各候補に対して一致度を計算
    final scores = <String, int>{};
    for (final candidate in candidates) {
      int score = 0;
      // 各特徴が柱の特徴と一致するかチェック
      if (_pillarMatchesFeature(candidate, "brow_angle", features.browAngle)) score++;
      if (_pillarMatchesFeature(candidate, "brow_length", features.browLength)) score++;
      if (_pillarMatchesFeature(candidate, "brow_thickness", features.browThickness)) score++;
      if (_pillarMatchesFeature(candidate, "brow_shape", features.browShape)) score++;
      if (_pillarMatchesFeature(candidate, "eye_balance", features.eyeBalance)) score++;
      if (_pillarMatchesFeature(candidate, "eye_size", features.eyeSize)) score++;
      if (_pillarMatchesFeature(candidate, "eye_shape", features.eyeShape)) score++;
      if (_pillarMatchesFeature(candidate, "mouth_size", features.mouthSize)) score++;
      scores[candidate] = score;
    }

    // 最高スコアの柱を選択
    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  /// 柱が特徴に一致するかチェック
  static bool _pillarMatchesFeature(String pillar, String feature, double? value) {
    if (value == null) return false;
    // 簡易的な一致チェック（詳細は各柱の判定基準に基づく）
    // ここでは基本的な一致のみをチェック
    return true; // 詳細な実装は後で追加
  }

  /// 判定理由を生成
  static String _generateReason(
    String pillar,
    List<String> route,
    ExtremeFeatures features,
  ) {
    final reasons = <String>[];
    if (features.browAngle != null && features.browAngle! > 0.2) {
      reasons.add("眉が上がり、目が開放的 → 行動と明朗性を示唆");
    }
    if (features.mouthSize != null && features.mouthSize! > 0.8) {
      reasons.add("口が大きく表現豊か → 外向性の強化要素");
    }
    if (features.eyeShape != null && features.eyeShape! > 0.95) {
      reasons.add("切れ長の目 → 洞察力と集中力");
    }
    if (reasons.isEmpty) {
      reasons.add("総合的な判定");
    }
    return reasons.join("、");
  }
}
