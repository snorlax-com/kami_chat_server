import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// FaceLandmarkTypeが既にインポートされていることを確認
import 'package:kami_face_oracle/core/tutorial_classifier.dart';
import 'package:kami_face_oracle/core/face_type_classifier.dart';
import 'package:kami_face_oracle/core/personality_mapping_table.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';

/// 診断警告
class DiagnosisWarning {
  final String type; // 'error' or 'warning'
  final String message;
  final String? layer; // 影響を受けた層

  DiagnosisWarning({
    required this.type,
    required this.message,
    this.layer,
  });
}

/// 性格診断結果（樹形図ベース）
class PersonalityTreeDiagnosisResult {
  final int personalityType;
  final String personalityTypeName;
  final String personalityDescription;
  final int? combinationNumber; // 52,488通りの組み合わせ番号
  final bool hasError;
  final List<DiagnosisWarning> warnings;
  final Map<String, String> layerResults; // 各層の判定結果
  final Map<String, double> layerValues; // 各層の数値
  final Map<String, String> layerReasons; // 各層の判定理由
  final List<String> decisionFlow; // 判断フロー（パチンコ玉の流れ）
  final Map<String, dynamic> evidence; // 根拠データ

  PersonalityTreeDiagnosisResult({
    required this.personalityType,
    required this.personalityTypeName,
    required this.personalityDescription,
    this.combinationNumber,
    this.hasError = false,
    this.warnings = const [],
    this.layerResults = const {},
    this.layerValues = const {},
    this.layerReasons = const {},
    this.decisionFlow = const [],
    this.evidence = const {},
  });
}

/// 性格診断分類器（樹形図ベース）
class PersonalityTreeClassifier {
  /// 顔から性格診断を実行
  ///
  /// ⚠️ このメソッドは削除されました。サーバー推論を使用してください。
  /// 代わりに `runDiagnosis(File imageFile)` を使用してください。
  static PersonalityTreeDiagnosisResult diagnose(Face face) {
    // 🔥 ローカル推論は完全削除されました
    // サーバー推論のみを使用してください
    print('[PersonalityTreeClassifier] ❌ ローカル推論は削除されました');
    print('[PersonalityTreeClassifier] ❌ このメソッドは使用できません');
    print('[PersonalityTreeClassifier] ❌ 代わりに runDiagnosis(File imageFile) を使用してください');
    throw Exception('LOCAL_INFERENCE_REMOVED: ローカル推論は削除されました。サーバー推論を使用してください。runDiagnosis(File imageFile) を呼び出してください。');
    final warnings = <DiagnosisWarning>[];
    bool hasError = false;

    // 特徴抽出
    double? browAngle;
    double? browShape;
    double? browThickness;
    double? browLength;
    double? glabellaWidth;
    double? browEyeDistance;
    double? eyeSize;
    double? eyeShape;
    double? mouthSize;
    String? faceType;

    try {
      // ✅ 修正: ランドマークのデバッグログを追加
      print('[PersonalityTreeClassifier] ✅ ランドマーク数: ${face.landmarks.length}');
      print('[PersonalityTreeClassifier] ✅ Contour数: ${face.contours.length}');

      // 重要なランドマークポイントをログ出力
      try {
        final leftEye = face.landmarks[FaceLandmarkType.leftEye];
        final rightEye = face.landmarks[FaceLandmarkType.rightEye];
        final leftMouth = face.landmarks[FaceLandmarkType.leftMouth];
        final rightMouth = face.landmarks[FaceLandmarkType.rightMouth];
        final noseBase = face.landmarks[FaceLandmarkType.noseBase];

        print('[PersonalityTreeClassifier] ✅ raw landmark(左目): ${leftEye?.position}');
        print('[PersonalityTreeClassifier] ✅ raw landmark(右目): ${rightEye?.position}');
        print('[PersonalityTreeClassifier] ✅ raw landmark(口左): ${leftMouth?.position}');
        print('[PersonalityTreeClassifier] ✅ raw landmark(口右): ${rightMouth?.position}');
        print('[PersonalityTreeClassifier] ✅ raw landmark(鼻): ${noseBase?.position}');
      } catch (e) {
        print('[PersonalityTreeClassifier] ⚠️ ランドマークログ出力エラー: $e');
      }

      // 眉の特徴を抽出
      final browFeatures = TutorialClassifier.extractBrowFeaturesAdvanced(face);

      // デバッグ: 生の特徴値を出力（特徴抽出が正しく動作しているか確認）
      print('[PersonalityTreeClassifier] 生の特徴値: ${browFeatures.toString()}');

      // Layer 1: 眉の角度（Python側と同じ調整を適用）
      // Python側: normalized_angle = avg_brow_angle_rad / (math.pi / 2) の後、値の調整を行う
      final rawAngle = browFeatures['angle'] as double? ?? 0.0;
      double adjustedAngle = rawAngle;
      // Python側と同じ調整ロジックを適用
      if (rawAngle < -0.5) {
        adjustedAngle = rawAngle * 2.0; // 負の値を拡大
      } else if (rawAngle > 0.4) {
        adjustedAngle = rawAngle * 1.3; // 正の値を拡大
      } else {
        // 中間の値は縮小（「中」に分類しやすくする）
        if (rawAngle > 0.2) {
          adjustedAngle = rawAngle * 0.05;
        } else if (rawAngle < -0.2) {
          adjustedAngle = rawAngle * 0.08;
        } else if (rawAngle > 0.05) {
          adjustedAngle = rawAngle * 0.02;
        } else if (rawAngle < -0.05) {
          adjustedAngle = rawAngle * 0.03;
        } else {
          adjustedAngle = rawAngle * 0.01;
        }
      }
      browAngle = adjustedAngle.clamp(-1.0, 1.0);

      // ✅ 修正案3: Layer 2の変換を改善（より敏感に反応するように）
      // Layer 2: 眉の形状（Python側と同じ調整を適用、ただしより敏感に）
      final rawShape = browFeatures['shape'] as double? ?? 0.5;
      // 中央値を0.5から0.45にシフトして、より曲線的な眉が検出されやすくする
      double adjustedShape = ((rawShape - 0.45) / 0.55).clamp(-1.0, 1.0);
      // さらに調整（より敏感に）
      if (adjustedShape > 0.1) {
        adjustedShape = 0.5 + (adjustedShape - 0.1) * 0.5; // 曲線的を拡大
      } else if (adjustedShape < -0.1) {
        adjustedShape = -0.5 + (adjustedShape + 0.1) * 0.5; // 直線的を拡大
      }
      browShape = adjustedShape.clamp(-1.0, 1.0);

      // ✅ 修正案3: Layer 3-5の変換を改善（より敏感に反応するように）
      // Layer 3: 眉の濃さ（0.0-1.0を-1.0〜1.0に変換、中央値を0.5から0.4にシフトしてより敏感に）
      final rawThickness = browFeatures['thickness'] as double? ?? 0.5;
      // 中央値を0.4にシフトして、より濃い眉が検出されやすくする
      browThickness = ((rawThickness - 0.4) / 0.6).clamp(-1.0, 1.0);

      // Layer 4: 眉の長さ（0.0-1.0を-1.0〜1.0に変換、中央値を0.5から0.4にシフト）
      final rawLength = browFeatures['length'] as double? ?? 0.5;
      browLength = ((rawLength - 0.4) / 0.6).clamp(-1.0, 1.0);

      // Layer 5: 眉間の幅（0.0-1.0を-1.0〜1.0に変換、中央値を0.5から0.4にシフト）
      final rawGlabellaWidth = browFeatures['glabellaWidth'] as double? ?? 0.5;
      glabellaWidth = ((rawGlabellaWidth - 0.4) / 0.6).clamp(-1.0, 1.0);

      // ✅ 修正案3: Layer 6の変換を改善（より敏感に反応するように）
      // Layer 6: 眉と目の距離（0.0-1.0の範囲を-1.0〜1.0に変換、中央値を0.5から0.4にシフト）
      final rawEyeDistance =
          browFeatures['browEyeDistance'] as double? ?? browFeatures['eyeDistance'] as double? ?? 0.5;
      // 中央値を0.4にシフトして、より離れている眉が検出されやすくする
      // ただし、0.0-1.0の範囲を保持（Python側の実装に合わせる）
      browEyeDistance = rawEyeDistance;

      // ✅ 修正案2: デバッグログを強化（生の値と変換後の値を両方出力）
      print('[PersonalityTreeClassifier] 🔍 特徴抽出の生の値:');
      print('[PersonalityTreeClassifier]   - browAngle (raw): $rawAngle → (adjusted): $browAngle');
      print('[PersonalityTreeClassifier]   - browShape (raw): $rawShape → (adjusted): $browShape');
      print('[PersonalityTreeClassifier]   - browThickness (raw): $rawThickness → (adjusted): $browThickness');
      print('[PersonalityTreeClassifier]   - browLength (raw): $rawLength → (adjusted): $browLength');
      print('[PersonalityTreeClassifier]   - glabellaWidth (raw): $rawGlabellaWidth → (adjusted): $glabellaWidth');
      print('[PersonalityTreeClassifier]   - browEyeDistance (raw): $rawEyeDistance → (adjusted): $browEyeDistance');

      // ✅ 修正案3: 目の特徴の変換を改善（より敏感に反応するように）
      // 目の特徴を抽出
      final eyeFeatures = TutorialClassifier.extractEyeFeaturesForDiagnosis(face);
      // Layer 7: 中央値を0.5から0.4にシフトして、より大きい目が検出されやすくする
      final rawEyeSize = eyeFeatures['size'] as double? ?? 0.5;
      eyeSize = ((rawEyeSize - 0.4) / 0.6).clamp(0.0, 1.0);

      final rawEyeShape = eyeFeatures['shape'] as double? ?? 0.5;
      eyeShape = ((rawEyeShape - 0.4) / 0.6).clamp(0.0, 1.0);

      // デバッグ: 目の特徴を出力（変換前と変換後の両方を出力）
      print('[PersonalityTreeClassifier] 目の特徴（変換前）: size=${eyeFeatures['size']}, shape=${eyeFeatures['shape']}');
      print('[PersonalityTreeClassifier] 目の特徴（変換後）: size=$eyeSize, shape=$eyeShape');

      // ✅ 修正案3: 口の大きさの変換を改善（より敏感に反応するように）
      // 口の大きさを抽出
      final rawMouthSize = TutorialClassifier.estimateMouthSizeStandard(face);
      // 中央値を0.5から0.4にシフトして、より大きい口が検出されやすくする
      mouthSize = ((rawMouthSize - 0.4) / 0.6).clamp(-1.0, 1.0);

      // デバッグ: 口の大きさを出力（変換前と変換後の両方を出力）
      print('[PersonalityTreeClassifier] 口の大きさ（変換前）: $rawMouthSize');
      print('[PersonalityTreeClassifier] 口の大きさ（変換後）: $mouthSize');

      // 顔の型を分類
      final faceTypeResult = FaceTypeClassifier.classify(face);
      faceType = faceTypeResult.faceType;

      // デバッグ: 顔の型を出力
      print('[PersonalityTreeClassifier] 顔の型: $faceType');

      // 必須ランドマークのチェック
      if (face.landmarks.isEmpty) {
        warnings.add(DiagnosisWarning(
          type: 'error',
          message: '顔のランドマークが検出できませんでした',
        ));
        hasError = true;
      }
    } catch (e, stackTrace) {
      print('[PersonalityTreeClassifier] 特徴抽出エラー: $e');
      print('[PersonalityTreeClassifier] スタックトレース: ${stackTrace.toString().split("\n").take(5).join("\n")}');
      warnings.add(DiagnosisWarning(
        type: 'error',
        message: '特徴抽出中にエラーが発生しました: $e',
      ));
      hasError = true;
    }

    // エラーが発生した場合はエラー結果を返す
    if (hasError ||
        browAngle == null ||
        browShape == null ||
        browThickness == null ||
        browLength == null ||
        glabellaWidth == null ||
        browEyeDistance == null ||
        eyeSize == null ||
        eyeShape == null ||
        mouthSize == null ||
        faceType == null) {
      // デバッグ: どの特徴がnullかを出力
      print(
          '[PersonalityTreeClassifier] 特徴抽出エラー: browAngle=$browAngle, browShape=$browShape, browThickness=$browThickness, browLength=$browLength, glabellaWidth=$glabellaWidth, browEyeDistance=$browEyeDistance, eyeSize=$eyeSize, eyeShape=$eyeShape, mouthSize=$mouthSize, faceType=$faceType');
      return PersonalityTreeDiagnosisResult(
        personalityType: 10,
        personalityTypeName: 'エラー',
        personalityDescription: '診断中にエラーが発生しました。写真を撮り直してください。',
        hasError: true,
        warnings: warnings,
      );
    }

    // 各層の判定（デバッグログ付き）
    final layer1 = _judgeLayer1(browAngle);
    print('[PersonalityTreeClassifier] Layer1判定: value=$browAngle → $layer1');

    final layer2 = _judgeLayer2(browShape);
    print('[PersonalityTreeClassifier] Layer2判定: value=$browShape → $layer2');

    final layer3 = _judgeLayer3(browThickness);
    print('[PersonalityTreeClassifier] Layer3判定: value=$browThickness → $layer3');

    final layer4 = _judgeLayer4(browLength);
    print('[PersonalityTreeClassifier] Layer4判定: value=$browLength → $layer4');

    final layer5 = _judgeLayer5(glabellaWidth);
    print('[PersonalityTreeClassifier] Layer5判定: value=$glabellaWidth → $layer5');

    final layer6 = _judgeLayer6(browEyeDistance);
    print('[PersonalityTreeClassifier] Layer6判定: value=$browEyeDistance → $layer6');

    final layer7 = _judgeLayer7(eyeSize, eyeShape);
    print('[PersonalityTreeClassifier] Layer7判定: eyeSize=$eyeSize, eyeShape=$eyeShape → $layer7');

    final layer8 = _judgeLayer8(mouthSize);
    print('[PersonalityTreeClassifier] Layer8判定: value=$mouthSize → $layer8');

    final layer9 = _judgeLayer9(faceType);
    print('[PersonalityTreeClassifier] Layer9判定: faceType=$faceType → $layer9');

    // 層の値を数値化
    // 第1層、第3-8層: 大=2, 中=1, 小=0
    // 第2層: 曲線=1, 直線=0
    final l1 = _layerValueToInt(layer1, layerNum: 1);
    final l2 = _layerValueToInt(layer2, layerNum: 2);
    final l3 = _layerValueToInt(layer3, layerNum: 3);
    final l4 = _layerValueToInt(layer4, layerNum: 4);
    final l5 = _layerValueToInt(layer5, layerNum: 5);
    final l6 = _layerValueToInt(layer6, layerNum: 6);
    final l7 = _layerValueToInt(layer7, layerNum: 7);
    final l8 = _layerValueToInt(layer8, layerNum: 8);
    final l9 = _faceTypeToInt(layer9);

    // 組み合わせ番号を計算（1-34,992）
    // 新しい組み合わせ数: 3 × 2 × 3^6 × 8 = 34,992通り
    final combinationNumber = _calculateCombinationNumber(l1, l2, l3, l4, l5, l6, l7, l8, l9);

    // デバッグ: 層の値を先に出力
    print(
        '[PersonalityTreeClassifier] 層の値: L1=$layer1, L2=$layer2, L3=$layer3, L4=$layer4, L5=$layer5, L6=$layer6, L7=$layer7, L8=$layer8, L9=$layer9');
    print('[PersonalityTreeClassifier] combinationNumber: $combinationNumber');

    // 性格タイプを分類（PersonalityMappingTableを使用）
    final personalityType = PersonalityMappingTable.getPersonalityType(
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

    // デバッグ: 性格タイプを出力
    print('[PersonalityTreeClassifier] 性格タイプ: $personalityType');

    // タイプ名と説明を取得
    final typeName = PersonalityMappingTable.getTypeName(personalityType);
    final typeDescription = PersonalityMappingTable.getTypeDescription(personalityType);

    if (typeName == null || typeDescription == null) {
      print('[PersonalityTreeClassifier] タイプ名または説明がnull: typeName=$typeName, typeDescription=$typeDescription');
      return PersonalityTreeDiagnosisResult(
        personalityType: 10,
        personalityTypeName: 'エラー',
        personalityDescription: '性格タイプの情報を取得できませんでした。',
        hasError: true,
        warnings: warnings,
      );
    }

    // 判断フローを構築
    final decisionFlow = [
      '第1層: $layer1',
      '第2層: $layer2',
      '第3層: $layer3',
      '第4層: $layer4',
      '第5層: $layer5',
      '第6層: $layer6',
      '第7層: $layer7',
      '第8層: $layer8',
      '第9層: $layer9',
    ];

    // 根拠データ
    final evidence = <String, dynamic>{
      'faceType': faceType,
      'faceTypeConfidence': 1.0,
      'browFeatures': {
        'angle': browAngle,
        'shape': browShape,
        'thickness': browThickness,
        'length': browLength,
        'glabellaWidth': glabellaWidth,
        'browEyeDistance': browEyeDistance,
      },
      'eyeFeatures': {
        'size': eyeSize,
        'shape': eyeShape,
      },
      'mouthSize': mouthSize,
    };

    print('[PersonalityTreeClassifier] FINISH');
    print('[AuraFace][STATE] Personality complete');

    return PersonalityTreeDiagnosisResult(
      personalityType: personalityType,
      personalityTypeName: typeName,
      personalityDescription: typeDescription,
      combinationNumber: combinationNumber,
      hasError: false,
      warnings: warnings,
      layerResults: {
        '第1層（眉の角度）': layer1,
        '第2層（眉の形状）': layer2,
        '第3層（眉の濃さ）': layer3,
        '第4層（眉の長さ）': layer4,
        '第5層（眉間の幅）': layer5,
        '第6層（眉と目の距離）': layer6,
        '第7層（目の形状）': layer7,
        '第8層（口の大きさ）': layer8,
        '第9層（顔の型）': layer9,
      },
      layerValues: {
        '第1層（眉の角度）': browAngle,
        '第2層（眉の形状）': browShape,
        '第3層（眉の濃さ）': browThickness,
        '第4層（眉の長さ）': browLength,
        '第5層（眉間の幅）': glabellaWidth,
        '第6層（眉と目の距離）': browEyeDistance,
        '第7層（目の大きさ）': eyeSize,
        '第7層（目の形状）': eyeShape,
        '第8層（口の大きさ）': mouthSize,
      },
      layerReasons: {
        '第1層（眉の角度）': '眉の角度: ${browAngle.toStringAsFixed(3)}',
        '第2層（眉の形状）': '眉の形状: ${browShape.toStringAsFixed(3)}',
        '第3層（眉の濃さ）': '眉の濃さ: ${browThickness.toStringAsFixed(3)}',
        '第4層（眉の長さ）': '眉の長さ: ${browLength.toStringAsFixed(3)}',
        '第5層（眉間の幅）': '眉間の幅: ${glabellaWidth.toStringAsFixed(3)}',
        '第6層（眉と目の距離）': '眉と目の距離: ${browEyeDistance.toStringAsFixed(3)}',
        '第7層（目の形状）': '目の大きさ: ${eyeSize.toStringAsFixed(3)}, 目の形状: ${eyeShape.toStringAsFixed(3)}',
        '第8層（口の大きさ）': '口の大きさ: ${mouthSize.toStringAsFixed(3)}',
        '第9層（顔の型）': '顔の型: $faceType',
      },
      decisionFlow: decisionFlow,
      evidence: evidence,
    );
  }

  /// 第1層: 眉の角度を判定
  /// 値の範囲: -1.0〜1.0（-1.0=右下がり、0.0=水平、1.0=右上がり）
  /// Python側: 分位数ベースの分類を使用（33.3%, 66.7%）
  /// 固定閾値を使用する場合、実際の値の分布に基づいて調整
  static String _judgeLayer1(double value) {
    // 実際の値の分布に基づいて、より適切な閾値を設定
    // 多くの画像で異なる結果が得られるように、閾値を緩和
    if (value > 0.3) return '大（右上がり）';
    if (value < -0.3) return '小（右下がり）';
    return '中（水平）';
  }

  /// 第2層: 眉の形状を判定（曲線/直線の2分類）
  /// 値の範囲: -1.0〜1.0（-1.0=直線的、0.0=中間、1.0=曲線的）
  /// Python側: 0.0-1.0の範囲に変換してから判定
  static String _judgeLayer2(double value) {
    // -1.0〜1.0の値を0.0-1.0に変換
    final normalizedValue = (value + 1.0) / 2.0; // -1.0〜1.0 → 0.0-1.0
    // 閾値0.5で判定（0.5より大きければ曲線、小さければ直線）
    if (normalizedValue > 0.5) return '曲線';
    return '直線';
  }

  /// 第3層: 眉の濃さを判定
  /// 値の範囲: -1.0〜1.0（-1.0=淡い、0.0=標準、1.0=濃い）
  /// ✅ 修正: 閾値を緩和してより多様な結果を得る
  static String _judgeLayer3(double value) {
    // 閾値を0.3から0.15に緩和（より敏感に反応）
    if (value > 0.15) return '大（濃い）';
    if (value < -0.15) return '小（淡い）';
    return '中（標準的）';
  }

  /// 第4層: 眉の長さを判定
  /// 値の範囲: -1.0〜1.0（-1.0=短い、0.0=標準、1.0=長い）
  /// ✅ 修正: 閾値を緩和してより多様な結果を得る
  static String _judgeLayer4(double value) {
    // 閾値を0.3から0.15に緩和（より敏感に反応）
    if (value > 0.15) return '大（長い）';
    if (value < -0.15) return '小（短い）';
    return '中（標準）';
  }

  /// 第5層: 眉間の幅を判定
  /// 値の範囲: -1.0〜1.0（-1.0=狭い、0.0=標準、1.0=広い）
  /// ✅ 修正: 閾値を緩和してより多様な結果を得る
  static String _judgeLayer5(double value) {
    // 閾値を0.3から0.15に緩和（より敏感に反応）
    if (value > 0.15) return '大（広い）';
    if (value < -0.15) return '小（狭い）';
    return '中（標準）';
  }

  /// 第6層: 眉と目の距離を判定
  /// 値の範囲: 0.0-1.0（0.0=近い、0.5=標準、1.0=離れている）
  /// ✅ 修正: 閾値を緩和してより多様な結果を得る
  static String _judgeLayer6(double value) {
    // 閾値を緩和（0.25/0.20 → 0.35/0.25）して、より多様な結果を得る
    if (value > 0.35) return '大（離れている）';
    if (value < 0.25) return '小（近い）';
    return '中（標準）';
  }

  /// 第7層: 目の形状を判定
  /// eyeSizeの範囲: 0.0-1.0（0.0=小さい、0.5=標準、1.0=大きい）
  /// eyeShapeの範囲: 0.0-1.0（0.0=切れ長、0.5=中間、1.0=丸い）
  /// ✅ 修正: 閾値を緩和してより多様な結果を得る
  static String _judgeLayer7(double eyeSize, double eyeShape) {
    // 閾値を緩和して、より多様な結果を得る
    // 大（大きく丸い）: eyeSizeが大きく、eyeShapeが大きい（丸い）
    if (eyeSize > 0.12 && eyeShape > 0.45) return '大（大きく丸い）';
    // 小（細く切れ長）: eyeShapeが小さい（切れ長）またはeyeSizeが小さい
    if (eyeShape < 0.40 || (eyeSize < 0.12 && eyeShape < 0.45)) return '小（細く切れ長）';
    return '中（標準）';
  }

  /// 第8層: 口の大きさを判定
  /// 値の範囲: -1.0〜1.0（-1.0=小さい、0.0=標準、1.0=大きい）
  /// ✅ 修正: 閾値を緩和してより多様な結果を得る
  static String _judgeLayer8(double value) {
    // 閾値を0.3から0.15に緩和（より敏感に反応）
    if (value > 0.15) return '大（大きい）';
    if (value < -0.15) return '小（小さい）';
    return '中（標準）';
  }

  /// 第9層: 顔の型を判定
  /// FaceTypeClassifierは日本語の顔型名を返すため、そのまま使用
  static String _judgeLayer9(String faceType) {
    // FaceTypeClassifierは既に日本語の顔型名を返すため、そのまま使用
    // サポートされている顔型: '丸顔', '細長顔', '長方形顔', '台座顔', '卵顔', '四角顔', '逆三角形顔', '三角形顔'
    final supportedTypes = ['丸顔', '細長顔', '長方形顔', '台座顔', '卵顔', '四角顔', '逆三角形顔', '三角形顔'];
    if (supportedTypes.contains(faceType)) {
      return faceType;
    }
    // 英語のキーが渡された場合のフォールバック（後方互換性のため）
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

  /// 層の値を数値化
  /// 第1層、第3-8層: 大=2, 中=1, 小=0
  /// 第2層: 曲線=1, 直線=0
  static int _layerValueToInt(String value, {int layerNum = 0}) {
    // 第2層の特別処理
    if (layerNum == 2) {
      if (value.contains('曲線')) return 1;
      if (value.contains('直線')) return 0;
      return 0; // デフォルトは直線
    }
    // その他の層
    if (value.contains('大')) return 2;
    if (value.contains('中')) return 1;
    if (value.contains('小')) return 0;
    return 1; // デフォルト
  }

  /// 顔の型を数値化（0-7）
  static int _faceTypeToInt(String faceType) {
    final faceTypeMap = {
      '丸顔': 0,
      '卵顔': 1,
      '細長顔': 2,
      '逆三角形顔': 3,
      '四角顔': 4,
      '台座顔': 5,
      '三角形顔': 6,
      '長方形顔': 7,
    };
    return faceTypeMap[faceType] ?? 1;
  }

  /// 組み合わせ番号を計算（1-34,992）
  /// 新しい組み合わせ数: 3 × 2 × 3^6 × 8 = 34,992通り
  /// 第1層: 3通り（0, 1, 2）
  /// 第2層: 2通り（0=直線, 1=曲線）
  /// 第3-8層: 各3通り（0, 1, 2）
  /// 第9層: 8通り（0-7）
  static int _calculateCombinationNumber(int l1, int l2, int l3, int l4, int l5, int l6, int l7, int l8, int l9) {
    // 組み合わせ番号 = l1×2×3^6×8 + l2×3^6×8 + l3×3^5×8 + l4×3^4×8 + l5×3^3×8 + l6×3^2×8 + l7×3^1×8 + l8×3^0×8 + l9
    int combination = 0;
    combination += l1 * 11664; // 2 × 3^6 × 8 = 2 × 729 × 8 = 11,664
    combination += l2 * 5832; // 3^6 × 8 = 729 × 8 = 5,832
    combination += l3 * 1944; // 3^5 × 8 = 243 × 8 = 1,944
    combination += l4 * 648; // 3^4 × 8 = 81 × 8 = 648
    combination += l5 * 216; // 3^3 × 8 = 27 × 8 = 216
    combination += l6 * 72; // 3^2 × 8 = 9 × 8 = 72
    combination += l7 * 24; // 3^1 × 8 = 3 × 8 = 24
    combination += l8 * 8; // 3^0 × 8 = 1 × 8 = 8
    combination += l9; // 1 (ただし、l9は0-7)
    return combination + 1; // 1-34,992の範囲
  }

  /// 性格タイプからDeityを取得
  static Deity getDeityForPersonalityType(int personalityType) {
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

    final deityId = typeToDeityIdMap[personalityType] ?? 'kanonis';
    return deities.firstWhere(
      (d) => d.id == deityId,
      orElse: () => deities.first,
    );
  }
}
