import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';
import 'package:kami_face_oracle/core/ai_interfaces.dart';
import 'package:kami_face_oracle/core/texture_analyzer.dart';
import 'package:kami_face_oracle/core/skin_quality_analyzer.dart';

/// 指標キャリブレーション設定（将来はリモート設定で差し替え可）
class SkinCalibConfig {
  static const double capDullness = 0.75;
  static const double capSpot = 0.65;
  static const double capAcne = 0.70;
  static const double capWrinkle = 0.70;
  static const double capEye = 0.90;
  static const double capBrow = 0.90;
  static const double capNose = 0.90;
  static const double capPuff = 0.70;

  // 下限値を引き上げ（逆指標の100%表示を抑制）
  static const double floorLow = 0.10;
  static const double floorMid = 0.15;
  static const double floorGood = 0.10;
  static const double floorBrow = 0.20;

  static const double gammaSoft = 1.05; // わずかに押し上げて低すぎる値を回避
  static const double gammaNone = 1.0;
  static const double gammaMild = 0.90;
}

/// 肌質分析結果を格納するクラス
class SkinAnalysisResult {
  final String skinType;
  final double oiliness;
  final double smoothness;
  final double uniformity;
  final double poreSize;
  final double brightness;
  final List<String> skinIssues;
  final Map<String, double> regionAnalysis;
  final String recommendation;
  // 追加の数値指標（AI検知用）
  final double? dullnessIndex; // くすみ 0..1 高いほどくすみ
  final double? spotDensity; // シミ面積比 0..1
  final double? acneActivity; // ニキビ活動度 0..1
  final double? wrinkleDensity; // しわ密度 0..1
  // 高度指標
  final double? eyeBrightness; // 目の輝き 0..1
  final double? darkCircle; // くま 0..1 高いほど濃い
  final double? browBalance; // 眉バランス 0..1 高いほど整い
  final double? noseGloss; // 鼻ツヤ 0..1
  final double? jawPuffiness; // 顎むくみ 0..1 高いほどむくみ
  // Hugging Face AI診断結果（生の確率値）
  final Map<String, double>?
      aiClassification; // {'acne': 0.0-1.0, 'darkcircle': 0.0-1.0, 'wrinkle': 0.0-1.0, 'swelling': 0.0-1.0, 'normal': 0.0-1.0}
  // 肌の質感と色調（詳細分析）
  final double? textureFineness; // キメの細かさ 0..1 高いほどキメが細かい
  final double? colorUniformity; // 色調の均一性 0..1 高いほど均一（既存のuniformityより詳細）
  // 肌スコア（艶・張り・色ムラ）
  final double? shineScore; // 艶スコア 0..1 高いほど艶がある
  final double? firmnessScore; // 張りスコア 0..1 高いほど張りがある
  final double? toneScore; // 色ムラスコア 0..1 高いほど色ムラが少ない
  // 新しい肌質指標（0-100スコア）
  final double? dryness; // 乾燥 0-100 高いほど乾燥している
  final double? redness; // 赤み 0-100 高いほど赤みが強い
  final double? texture; // キメ/テクスチャ 0-100 高いほどキメが細かい
  final double? evenness; // 透明感/色ムラ 0-100 高いほど透明感があり色ムラが少ない
  final double? firmness; // ハリ・弾力 0-100 高いほどハリがある
  final double? acne; // ニキビ・炎症 0-100 高いほどニキビが多い

  // ⚠️ 【G】raw値（キャリブレーション前の生の値）を保持
  // 保存・デルタ計算はraw値を使用し、UI表示のみcalibrated値を使用
  final double? dullnessIndexRaw; // くすみ（raw値）
  final double? spotDensityRaw; // シミ面積比（raw値）
  final double? acneActivityRaw; // ニキビ活動度（raw値）
  final double? wrinkleDensityRaw; // しわ密度（raw値）
  final double? eyeBrightnessRaw; // 目の輝き（raw値）
  final double? darkCircleRaw; // くま（raw値）
  final double? browBalanceRaw; // 眉バランス（raw値）
  final double? noseGlossRaw; // 鼻ツヤ（raw値）
  final double? jawPuffinessRaw; // 顎むくみ（raw値）

  SkinAnalysisResult({
    required this.skinType,
    required this.oiliness,
    required this.smoothness,
    required this.uniformity,
    required this.poreSize,
    required this.brightness,
    required this.skinIssues,
    required this.regionAnalysis,
    required this.recommendation,
    this.dullnessIndex,
    this.spotDensity,
    this.acneActivity,
    this.wrinkleDensity,
    this.eyeBrightness,
    this.darkCircle,
    this.browBalance,
    this.noseGloss,
    this.jawPuffiness,
    this.aiClassification,
    this.textureFineness,
    this.colorUniformity,
    this.shineScore,
    this.firmnessScore,
    this.toneScore,
    this.dryness,
    this.redness,
    this.texture,
    this.evenness,
    this.firmness,
    this.acne,
    this.dullnessIndexRaw,
    this.spotDensityRaw,
    this.acneActivityRaw,
    this.wrinkleDensityRaw,
    this.eyeBrightnessRaw,
    this.darkCircleRaw,
    this.browBalanceRaw,
    this.noseGlossRaw,
    this.jawPuffinessRaw,
  });

  @override
  String toString() {
    return '''
肌質分析結果:
- 肌タイプ: $skinType
- 油分レベル: ${(oiliness * 100).toStringAsFixed(1)}%
- 滑らかさ: ${(smoothness * 100).toStringAsFixed(1)}%
- 均一性: ${(uniformity * 100).toStringAsFixed(1)}%
- 毛穴サイズ: ${(poreSize * 100).toStringAsFixed(1)}%
- 明度: ${(brightness * 100).toStringAsFixed(1)}%
- 肌の悩み: ${skinIssues.join(', ')}
- 推奨ケア: $recommendation
''';
  }

  Map<String, dynamic> toSimpleMap() => {
        'skinType': skinType,
        'oiliness': oiliness,
        'smoothness': smoothness,
        'uniformity': uniformity,
        'poreSize': poreSize,
        'brightness': brightness,
        'dullnessIndex': dullnessIndex ?? 0.0,
        'spotDensity': spotDensity ?? 0.0,
        'acneActivity': acneActivity ?? 0.0,
        'wrinkleDensity': wrinkleDensity ?? 0.0,
        'eyeBrightness': eyeBrightness ?? 0.0,
        'darkCircle': darkCircle ?? 0.0,
        'browBalance': browBalance ?? 0.0,
        'noseGloss': noseGloss ?? 0.0,
        'jawPuffiness': jawPuffiness ?? 0.0,
      };

  /// JSON形式に変換（保存・再利用用）
  Map<String, dynamic> toJson() => {
        'skinType': skinType,
        'oiliness': oiliness,
        'smoothness': smoothness,
        'uniformity': uniformity,
        'poreSize': poreSize,
        'brightness': brightness,
        'dryness': dryness,
        'redness': redness,
        'texture': texture,
        'evenness': evenness,
        'firmness': firmness,
        'acne': acne,
        'dullnessIndex': dullnessIndex,
        'spotDensity': spotDensity,
        'acneActivity': acneActivity,
        'wrinkleDensity': wrinkleDensity,
        'eyeBrightness': eyeBrightness,
        'darkCircle': darkCircle,
        'browBalance': browBalance,
        'noseGloss': noseGloss,
        'jawPuffiness': jawPuffiness,
        'textureFineness': textureFineness,
        'colorUniformity': colorUniformity,
        'shineScore': shineScore,
        'firmnessScore': firmnessScore,
        'toneScore': toneScore,
        'skinIssues': skinIssues,
        'regionAnalysis': regionAnalysis,
        'recommendation': recommendation,
        'aiClassification': aiClassification,
        // raw値も保存
        'dullnessIndexRaw': dullnessIndexRaw,
        'spotDensityRaw': spotDensityRaw,
        'acneActivityRaw': acneActivityRaw,
        'wrinkleDensityRaw': wrinkleDensityRaw,
        'eyeBrightnessRaw': eyeBrightnessRaw,
        'darkCircleRaw': darkCircleRaw,
        'browBalanceRaw': browBalanceRaw,
        'noseGlossRaw': noseGlossRaw,
        'jawPuffinessRaw': jawPuffinessRaw,
      };

  /// JSON形式から復元
  factory SkinAnalysisResult.fromJson(Map<String, dynamic> json) {
    return SkinAnalysisResult(
      skinType: json['skinType'] ?? 'normal',
      oiliness: (json['oiliness'] ?? 0.0).toDouble(),
      smoothness: (json['smoothness'] ?? 0.0).toDouble(),
      uniformity: (json['uniformity'] ?? 0.0).toDouble(),
      poreSize: (json['poreSize'] ?? 0.0).toDouble(),
      brightness: (json['brightness'] ?? 0.0).toDouble(),
      skinIssues: List<String>.from(json['skinIssues'] ?? []),
      regionAnalysis: Map<String, double>.from(json['regionAnalysis'] ?? {}),
      recommendation: json['recommendation'] ?? '',
      dryness: json['dryness']?.toDouble(),
      redness: json['redness']?.toDouble(),
      texture: json['texture']?.toDouble(),
      evenness: json['evenness']?.toDouble(),
      firmness: json['firmness']?.toDouble(),
      acne: json['acne']?.toDouble(),
      dullnessIndex: json['dullnessIndex']?.toDouble(),
      spotDensity: json['spotDensity']?.toDouble(),
      acneActivity: json['acneActivity']?.toDouble(),
      wrinkleDensity: json['wrinkleDensity']?.toDouble(),
      eyeBrightness: json['eyeBrightness']?.toDouble(),
      darkCircle: json['darkCircle']?.toDouble(),
      browBalance: json['browBalance']?.toDouble(),
      noseGloss: json['noseGloss']?.toDouble(),
      jawPuffiness: json['jawPuffiness']?.toDouble(),
      textureFineness: json['textureFineness']?.toDouble(),
      colorUniformity: json['colorUniformity']?.toDouble(),
      shineScore: json['shineScore']?.toDouble(),
      firmnessScore: json['firmnessScore']?.toDouble(),
      toneScore: json['toneScore']?.toDouble(),
      aiClassification: json['aiClassification'] != null ? Map<String, double>.from(json['aiClassification']) : null,
      dullnessIndexRaw: json['dullnessIndexRaw']?.toDouble(),
      spotDensityRaw: json['spotDensityRaw']?.toDouble(),
      acneActivityRaw: json['acneActivityRaw']?.toDouble(),
      wrinkleDensityRaw: json['wrinkleDensityRaw']?.toDouble(),
      eyeBrightnessRaw: json['eyeBrightnessRaw']?.toDouble(),
      darkCircleRaw: json['darkCircleRaw']?.toDouble(),
      browBalanceRaw: json['browBalanceRaw']?.toDouble(),
      noseGlossRaw: json['noseGlossRaw']?.toDouble(),
      jawPuffinessRaw: json['jawPuffinessRaw']?.toDouble(),
    );
  }

  /// 【G】キャリブレーション済みの値を取得（UI表示用）
  /// raw値がnullの場合はcalibrated値（既存のフィールド）を返す
  double? getDullnessIndexCalibrated() => dullnessIndex;
  double? getSpotDensityCalibrated() => spotDensity;
  double? getAcneActivityCalibrated() => acneActivity;
  double? getWrinkleDensityCalibrated() => wrinkleDensity;
  double? getEyeBrightnessCalibrated() => eyeBrightness;
  double? getDarkCircleCalibrated() => darkCircle;
  double? getBrowBalanceCalibrated() => browBalance;
  double? getNoseGlossCalibrated() => noseGloss;
  double? getJawPuffinessCalibrated() => jawPuffiness;

  /// 【G】raw値を取得（保存・デルタ計算用）
  double? getDullnessIndexRaw() => dullnessIndexRaw ?? dullnessIndex;
  double? getSpotDensityRaw() => spotDensityRaw ?? spotDensity;
  double? getAcneActivityRaw() => acneActivityRaw ?? acneActivity;
  double? getWrinkleDensityRaw() => wrinkleDensityRaw ?? wrinkleDensity;
  double? getEyeBrightnessRaw() => eyeBrightnessRaw ?? eyeBrightness;
  double? getDarkCircleRaw() => darkCircleRaw ?? darkCircle;
  double? getBrowBalanceRaw() => browBalanceRaw ?? browBalance;
  double? getNoseGlossRaw() => noseGlossRaw ?? noseGloss;
  double? getJawPuffinessRaw() => jawPuffinessRaw ?? jawPuffiness;
}

/// 比較デルタ算出ユーティリティ
class SkinDelta {
  final double dullnessDelta;
  final double spotDelta;
  final double acneDelta;
  final double wrinkleDelta;
  final double brightnessDelta;

  SkinDelta({
    required this.dullnessDelta,
    required this.spotDelta,
    required this.acneDelta,
    required this.wrinkleDelta,
    required this.brightnessDelta,
  });
}

extension SkinAnalyzerDelta on SkinAnalyzer {
  /// 【G】raw値を使用してデルタを計算（キャリブレーション前の値を使用）
  static SkinDelta computeDelta({
    required SkinAnalysisResult? baseline,
    required SkinAnalysisResult? previous,
    required SkinAnalysisResult current,
  }) {
    // 直近60% + 恒久40%
    double blend(double cur, double? prev, double? base) {
      final p = prev ?? base ?? cur;
      final b = base ?? prev ?? cur;
      return cur - (0.6 * p + 0.4 * b);
    }

    double val(SkinAnalysisResult? r, double? Function(SkinAnalysisResult r) pick, double fallback) {
      if (r == null) return fallback;
      return pick(r) ?? fallback;
    }

    // ⚠️ 重要: raw値を使用（キャリブレーション前の値）
    final dDelta = blend(
      current.getDullnessIndexRaw() ?? 0.0,
      val(previous, (r) => r.getDullnessIndexRaw(), 0.0),
      val(baseline, (r) => r.getDullnessIndexRaw(), 0.0),
    );
    final sDelta = blend(
      current.getSpotDensityRaw() ?? 0.0,
      val(previous, (r) => r.getSpotDensityRaw(), 0.0),
      val(baseline, (r) => r.getSpotDensityRaw(), 0.0),
    );
    final aDelta = blend(
      current.getAcneActivityRaw() ?? 0.0,
      val(previous, (r) => r.getAcneActivityRaw(), 0.0),
      val(baseline, (r) => r.getAcneActivityRaw(), 0.0),
    );
    final wDelta = blend(
      current.getWrinkleDensityRaw() ?? 0.0,
      val(previous, (r) => r.getWrinkleDensityRaw(), 0.0),
      val(baseline, (r) => r.getWrinkleDensityRaw(), 0.0),
    );
    final bDelta = blend(
      current.brightness,
      previous?.brightness,
      baseline?.brightness,
    );

    return SkinDelta(
      dullnessDelta: dDelta,
      spotDelta: sDelta,
      acneDelta: aDelta,
      wrinkleDelta: wDelta,
      brightnessDelta: bDelta,
    );
  }
}

/// 美運スコア算出（0..1）
/// 重み例: ツヤ0.25/目輝き0.2/口角0.15/血色0.15/むくみ逆数0.15/均一0.1
double computeBeautyLuckScore({
  required SkinAnalysisResult skin,
  required FaceFeatures features,
  double eyeBrightness = 0.6,
  double puffiness = 0.3,
  double symmetry = 0.6, // 参考（未使用だが拡張余地）
}) {
  final gloss = (skin.brightness * (1.0 - (skin.dullnessIndex ?? 0.0))).clamp(0.0, 1.0);
  final even = skin.uniformity.clamp(0.0, 1.0);
  final rednessPenalty = ((skin.acneActivity ?? 0.0) * 0.3 + (skin.spotDensity ?? 0.0) * 0.2).clamp(0.0, 1.0);
  final glossAdj = (0.8 * gloss + 0.2 * features.gloss).clamp(0.0, 1.0);
  // 新指標があれば優先
  final eyeB = (skin.eyeBrightness ?? eyeBrightness).clamp(0.0, 1.0);
  final puff = (skin.jawPuffiness ?? puffiness).clamp(0.0, 1.0);
  final mouth = features.mouthCorner().clamp(0.0, 1.0);
  final luck =
      0.25 * glossAdj + 0.20 * eyeB + 0.15 * mouth + 0.15 * (1.0 - rednessPenalty) + 0.15 * (1.0 - puff) + 0.10 * even;
  return luck.clamp(0.0, 1.0);
}

/// 肌質分析を行うクラス
class SkinAnalyzer {
  /// 画像から肌質を分析する
  static Future<SkinAnalysisResult> analyzeSkin(io.File imageFile, Face face) async {
    // ⚠️ 重要: aiClassificationResultを関数の最初で定義（スコープを確保）
    Map<String, double>? aiClassificationResult;
    // ⚠️ 重要: textureFinenessとcolorUniformityも関数の最初で定義（スコープを確保）
    double? textureFineness;
    double? colorUniformity;
    // 肌スコア（艶・張り・色ムラ）
    double? shineScore;
    double? firmnessScore;
    double? toneScore;

    try {
      // 画像ファイルの存在確認
      if (!await imageFile.exists()) {
        throw Exception('画像ファイルが見つかりません: ${imageFile.path}');
      }

      // 画像を読み込み
      final imageBytes = await imageFile.readAsBytes();
      if (imageBytes.isEmpty) {
        throw Exception('画像ファイルが空です: ${imageFile.path}');
      }

      final image = img.decodeImage(imageBytes is Uint8List ? imageBytes : Uint8List.fromList(imageBytes));

      if (image == null) {
        throw Exception('画像のデコードに失敗しました: ${imageFile.path}');
      }

      if (image.width == 0 || image.height == 0) {
        throw Exception('画像サイズが無効です: ${image.width}x${image.height}');
      }

      // 顔の検出結果を確認
      if (face.boundingBox.width <= 0 || face.boundingBox.height <= 0) {
        throw Exception('顔の検出領域が無効です: width=${face.boundingBox.width}, height=${face.boundingBox.height}');
      }

      // 顔の領域を抽出（顔の形状を保持）
      final faceRegion = _extractFaceRegion(image, face);

      if (faceRegion.width == 0 || faceRegion.height == 0) {
        throw Exception('顔領域の抽出に失敗しました: ${faceRegion.width}x${faceRegion.height}');
      }

      // ⚠️ 重要な修正: AI診断を最優先で実行（エラーが発生してもAI診断は実行する）
      // 肌状態分類AIを使用（aryanshridhar/skin-disease-classification形式に準拠）
      // Hugging Faceモデルを優先：AI結果を80-90%使用、既存分析は10-20%の補助のみ

      try {
        // 顔の形状を活用して肌の部分のみを抽出（髪や背景を除外）
        // ⚠️ エラーが発生しても顔領域全体を使用してAI診断を継続
        img.Image skinOnlyRegion = faceRegion; // デフォルトは顔領域全体
        try {
          skinOnlyRegion = _extractSkinOnlyRegion(faceRegion, face);
        } catch (e, stackTrace) {
          // エラー時は顔領域全体を使用（AI診断は継続）
          skinOnlyRegion = faceRegion;
        }

        // ⚠️ 【A】モデルの初期化と分類（必ず実行・必ずdispose）
        final modelPath = '${AppAiConfig.modelsDir}skin_condition_v2.tflite';
        SkinConditionClassifier? classifier;

        try {
          // モデルファイルの存在確認（Webではio_stubでスキップ）
          final modelFile = io.File(modelPath);
          if (await modelFile.exists()) {
            final fileSize = await modelFile.length();
            print('[SkinAnalyzer] 📁 モデルファイル確認: path=$modelPath, size=$fileSize bytes');
          } else {
            print('[SkinAnalyzer] ⚠️ モデルファイルが見つかりません: $modelPath');
            print('[SkinAnalyzer] 🔍 AI分類スキップ理由: model_missing');
          }

          // SkinConditionClassifierを使用して肌状態を分類
          classifier = SkinConditionClassifier(modelPath);
          print('[SkinAnalyzer] 🔍 AI分類開始: inputSize=${skinOnlyRegion.width}x${skinOnlyRegion.height}');

          final classification = await classifier.classify(skinOnlyRegion);

          if (classification != null) {
            // 出力の合計を確認（softmax後なら≈1）
            final total = classification.values.fold<double>(0.0, (sum, v) => sum + v);
            print('[SkinAnalyzer] ✅ AI分類成功: total=$total');

            // 0.00%連発を検出
            final maxValue = classification.values.reduce((a, b) => a > b ? a : b);
            if (maxValue < 0.01) {
              print('[SkinAnalyzer] ⚠️⚠️⚠️ 警告: AI分類が0.00%連発（最大値=$maxValue）');
              print('[SkinAnalyzer] 🔍 前処理確認: inputSize=${skinOnlyRegion.width}x${skinOnlyRegion.height}');
              print('[SkinAnalyzer] 🔍 出力詳細: $classification');
            }

            aiClassificationResult = classification;
          } else {
            print('[SkinAnalyzer] ⚠️ AI分類結果がnull');
            print('[SkinAnalyzer] 🔍 AI分類スキップ理由: classification_null');
          }
        } catch (e, stackTrace) {
          // 【E】例外の詳細ログを出力
          print('[SkinAnalyzer] ❌ AI分類エラー: $e');
          print('[SkinAnalyzer] 🔍 スタックトレース: ${stackTrace.toString().split("\n").take(10).join("\n")}');

          // エラーの種類を分類
          String errorReason = 'unknown';
          if (e.toString().contains('FileNotFoundException') || e.toString().contains('No such file')) {
            errorReason = 'model_missing';
          } else if (e.toString().contains('Interpreter') || e.toString().contains('initialize')) {
            errorReason = 'interpreter_init_failed';
          } else if (e.toString().contains('input') ||
              e.toString().contains('size') ||
              e.toString().contains('decode')) {
            errorReason = 'invalid_input_image';
          } else if (e.toString().contains('run') ||
              e.toString().contains('invoke') ||
              e.toString().contains('inference')) {
            errorReason = 'inference_failed';
          } else if (e.toString().contains('output') ||
              e.toString().contains('NaN') ||
              e.toString().contains('Infinity')) {
            errorReason = 'output_invalid';
          }

          print('[SkinAnalyzer] 🔍 AI分類スキップ理由: $errorReason');
        } finally {
          // 【A】必ずdispose（nullでもエラーでも）
          try {
            classifier?.dispose();
            print('[SkinAnalyzer] ✅ classifier.dispose() 呼び出し完了');
          } catch (e) {
            print('[SkinAnalyzer] ⚠️ dispose()エラー: $e');
          }
        }
      } catch (e, stackTrace) {
        // AI分類が失敗した場合は既存処理を継続
      }

      // 各分析を実行（TFLiteがあれば置換）
      // ⚠️ エラーが発生してもAI診断結果は既に取得済みなので処理を継続
      double oiliness;
      double smoothness;
      double uniformity;
      double poreSize;
      double brightness;
      double dullnessIndex;
      double spotDensity;
      double acneActivity;
      double wrinkleDensity;

      // 肌の質感と色調の詳細分析
      try {
        var rawTextureFineness = TextureAnalyzer.calculateTextureFineness(faceRegion);
        var rawColorUniformity = TextureAnalyzer.calculateColorUniformity(faceRegion);

        // 値がnullの場合はデフォルト値を設定（0%を避ける）
        final textureFinenessValue = rawTextureFineness ?? 0.3;
        final colorUniformityValue = rawColorUniformity ?? 0.5;

        // 振れ幅を拡大する処理
        // キメの細かさ: 値の範囲を拡張（0.15-1.0 → 0.05-0.95に拡大）
        // 中央値0.5を基準に、低い値はより低く、高い値はより高く拡大
        final finenessCenter = 0.5;
        final finenessExpansion = 1.8; // 拡大係数
        final finenessDiff = (textureFinenessValue - finenessCenter);
        textureFineness = (finenessCenter + finenessDiff * finenessExpansion).clamp(0.05, 0.95);

        // 色調の均一性: 値の範囲を拡張（0.20-1.0 → 0.10-0.95に拡大）
        final uniformityCenter = 0.5;
        final uniformityExpansion = 1.8; // 拡大係数
        final uniformityDiff = (colorUniformityValue - uniformityCenter);
        colorUniformity = (uniformityCenter + uniformityDiff * uniformityExpansion).clamp(0.10, 0.95);
      } catch (e, stackTrace) {
        // エラー時はデフォルト値を設定（0%を避ける）
        if (textureFineness == null) {
          textureFineness = 0.3; // デフォルト値30%
        }
        if (colorUniformity == null) {
          colorUniformity = 0.5; // デフォルト値50%
        }
      }

      try {
        oiliness = _analyzeOiliness(faceRegion);
        smoothness = _analyzeSmoothness(faceRegion);
        // TextureAnalyzerの滑らかさも計算して、既存の結果と統合
        try {
          final textureSmoothness = TextureAnalyzer.calculateSmoothness(faceRegion);
          // 既存の結果とTextureAnalyzerの結果を統合（重み付け平均）
          smoothness = (smoothness * 0.5 + textureSmoothness * 0.5).clamp(0.0, 1.0);
        } catch (e) {
          // エラー時は既存の結果を使用
        }

        uniformity = _analyzeUniformity(faceRegion);
        // TextureAnalyzerの色調の均一性も使用（既存の結果と統合）
        final colorUniformityValue = colorUniformity ?? 0.5;
        uniformity = (uniformity * 0.5 + colorUniformityValue * 0.5).clamp(0.0, 1.0);
        try {
          final tfl = GlossEvennessTFLite('${AppAiConfig.modelsDir}gloss_evenness.tflite');
          final pred = await tfl.predict(faceRegion);
          if (pred != null) {
            uniformity = pred['evenness']?.clamp(0.0, 1.0) ?? uniformity;
          }
        } catch (_) {}
        poreSize = _analyzePoreSize(faceRegion);
        brightness = _analyzeBrightness(faceRegion);
        // 追加の数値指標
        // ⚠️ 重要: dullnessIndexがnullにならないようにデフォルト値を設定
        try {
          dullnessIndex = _calculateDullness(faceRegion);
          // TextureAnalyzerのくすみも使用（既存の結果と統合）
          try {
            final textureDullness = TextureAnalyzer.calculateDullness(faceRegion);
            dullnessIndex = (dullnessIndex * 0.5 + textureDullness * 0.5).clamp(0.0, 1.0);
          } catch (e) {
            // エラー時は既存の結果を使用
            print('[SkinAnalyzer] ⚠️ TextureAnalyzerのくすみ計算エラー: $e');
          }
        } catch (e) {
          print('[SkinAnalyzer] ⚠️ くすみ計算エラー: $e');
          dullnessIndex = 0.3; // デフォルト値（低いくすみ）
        }

        // ⚠️ 重要: dullnessIndexがnullの場合はデフォルト値を設定
        if (dullnessIndex == null) {
          print('[SkinAnalyzer] ⚠️ dullnessIndexがnullのため、デフォルト値を設定');
          dullnessIndex = 0.3;
        }
        spotDensity = await _estimateSpotDensity(faceRegion);
        acneActivity = await _estimateAcneActivity(faceRegion);
        wrinkleDensity = _estimateWrinkleDensity(faceRegion);
      } catch (e) {
        // エラー時はデフォルト値を使用
        oiliness = 0.5;
        smoothness = 0.5;
        uniformity = 0.5;
        poreSize = 0.5;
        brightness = 0.5;
        dullnessIndex = 0.3;
        spotDensity = 0.2;
        acneActivity = 0.2;
        wrinkleDensity = 0.2;
      }

      // 高度指標（ランドマーク使用）
      final adv = _advancedMetrics(image, face);
      final eyeBrightness = adv['eyeBrightness'];
      var darkCircle = adv['darkCircle']; // AI補正のためvarに変更
      final browBalance = adv['browBalance'];
      final noseGloss = adv['noseGloss'];
      var jawPuffiness = adv['jawPuffiness']; // AI補正のためvarに変更

      // セグメント化モデルが利用可能なら上書き
      try {
        final seg = BlemishSegmentation('${AppAiConfig.modelsDir}blemish.tflite');
        final r = await seg.inferMaskRatio(faceRegion);
        if (r != null) {
          spotDensity = (spotDensity * 0.5 + r * 0.5).clamp(0.0, 1.0);
          acneActivity = (acneActivity * 0.8 + r * 0.2).clamp(0.0, 1.0);
        }
      } catch (_) {}

      // ⚠️ 重要: AI診断結果は既に取得済み（最優先で実行済み）
      // UIでは生のAI結果（aiClassification）を100%使用するため、既存分析との融合は行わない
      // aiClassificationResultはそのままSkinAnalysisResultに保存される

      // 肌スコア分析（艶・張り・色ムラ）は後で計算（firmnessとevennessが計算された後）
      // 一時的にデフォルト値を設定
      shineScore = brightness;
      firmnessScore = smoothness;
      toneScore = uniformity;

      // 【G】raw値を保存（キャリブレーション前）
      final dullnessIndexRaw = dullnessIndex;
      final spotDensityRaw = spotDensity;
      final acneActivityRaw = acneActivity;
      final wrinkleDensityRaw = wrinkleDensity;
      final eyeBrightnessRaw = eyeBrightness;
      final darkCircleRaw = darkCircle;
      final browBalanceRaw = browBalance;
      final noseGlossRaw = noseGloss;
      final jawPuffinessRaw = jawPuffiness;

      // 【G】キャリブレーション（UI表示用のみ、保存・デルタ計算はraw値を使用）
      dullnessIndex = _calibrate(dullnessIndex,
          cap: SkinCalibConfig.capDullness, floor: SkinCalibConfig.floorMid, gamma: SkinCalibConfig.gammaMild);
      spotDensity = _calibrate(spotDensity,
          cap: SkinCalibConfig.capSpot, floor: SkinCalibConfig.floorLow, gamma: SkinCalibConfig.gammaSoft);
      acneActivity = _calibrate(acneActivity,
          cap: SkinCalibConfig.capAcne, floor: SkinCalibConfig.floorLow, gamma: SkinCalibConfig.gammaSoft);
      wrinkleDensity = _calibrate(wrinkleDensity,
          cap: SkinCalibConfig.capWrinkle, floor: SkinCalibConfig.floorLow, gamma: SkinCalibConfig.gammaSoft);
      // 良い値側も頭打ち（見た目100%を避ける）
      final eyeB = _calibrate(eyeBrightness ?? 0.6,
          cap: SkinCalibConfig.capEye, floor: SkinCalibConfig.floorGood, gamma: SkinCalibConfig.gammaNone);
      final darkCircleC = _calibrate(darkCircle ?? 0.0,
          cap: SkinCalibConfig.capPuff, floor: SkinCalibConfig.floorLow, gamma: SkinCalibConfig.gammaSoft);
      final browBal = _calibrate(browBalance ?? 0.6,
          cap: SkinCalibConfig.capBrow, floor: SkinCalibConfig.floorBrow, gamma: SkinCalibConfig.gammaNone);
      final noseG = _calibrate(noseGloss ?? 0.5,
          cap: SkinCalibConfig.capNose, floor: SkinCalibConfig.floorGood, gamma: SkinCalibConfig.gammaNone);
      final jawPuf = _calibrate(jawPuffiness ?? 0.3,
          cap: SkinCalibConfig.capPuff, floor: SkinCalibConfig.floorMid, gamma: SkinCalibConfig.gammaSoft);

      // 既存の課題検出に数値指標を反映
      var skinIssues = await _detectSkinIssues(faceRegion,
          dullnessIndex: dullnessIndex, spotDensity: spotDensity, acneActivity: acneActivity);
      final regionAnalysis = _analyzeRegions(faceRegion, face);

      // 肌タイプを判定（既存ロジック）
      var skinType = _determineSkinType(oiliness, smoothness, uniformity);

      // 新しい肌質指標を計算（ROIベース）
      double? dryness;
      double? redness;
      double? texture;
      double? evenness;
      double? firmness;
      double? acne;

      // ⚠️ 重要: 計算を実行する前に、face.boundingBoxとimageが有効か確認
      // ⚠️ 重要: tryブロックの外で変数を初期化して、確実に実行されるようにする
      print('[SkinAnalyzer] 🔍 SkinQualityAnalyzerの計算を開始します...');
      print('[SkinAnalyzer] image: ${image.width}x${image.height}');
      print('[SkinAnalyzer] face.boundingBox: ${face.boundingBox}');

      try {
        final faceBox = face.boundingBox;
        print(
            '[SkinAnalyzer] 顔領域: left=${faceBox.left}, top=${faceBox.top}, width=${faceBox.width}, height=${faceBox.height}');
        print('[SkinAnalyzer] 画像サイズ: width=${image.width}, height=${image.height}');

        // 顔領域と画像サイズの妥当性チェック
        if (faceBox.width <= 0 || faceBox.height <= 0) {
          print('[SkinAnalyzer] ⚠️ 顔領域が無効です: width=${faceBox.width}, height=${faceBox.height}');
          // エラーをthrowせず、デフォルト値を設定して続行
          dryness = 50.0;
          texture = 50.0;
          evenness = 50.0;
        } else if (image.width <= 0 || image.height <= 0) {
          print('[SkinAnalyzer] ⚠️ 画像サイズが無効です: width=${image.width}, height=${image.height}');
          // エラーをthrowせず、デフォルト値を設定して続行
          dryness = 50.0;
          texture = 50.0;
          evenness = 50.0;
        } else {
          // 各指標を計算（0-100スコア）
          // ⚠️ 重要: エラーが発生してもデフォルト値を設定する
          try {
            dryness = SkinQualityAnalyzer.calculateDryness(image, faceBox);
            print('[SkinAnalyzer] 乾燥: $dryness');
          } catch (e) {
            print('[SkinAnalyzer] ⚠️ 乾燥計算エラー: $e');
            dryness = 50.0; // デフォルト値
          }

          try {
            redness = SkinQualityAnalyzer.calculateRedness(image, faceBox);
            print('[SkinAnalyzer] 赤み: $redness');
          } catch (e) {
            print('[SkinAnalyzer] ⚠️ 赤み計算エラー: $e');
            redness = 30.0; // デフォルト値
          }

          try {
            texture = SkinQualityAnalyzer.calculateTexture(image, faceBox);
            print('[SkinAnalyzer] キメ: $texture');
          } catch (e) {
            print('[SkinAnalyzer] ⚠️ キメ計算エラー: $e');
            texture = 50.0; // デフォルト値
          }

          try {
            evenness = SkinQualityAnalyzer.calculateEvenness(image, faceBox);
            print('[SkinAnalyzer] 透明感: $evenness');
          } catch (e) {
            print('[SkinAnalyzer] ⚠️ 透明感計算エラー: $e');
            evenness = 50.0; // デフォルト値
          }

          try {
            firmness = SkinQualityAnalyzer.calculateFirmness(image, faceBox);
            print('[SkinAnalyzer] ハリ: $firmness');
          } catch (e) {
            print('[SkinAnalyzer] ⚠️ ハリ計算エラー: $e');
            firmness = 50.0; // デフォルト値
          }

          try {
            acne = SkinQualityAnalyzer.calculateAcne(image, faceBox);
            print('[SkinAnalyzer] ニキビ: $acne');
          } catch (e) {
            print('[SkinAnalyzer] ⚠️ ニキビ計算エラー: $e');
            acne = 20.0; // デフォルト値
          }

          // 皮脂量も新しいロジックで再計算（既存のoilinessと統合）
          try {
            final newOiliness = SkinQualityAnalyzer.calculateOiliness(image, faceBox);
            print('[SkinAnalyzer] 新しい皮脂量: $newOiliness');
            // 既存のoilinessと新しい値を統合（既存70%、新30%）
            final oilinessValue = (oiliness * 0.7 + (newOiliness / 100.0) * 0.3).clamp(0.0, 1.0);
            oiliness = oilinessValue;
            print('[SkinAnalyzer] 統合後の皮脂量: ${oiliness * 100}');
          } catch (e) {
            print('[SkinAnalyzer] ⚠️ 皮脂量計算エラー: $e');
            // エラー時は既存のoilinessを保持
          }

          // 新しい指標に基づいて肌タイプを再判定
          if (dryness != null && redness != null && acne != null) {
            try {
              final newSkinType = SkinQualityAnalyzer.detectSkinType(
                oiliness: oiliness * 100.0,
                dryness: dryness,
                redness: redness,
                acne: acne,
              );
              // 既存のskinTypeと新しい判定を統合
              if (newSkinType != 'normal' && skinType == 'normal') {
                skinType = newSkinType;
              } else if (newSkinType == 'sensitive') {
                // 敏感肌は優先
                skinType = 'sensitive';
              }
            } catch (e) {
              print('[SkinAnalyzer] ⚠️ 肌タイプ判定エラー: $e');
              // エラー時は既存のskinTypeを保持
            }
          }
        }
      } catch (e, stackTrace) {
        print('[SkinAnalyzer] ❌ 新しい肌質指標の計算エラー: $e');
        print('[SkinAnalyzer] スタックトレース: ${stackTrace.toString().split("\n").take(5).join("\n")}');
        // ⚠️ 重要: エラー時もデフォルト値を設定
        if (dryness == null) {
          dryness = 50.0;
          print('[SkinAnalyzer] ⚠️ 乾燥にデフォルト値を設定: $dryness');
        }
        if (texture == null) {
          texture = 50.0;
          print('[SkinAnalyzer] ⚠️ キメにデフォルト値を設定: $texture');
        }
        if (evenness == null) {
          evenness = 50.0;
          print('[SkinAnalyzer] ⚠️ 透明感にデフォルト値を設定: $evenness');
        }
      }

      // ⚠️ 重要: tryブロックの外でも、確実にデフォルト値を設定
      print('[SkinAnalyzer] 🔍 SkinQualityAnalyzerの計算後の状態確認:');
      print('[SkinAnalyzer]   - dryness: $dryness');
      print('[SkinAnalyzer]   - texture: $texture');
      print('[SkinAnalyzer]   - evenness: $evenness');

      // ⚠️ 重要: 各指標がnullの場合はデフォルト値または既存値から推測
      if (dryness == null) {
        dryness = 50.0;
        print('[SkinAnalyzer] ⚠️ 乾燥がnullのため、デフォルト値を設定: $dryness');
      }
      if (texture == null) {
        // textureFinenessから推測（0.0-1.0を0-100に変換）
        if (textureFineness != null) {
          texture = (textureFineness * 100.0).clamp(0.0, 100.0);
          print('[SkinAnalyzer] ⚠️ キメがnullのため、textureFinenessから推測: $texture');
        } else {
          texture = 50.0;
          print('[SkinAnalyzer] ⚠️ キメがnullのため、デフォルト値を設定: $texture');
        }
      }
      if (evenness == null) {
        // uniformityから推測（0.0-1.0を0-100に変換）
        evenness = (uniformity * 100.0).clamp(0.0, 100.0);
        print('[SkinAnalyzer] ⚠️ 透明感がnullのため、uniformityから推測: $evenness');
      }

      // ⚠️ 重要: dullnessIndexがnullの場合はbrightnessから推測
      if (dullnessIndex == null) {
        // brightnessが低いほどくすみが高い（反転）
        dullnessIndex = (1.0 - brightness).clamp(0.0, 1.0);
        print('[SkinAnalyzer] ⚠️ dullnessIndexがnullのため、brightnessから推測: $dullnessIndex');
      }

      // 肌スコア分析（艶・張り・色ムラ）- firmnessとevennessが計算された後に再計算
      try {
        // shineScore（艶）: brightnessとnoseGlossから計算
        shineScore = (brightness * 0.6 + (noseGloss ?? 0.5) * 0.4).clamp(0.0, 1.0);
        // firmnessScore（張り）: smoothnessとfirmnessから計算
        if (firmness != null) {
          firmnessScore = (smoothness * 0.5 + (firmness! / 100.0) * 0.5).clamp(0.0, 1.0);
        }
        // toneScore（色ムラ）: evennessとuniformityから計算
        if (evenness != null) {
          toneScore = ((evenness! / 100.0) * 0.6 + uniformity * 0.4).clamp(0.0, 1.0);
        }
      } catch (e) {
        // エラー時は既存の値を保持
      }

      // AI診断結果がnullまたはすべて0.00%の場合、エラー情報を追加
      bool hasSkinDiagnosisError = false;
      if (aiClassificationResult == null || aiClassificationResult.isEmpty) {
        hasSkinDiagnosisError = true;
        skinIssues = List<String>.from(skinIssues)..add('診断エラー: AI診断結果が取得できませんでした。写真を撮り直してください。');
      } else {
        final wrinkle = (aiClassificationResult['wrinkle'] ?? 0.0) * 100;
        final normal = (aiClassificationResult['normal'] ?? 0.0) * 100;
        final darkCircle = (aiClassificationResult['darkcircle'] ?? 0.0) * 100;
        final aiAcne = (aiClassificationResult['acne'] ?? 0.0) * 100;
        final swelling = (aiClassificationResult['swelling'] ?? 0.0) * 100;
        final total = wrinkle + normal + darkCircle + aiAcne + swelling;

        if (total < 0.01 ||
            (wrinkle < 0.01 && normal < 0.01 && darkCircle < 0.01 && aiAcne < 0.01 && swelling < 0.01)) {
          hasSkinDiagnosisError = true;
          skinIssues = List<String>.from(skinIssues)..add('診断エラー: すべての診断値が0.00%です。写真を撮り直してください。');
        }
      }

      // 推奨ケアを生成
      String recommendation = _generateRecommendation(skinType, skinIssues, oiliness);

      // エラーが発生した場合は、推奨メッセージをエラーメッセージに置き換え
      if (hasSkinDiagnosisError) {
        recommendation = '肌診断の分析に失敗しました。写真を撮り直してアップロードしてください。';
      }

      // ⚠️ 重要: 最終的なnullチェックとデフォルト値設定（SkinAnalysisResultを作成する直前）
      if (dryness == null) {
        dryness = 50.0;
        print('[SkinAnalyzer] ⚠️ 最終チェック: 乾燥がnullのため、デフォルト値を設定: $dryness');
      }
      if (texture == null) {
        if (textureFineness != null) {
          texture = (textureFineness * 100.0).clamp(0.0, 100.0);
          print('[SkinAnalyzer] ⚠️ 最終チェック: キメがnullのため、textureFinenessから推測: $texture');
        } else {
          texture = 50.0;
          print('[SkinAnalyzer] ⚠️ 最終チェック: キメがnullのため、デフォルト値を設定: $texture');
        }
      }
      if (evenness == null) {
        evenness = (uniformity * 100.0).clamp(0.0, 100.0);
        print('[SkinAnalyzer] ⚠️ 最終チェック: 透明感がnullのため、uniformityから推測: $evenness');
      }
      if (dullnessIndex == null) {
        dullnessIndex = (1.0 - brightness).clamp(0.0, 1.0);
        print('[SkinAnalyzer] ⚠️ 最終チェック: dullnessIndexがnullのため、brightnessから推測: $dullnessIndex');
      }

      final result = SkinAnalysisResult(
        skinType: skinType,
        oiliness: oiliness,
        smoothness: smoothness,
        uniformity: uniformity,
        poreSize: poreSize,
        brightness: brightness,
        skinIssues: skinIssues,
        regionAnalysis: regionAnalysis,
        recommendation: recommendation,
        dullnessIndex: dullnessIndex, // キャリブレーション済み（UI表示用）
        spotDensity: spotDensity, // キャリブレーション済み（UI表示用）
        acneActivity: acneActivity, // キャリブレーション済み（UI表示用）
        wrinkleDensity: wrinkleDensity, // キャリブレーション済み（UI表示用）
        eyeBrightness: eyeB, // キャリブレーション済み（UI表示用）
        darkCircle: darkCircleC, // キャリブレーション済み（UI表示用）
        browBalance: browBal, // キャリブレーション済み（UI表示用）
        noseGloss: noseG, // キャリブレーション済み（UI表示用）
        jawPuffiness: jawPuf, // キャリブレーション済み（UI表示用）
        aiClassification: aiClassificationResult, // Hugging Face AI診断結果を保存
        textureFineness: textureFineness, // キメの細かさ
        colorUniformity: colorUniformity, // 色調の均一性
        shineScore: shineScore, // 艶スコア
        firmnessScore: firmnessScore, // 張りスコア
        toneScore: toneScore, // 色ムラスコア
        dryness: dryness!, // 乾燥（0-100）- nullチェック済み
        redness: redness ?? 30.0, // 赤み（0-100）- デフォルト値30.0
        texture: texture!, // キメ/テクスチャ（0-100）- nullチェック済み
        evenness: evenness!, // 透明感/色ムラ（0-100）- nullチェック済み
        firmness: firmness ?? 50.0, // ハリ・弾力（0-100）- デフォルト値50.0
        acne: acne ?? 20.0, // ニキビ・炎症（0-100）- デフォルト値20.0
        // 【G】raw値を保存（キャリブレーション前）
        dullnessIndexRaw: dullnessIndexRaw,
        spotDensityRaw: spotDensityRaw,
        acneActivityRaw: acneActivityRaw,
        wrinkleDensityRaw: wrinkleDensityRaw,
        eyeBrightnessRaw: eyeBrightnessRaw,
        darkCircleRaw: darkCircleRaw,
        browBalanceRaw: browBalanceRaw,
        noseGlossRaw: noseGlossRaw,
        jawPuffinessRaw: jawPuffinessRaw,
      );

      // デバッグ: 最終的な値を確認
      print('[SkinAnalyzer] ✅ 最終診断結果:');
      print('[SkinAnalyzer]   - dullnessIndex: $dullnessIndex');
      print('[SkinAnalyzer]   - dryness: $dryness');
      print('[SkinAnalyzer]   - texture: $texture');
      print('[SkinAnalyzer]   - evenness: $evenness');
      print('[SkinAnalyzer]   - brightness: $brightness');

      // デバッグ: 保存された値を確認

      return result;
    } catch (e, stackTrace) {
      // ⚠️ 重要な修正: エラーが発生しても、計算済みのtextureFinenessとcolorUniformityを保持
      // エラー時でも計算済みの値があれば使用、なければデフォルト値を設定
      if (textureFineness == null) {
        textureFineness = 0.3; // デフォルト値30%
      }
      if (colorUniformity == null) {
        colorUniformity = 0.5; // デフォルト値50%
      }

      // ⚠️ 重要な修正: RangeErrorが発生してもAI診断結果があれば、それを保存した結果を返す
      if (aiClassificationResult != null) {
        try {
          // AI診断結果があれば、最小限の結果を返す（計算済みのtextureFinenessとcolorUniformityを含む）
          return SkinAnalysisResult(
            skinType: '混合肌',
            oiliness: 0.5,
            smoothness: 0.5,
            uniformity: 0.5,
            poreSize: 0.5,
            brightness: 0.5,
            skinIssues: ['分析中にエラーが発生しました'],
            regionAnalysis: {},
            recommendation: '画像分析中にエラーが発生しましたが、AI診断結果は取得できました。',
            aiClassification: aiClassificationResult, // ⚠️ 重要: AI診断結果を保存
            textureFineness: textureFineness, // ⚠️ 重要: 計算済みの値を保存
            colorUniformity: colorUniformity, // ⚠️ 重要: 計算済みの値を保存
          );
        } catch (e2) {
          return _getDefaultResult(
              aiClassification: aiClassificationResult,
              textureFineness: textureFineness,
              colorUniformity: colorUniformity);
        }
      }
      return _getDefaultResult(
          aiClassification: aiClassificationResult, textureFineness: textureFineness, colorUniformity: colorUniformity);
    }
  }

  /// 顔の領域を抽出
  /// ⚠️ 改善: 学習データに合わせて、顔領域を少し拡張（周囲の背景を含める）
  /// これにより、学習時と推論時の入力がより一致する
  static img.Image _extractFaceRegion(img.Image image, Face face) {
    final boundingBox = face.boundingBox;

    // 顔の境界ボックスを画像座標に変換
    final faceWidth = boundingBox.width;
    final faceHeight = boundingBox.height;

    // ⚠️ 改善: 顔領域を拡張（学習データが顔周辺を含む場合があるため）
    // より大きめに拡張して、学習データの形式に近づける
    final expandRatio = 0.18; // 上下左右に18%拡張（より学習データに近い形式）
    final expandX = faceWidth * expandRatio;
    final expandY = faceHeight * expandRatio;

    final left = math.max(0, (boundingBox.left - expandX).toInt());
    final top = math.max(0, (boundingBox.top - expandY).toInt());
    final right = math.min(image.width, (boundingBox.right + expandX).toInt());
    final bottom = math.min(image.height, (boundingBox.bottom + expandY).toInt());

    // 顔の領域を切り出し
    return img.copyCrop(image, x: left, y: top, width: right - left, height: bottom - top);
  }

  /// 顔領域から肌の部分のみを抽出（髪や背景を除外）
  /// 顔の輪郭（contours）を使用して肌領域を正確に抽出
  static img.Image _extractSkinOnlyRegion(img.Image faceRegion, Face face) {
    try {
      // 顔の輪郭が利用可能な場合、それを活用
      final faceContour = face.contours[FaceContourType.face];

      if (faceContour != null && faceContour.points.isNotEmpty) {
        // 顔の輪郭を使用して肌領域を抽出
        // 輪郭内の領域のみをマスクとして使用
        final w = faceRegion.width;
        final h = faceRegion.height;
        final boundingBox = face.boundingBox;

        // 輪郭点を顔領域のローカル座標に変換
        final localContourPoints = faceContour.points.map((p) {
          final localX = (p.x - boundingBox.left).clamp(0.0, w.toDouble()).toInt();
          final localY = (p.y - boundingBox.top).clamp(0.0, h.toDouble()).toInt();
          return img.Point(localX, localY);
        }).toList();

        // 目や口のランドマークを取得して除外領域を定義
        final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
        final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
        final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]?.position;
        final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]?.position;
        final bottomMouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position;

        // ランドマークをローカル座標に変換
        final eyeExclusionRadius = (w * 0.08).clamp(10.0, 30.0); // 目の除外半径（顔幅の8%）
        final mouthExclusionRadius = (w * 0.12).clamp(15.0, 40.0); // 口の除外半径（顔幅の12%）

        final leftEyeLocal = leftEye != null
            ? img.Point(
                ((leftEye.x - boundingBox.left).clamp(0.0, w.toDouble())).toInt(),
                ((leftEye.y - boundingBox.top).clamp(0.0, h.toDouble())).toInt(),
              )
            : null;
        final rightEyeLocal = rightEye != null
            ? img.Point(
                ((rightEye.x - boundingBox.left).clamp(0.0, w.toDouble())).toInt(),
                ((rightEye.y - boundingBox.top).clamp(0.0, h.toDouble())).toInt(),
              )
            : null;

        // 口の中心を計算（leftMouthとrightMouthから、またはbottomMouthを使用）
        img.Point? mouthLocal;
        if (bottomMouth != null) {
          mouthLocal = img.Point(
            ((bottomMouth.x - boundingBox.left).clamp(0.0, w.toDouble())).toInt(),
            ((bottomMouth.y - boundingBox.top).clamp(0.0, h.toDouble())).toInt(),
          );
        } else if (leftMouth != null && rightMouth != null) {
          // leftMouthとrightMouthから中心を計算
          final mouthCenterX = ((leftMouth.x + rightMouth.x) / 2 - boundingBox.left).clamp(0.0, w.toDouble());
          final mouthCenterY = ((leftMouth.y + rightMouth.y) / 2 - boundingBox.top).clamp(0.0, h.toDouble());
          mouthLocal = img.Point(mouthCenterX.toInt(), mouthCenterY.toInt());
        }

        // 輪郭内の領域をマスクとして作成
        // ⚠️ 改善: より正確なポリゴン内判定アルゴリズムを使用 + 目や口のランドマークを除外
        final mask = List.generate(w * h, (index) {
          final x = index % w;
          final y = index ~/ w;

          // 目や口のランドマークを除外
          if (leftEyeLocal != null) {
            final distToLeftEye = math.sqrt(math.pow(x - leftEyeLocal.x, 2) + math.pow(y - leftEyeLocal.y, 2));
            if (distToLeftEye < eyeExclusionRadius) {
              return false; // 左目の領域を除外
            }
          }
          if (rightEyeLocal != null) {
            final distToRightEye = math.sqrt(math.pow(x - rightEyeLocal.x, 2) + math.pow(y - rightEyeLocal.y, 2));
            if (distToRightEye < eyeExclusionRadius) {
              return false; // 右目の領域を除外
            }
          }
          if (mouthLocal != null) {
            final distToMouth = math.sqrt(math.pow(x - mouthLocal.x, 2) + math.pow(y - mouthLocal.y, 2));
            if (distToMouth < mouthExclusionRadius) {
              return false; // 口の領域を除外
            }
          }

          // ポリゴン内判定（Ray Casting Algorithm）
          // 輪郭点からポリゴンを作成し、点がポリゴン内にあるか判定
          if (localContourPoints.length >= 3) {
            bool inside = false;
            int j = localContourPoints.length - 1;
            for (int i = 0; i < localContourPoints.length; i++) {
              final pi = localContourPoints[i];
              final pj = localContourPoints[j];

              // 線分と交差するか判定（Ray Casting）
              if (((pi.y > y) != (pj.y > y)) && (x < (pj.x - pi.x) * (y - pi.y) / (pj.y - pi.y) + pi.x)) {
                inside = !inside;
              }
              j = i;
            }

            // ポリゴン内判定の結果を返す（輪郭内 = 肌領域）
            return inside;
          } else {
            // 輪郭点が不足している場合は楕円形マスクにフォールバック
            final cx = w / 2.0;
            final cy = h / 2.0;
            final dx = (x - cx) / (w / 2.0);
            final dy = (y - cy) / (h / 2.0);
            final inside = (dx * dx + dy * dy) <= 0.85; // 外側15%を除外
            return inside;
          }
        });

        // マスクを適用して肌領域のみを抽出
        final skinRegion = img.Image(width: w, height: h);
        // 平均色を事前に計算（ループ内で毎回計算しない）
        final avgColor = _calculateAverageSkinColor(faceRegion, mask);

        // マスクのサイズと画像のサイズが一致することを確認
        final expectedMaskSize = w * h;
        if (mask.length != expectedMaskSize) {
          return faceRegion;
        }

        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            final idx = y * w + x;
            // 範囲チェック（二重チェック）
            if (idx < 0 || idx >= mask.length || idx >= expectedMaskSize) continue;
            if (x < 0 || x >= w || y < 0 || y >= h) continue;

            try {
              if (mask[idx]) {
                final pixel = faceRegion.getPixel(x, y);
                skinRegion.setPixel(x, y, pixel);
              } else {
                // 背景部分は平均色で埋める
                skinRegion.setPixel(x, y, img.ColorRgb8(avgColor.r.toInt(), avgColor.g.toInt(), avgColor.b.toInt()));
              }
            } catch (e) {
              // エラー時は平均色で埋める
              try {
                skinRegion.setPixel(x, y, img.ColorRgb8(avgColor.r.toInt(), avgColor.g.toInt(), avgColor.b.toInt()));
              } catch (_) {
                // それでもエラーの場合はスキップ
                continue;
              }
            }
          }
        }

        return skinRegion;
      } else {
        // 輪郭が利用できない場合は、簡易マスクを使用（既存の_skinMask関数を活用）
        final mask = _skinMask(faceRegion);
        final w = faceRegion.width;
        final h = faceRegion.height;
        final avgColor = _calculateAverageSkinColor(faceRegion, mask);

        final skinRegion = img.Image(width: w, height: h);
        // マスクのサイズと画像のサイズが一致することを確認
        final expectedMaskSize = w * h;
        if (mask.length != expectedMaskSize) {
          return faceRegion;
        }

        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            final idx = y * w + x;
            // 範囲チェック（二重チェック）
            if (idx < 0 || idx >= mask.length || idx >= expectedMaskSize) continue;
            if (x < 0 || x >= w || y < 0 || y >= h) continue;

            try {
              if (mask[idx]) {
                final pixel = faceRegion.getPixel(x, y);
                skinRegion.setPixel(x, y, pixel);
              } else {
                skinRegion.setPixel(x, y, img.ColorRgb8(avgColor.r.toInt(), avgColor.g.toInt(), avgColor.b.toInt()));
              }
            } catch (e) {
              // エラー時は平均色で埋める
              try {
                skinRegion.setPixel(x, y, img.ColorRgb8(avgColor.r.toInt(), avgColor.g.toInt(), avgColor.b.toInt()));
              } catch (_) {
                // それでもエラーの場合はスキップ
                continue;
              }
            }
          }
        }

        return skinRegion;
      }
    } catch (e) {
      // エラー時は顔領域全体を使用
      return faceRegion;
    }
  }

  /// 肌領域の平均色を計算（背景埋め込み用）
  static img.ColorRgb8 _calculateAverageSkinColor(img.Image region, List<bool> mask) {
    int rSum = 0, gSum = 0, bSum = 0, count = 0;
    final w = region.width;
    final h = region.height;
    final expectedMaskSize = w * h;

    // ⚠️ 重要な修正: マスクサイズのチェック
    if (mask.length != expectedMaskSize) {
      return img.ColorRgb8(200, 180, 160); // デフォルトの肌色
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;
        // ⚠️ 範囲チェックを追加（RangeError防止）
        if (idx < 0 || idx >= mask.length || idx >= expectedMaskSize) continue;

        try {
          if (mask[idx]) {
            final pixel = region.getPixel(x, y);
            rSum += pixel.r.toInt();
            gSum += pixel.g.toInt();
            bSum += pixel.b.toInt();
            count++;
          }
        } catch (e) {
          // エラー時はスキップ
          continue;
        }
      }
    }

    if (count == 0) {
      return img.ColorRgb8(200, 180, 160); // デフォルトの肌色
    }

    return img.ColorRgb8(
      (rSum / count).toInt().clamp(0, 255),
      (gSum / count).toInt().clamp(0, 255),
      (bSum / count).toInt().clamp(0, 255),
    );
  }

  /// 肌領域の簡易マスク（顔矩形内の内接楕円、周縁の髪/背景を除外）
  /// ⚠️ 改善: より積極的に周縁を除外（髪や背景の影響を最小化）
  static List<bool> _skinMask(img.Image region) {
    final w = region.width, h = region.height;
    final cx = w / 2.0, cy = h / 2.0;
    final rx = w * 0.38, ry = h * 0.45; // より内側寄りに変更（髪や背景をより積極的に除外）
    final mask = List<bool>.filled(w * h, false);
    int idx = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++, idx++) {
        final nx = (x - cx) / rx;
        final ny = (y - cy) / ry;
        final inside = (nx * nx + ny * ny) <= 1.0;
        mask[idx] = inside;
      }
    }
    return mask;
  }

  /// ルマ配列（マスク適用）とパーセンタイル取得
  static List<double> _maskedLuma(img.Image im, List<bool> mask) {
    final bytes = im.getBytes();
    final l = <double>[];
    int idx = 0;
    for (int i = 0; i < bytes.length; i += 4) {
      if (!mask[idx++]) continue;
      final r = bytes[i].toDouble(), g = bytes[i + 1].toDouble(), b = bytes[i + 2].toDouble();
      l.add(0.299 * r + 0.587 * g + 0.114 * b);
    }
    return l;
  }

  static double _percentile(List<double> a, double p) {
    if (a.isEmpty) return 0.0;
    final b = List<double>.from(a)..sort();
    final i = (b.length * p).clamp(0, b.length - 1).toInt();
    return b[i];
  }

  /// 油分レベルを分析
  static double _analyzeOiliness(img.Image faceRegion) {
    // Tゾーン（額と鼻）の光沢を分析
    final width = faceRegion.width;
    final height = faceRegion.height;

    // 額の領域（上部1/3）
    final foreheadRegion = img.copyCrop(faceRegion, x: 0, y: 0, width: width, height: height ~/ 3);

    // 鼻の領域（中央1/3の中央部分）
    final noseRegion = img.copyCrop(faceRegion, x: width ~/ 3, y: height ~/ 3, width: width ~/ 3, height: height ~/ 3);

    // 光沢度を計算（明度の分散）
    final foreheadShine = _calculateShine(foreheadRegion);
    final noseShine = _calculateShine(noseRegion);

    // 油分レベルを0-1の範囲で正規化
    return math.min(1.0, (foreheadShine + noseShine) / 2.0);
  }

  /// 光沢度を計算
  static double _calculateShine(img.Image region) {
    double totalBrightness = 0;
    int pixelCount = 0;

    for (int y = 0; y < region.height; y++) {
      for (int x = 0; x < region.width; x++) {
        final pixel = region.getPixel(x, y);
        final brightness = (pixel.r + pixel.g + pixel.b) / 3.0;
        totalBrightness += brightness;
        pixelCount++;
      }
    }

    final averageBrightness = totalBrightness / pixelCount;

    // 明度の分散を計算（光沢の指標）
    double variance = 0;
    for (int y = 0; y < region.height; y++) {
      for (int x = 0; x < region.width; x++) {
        final pixel = region.getPixel(x, y);
        final brightness = (pixel.r + pixel.g + pixel.b) / 3.0;
        variance += math.pow(brightness - averageBrightness, 2);
      }
    }

    return math.sqrt(variance / pixelCount) / 255.0;
  }

  /// 滑らかさを分析
  static double _analyzeSmoothness(img.Image faceRegion) {
    // エッジ検出を使用して肌の滑らかさを測定
    final edges = img.sobel(faceRegion);

    double totalEdgeStrength = 0;
    int pixelCount = 0;

    for (int y = 0; y < edges.height; y++) {
      for (int x = 0; x < edges.width; x++) {
        final pixel = edges.getPixel(x, y);
        final edgeStrength = (pixel.r + pixel.g + pixel.b) / 3.0;
        totalEdgeStrength += edgeStrength;
        pixelCount++;
      }
    }

    final averageEdgeStrength = totalEdgeStrength / pixelCount;

    // 滑らかさはエッジ強度の逆数（0-1の範囲で正規化）
    return math.max(0.0, 1.0 - (averageEdgeStrength / 255.0));
  }

  /// 均一性を分析
  static double _analyzeUniformity(img.Image faceRegion) {
    // 色の均一性を分析
    final width = faceRegion.width;
    final height = faceRegion.height;

    // 画像をグリッドに分割して各セクションの平均色を計算
    final gridSize = 8;
    final cellWidth = width ~/ gridSize;
    final cellHeight = height ~/ gridSize;

    List<List<double>> cellColors = [];

    for (int row = 0; row < gridSize; row++) {
      List<double> rowColors = [];
      for (int col = 0; col < gridSize; col++) {
        final cell =
            img.copyCrop(faceRegion, x: col * cellWidth, y: row * cellHeight, width: cellWidth, height: cellHeight);

        final averageColor = _calculateAverageColor(cell);
        rowColors.add(averageColor);
      }
      cellColors.add(rowColors);
    }

    // 色の分散を計算
    double totalVariance = 0;
    int comparisons = 0;

    for (int row = 0; row < gridSize; row++) {
      for (int col = 0; col < gridSize; col++) {
        final currentColor = cellColors[row][col];

        // 隣接するセルの色と比較
        if (row > 0) {
          totalVariance += math.pow(currentColor - cellColors[row - 1][col], 2);
          comparisons++;
        }
        if (col > 0) {
          totalVariance += math.pow(currentColor - cellColors[row][col - 1], 2);
          comparisons++;
        }
      }
    }

    final averageVariance = totalVariance / comparisons;

    // 均一性は分散の逆数（0-1の範囲で正規化）
    return math.max(0.0, 1.0 - (averageVariance / 10000.0));
  }

  /// 平均色を計算
  static double _calculateAverageColor(img.Image region) {
    double totalColor = 0;
    int pixelCount = 0;

    for (int y = 0; y < region.height; y++) {
      for (int x = 0; x < region.width; x++) {
        final pixel = region.getPixel(x, y);
        totalColor += (pixel.r + pixel.g + pixel.b) / 3.0;
        pixelCount++;
      }
    }

    return totalColor / pixelCount;
  }

  /// 毛穴サイズを分析
  static double _analyzePoreSize(img.Image faceRegion) {
    // 毛穴検出のためのモルフォロジー演算
    final gray = img.grayscale(faceRegion);
    final blurred = img.gaussianBlur(gray, radius: 2);

    // 局所的な最小値検出（毛穴の候補）
    int poreCount = 0;

    for (int y = 2; y < blurred.height - 2; y++) {
      for (int x = 2; x < blurred.width - 2; x++) {
        final centerPixel = blurred.getPixel(x, y);
        final centerBrightness = centerPixel.r;

        // 周囲のピクセルと比較
        bool isLocalMinimum = true;
        for (int dy = -2; dy <= 2; dy++) {
          for (int dx = -2; dx <= 2; dx++) {
            if (dx == 0 && dy == 0) continue;

            final neighborPixel = blurred.getPixel(x + dx, y + dy);
            if (neighborPixel.r < centerBrightness) {
              isLocalMinimum = false;
              break;
            }
          }
          if (!isLocalMinimum) break;
        }

        if (isLocalMinimum && centerBrightness < 100) {
          poreCount++;
        }
      }
    }

    // 毛穴密度を0-1の範囲で正規化
    final totalPixels = blurred.width * blurred.height;
    return math.min(1.0, (poreCount / totalPixels) * 1000);
  }

  /// 明度を分析
  static double _analyzeBrightness(img.Image faceRegion) {
    final mask = _skinMask(faceRegion);
    final l = _maskedLuma(faceRegion, mask);
    if (l.isEmpty) return 0.6;
    // コントラストストレッチ（p5..p95）
    final p5 = _percentile(l, 0.05);
    final p95 = _percentile(l, 0.95);
    double sum = 0;
    for (final v in l) {
      final n = ((v - p5) / (p95 - p5 + 1e-6)).clamp(0.0, 1.0);
      sum += n;
    }
    return sum / l.length;
  }

  /// 肌の悩みを検出
  static Future<List<String>> _detectSkinIssues(img.Image faceRegion,
      {double? dullnessIndex, double? spotDensity, double? acneActivity}) async {
    List<String> issues = [];

    // シミ検出
    final finalSpotDensity = spotDensity ?? await _estimateSpotDensity(faceRegion);
    if (finalSpotDensity > 0.02 || _detectSpots(faceRegion)) {
      issues.add('シミ・そばかす');
    }

    // ニキビ跡検出
    final finalAcneActivity = acneActivity ?? await _estimateAcneActivity(faceRegion);
    if (finalAcneActivity > 0.15 || _detectAcneScars(faceRegion)) {
      issues.add('ニキビ跡');
    }

    // 毛穴の目立ち
    if (_detectVisiblePores(faceRegion)) {
      issues.add('毛穴の目立ち');
    }

    // くすみ検出
    if ((dullnessIndex ?? _calculateDullness(faceRegion)) > 0.4 || _detectDullness(faceRegion)) {
      issues.add('くすみ');
    }

    return issues;
  }

  /// くすみ指数（0..1 高いほどくすみ）
  static double _calculateDullness(img.Image faceRegion) {
    // マスク内での明度低下 + 黄味 + 低コントラスト（白霞み対策）
    final mask = _skinMask(faceRegion);
    final luma = _maskedLuma(faceRegion, mask);
    if (luma.isEmpty) return 0.0;
    double sumL = 0, sumR = 0, sumG = 0, sumB = 0;
    int idx = 0;
    final bytes = faceRegion.getBytes();
    for (int i = 0; i < bytes.length; i += 4) {
      if (!mask[idx++]) continue;
      final r = bytes[i].toDouble(), g = bytes[i + 1].toDouble(), b = bytes[i + 2].toDouble();
      sumR += r;
      sumG += g;
      sumB += b;
      sumL += 0.299 * r + 0.587 * g + 0.114 * b;
    }
    final n = luma.length;
    final avgL = (sumL / n) / 255.0;
    final avgR = sumR / n, avgG = sumG / n, avgB = sumB / n;
    final yellowish = (((avgR + avgG) / 2.0) - avgB) / 255.0;
    double varianceSum = 0;
    final mean = sumL / n;
    for (final v in luma) {
      varianceSum += (v - mean) * (v - mean);
    }
    final std = math.sqrt(varianceSum / n);
    final contrast = (std / 64.0).clamp(0.0, 1.0);
    final dullY = (1.0 - avgL).clamp(0.0, 1.0);
    final yellow = yellowish.clamp(0.0, 1.0);
    final lowContrast = (1.0 - contrast).clamp(0.0, 1.0);
    return (0.5 * dullY + 0.3 * yellow + 0.2 * lowContrast).clamp(0.0, 1.0);
  }

  /// 高度指標の算出（目輝き/くま/眉バランス/鼻ツヤ/顎むくみ）
  static Map<String, double> _advancedMetrics(img.Image image, Face face) {
    final bbox = face.boundingBox.inflate(6);
    int x0 = bbox.left.clamp(0, image.width - 1).toInt();
    int y0 = bbox.top.clamp(0, image.height - 1).toInt();
    int w = (bbox.width).clamp(1, image.width - x0).toInt();
    int h = (bbox.height).clamp(1, image.height - y0).toInt();
    final crop = img.copyCrop(image, x: x0, y: y0, width: w, height: h);

    double sampleBoxAvg(img.Image im, int cx, int cy, int rw, int rh) {
      final r = img.copyCrop(im,
          x: (cx - rw ~/ 2).clamp(0, im.width - 1),
          y: (cy - rh ~/ 2).clamp(0, im.height - 1),
          width: rw.clamp(1, im.width),
          height: rh.clamp(1, im.height));
      double sum = 0;
      int n = 0;
      final bytes = r.getBytes();
      for (int i = 0; i < bytes.length; i += 4) {
        final r0 = bytes[i], g0 = bytes[i + 1], b0 = bytes[i + 2];
        sum += 0.299 * r0 + 0.587 * g0 + 0.114 * b0;
        n++;
      }
      return (sum / (n == 0 ? 1 : n)) / 255.0;
    }

    double highlightRatio(img.Image im, int cx, int cy, int rw, int rh, {int thr = 225}) {
      final r = img.copyCrop(im,
          x: (cx - rw ~/ 2).clamp(0, im.width - 1),
          y: (cy - rh ~/ 2).clamp(0, im.height - 1),
          width: rw.clamp(1, im.width),
          height: rh.clamp(1, im.height));
      int n = 0, hi = 0;
      final bytes = r.getBytes();
      for (int i = 0; i < bytes.length; i += 4) {
        final r0 = bytes[i], g0 = bytes[i + 1], b0 = bytes[i + 2];
        final l = 0.299 * r0 + 0.587 * g0 + 0.114 * b0;
        if (l >= thr) hi++;
        n++;
      }
      return (hi / (n == 0 ? 1 : n)).clamp(0.0, 1.0);
    }

    // 目の中心近くとその下帯域をサンプリング
    final leftEyePts = face.contours[FaceContourType.leftEye]?.points ?? [];
    final rightEyePts = face.contours[FaceContourType.rightEye]?.points ?? [];
    int lcx = leftEyePts.isNotEmpty ? leftEyePts.map((p) => p.x).reduce((a, b) => a + b) ~/ leftEyePts.length : w ~/ 3;
    int lcy = leftEyePts.isNotEmpty ? leftEyePts.map((p) => p.y).reduce((a, b) => a + b) ~/ leftEyePts.length : h ~/ 3;
    int rcx =
        rightEyePts.isNotEmpty ? rightEyePts.map((p) => p.x).reduce((a, b) => a + b) ~/ rightEyePts.length : 2 * w ~/ 3;
    int rcy =
        rightEyePts.isNotEmpty ? rightEyePts.map((p) => p.y).reduce((a, b) => a + b) ~/ rightEyePts.length : h ~/ 3;
    // 座標をcrop基準に補正
    lcx -= x0;
    lcy -= y0;
    rcx -= x0;
    rcy -= y0;
    lcx = lcx.clamp(0, crop.width - 1);
    lcy = lcy.clamp(0, crop.height - 1);
    rcx = rcx.clamp(0, crop.width - 1);
    rcy = rcy.clamp(0, crop.height - 1);
    final eyeB =
        ((sampleBoxAvg(crop, lcx, lcy, w ~/ 10, h ~/ 12) + sampleBoxAvg(crop, rcx, rcy, w ~/ 10, h ~/ 12)) / 2.0)
            .clamp(0.0, 1.0);
    final underB = ((sampleBoxAvg(crop, lcx, lcy + h ~/ 14, w ~/ 10, h ~/ 18) +
                sampleBoxAvg(crop, rcx, rcy + h ~/ 14, w ~/ 10, h ~/ 18)) /
            2.0)
        .clamp(0.0, 1.0);
    final darkCircle = (eyeB - underB).clamp(0.0, 1.0); // 差が大きいほどくまが薄い → 反転
    final darkCircleIdx = (1.0 - darkCircle).clamp(0.0, 1.0);

    // 眉バランス: 眉中心の高さ差
    final lb = face.contours[FaceContourType.leftEyebrowTop]?.points ?? [];
    final rb = face.contours[FaceContourType.rightEyebrowTop]?.points ?? [];
    final lby = lb.isNotEmpty ? lb.map((p) => p.y).reduce((a, b) => a + b) / lb.length : lcy - h * 0.08;
    final rby = rb.isNotEmpty ? rb.map((p) => p.y).reduce((a, b) => a + b) / rb.length : rcy - h * 0.08;
    final diff = ((lby - rby).abs()) / (h + 1e-6);
    final browBalance = (1.0 - diff * 3.0).clamp(0.0, 1.0);

    // 鼻ツヤ: 鼻底/鼻先付近のハイライト率
    final nose = face.landmarks[FaceLandmarkType.noseBase];
    int nx = nose?.position.x.toInt() ?? (x0 + w ~/ 2);
    int ny = nose?.position.y.toInt() ?? (y0 + 2 * h ~/ 3);
    nx -= x0;
    ny -= y0;
    nx = nx.clamp(0, crop.width - 1);
    ny = ny.clamp(0, crop.height - 1);
    final noseGloss = highlightRatio(crop, nx, ny, w ~/ 10, h ~/ 12).clamp(0.0, 1.0);

    // 顎むくみ: 下顎帯域の平均明度差と輪郭幅比の合成（簡易）
    final facePts = face.contours[FaceContourType.face]?.points ?? [];
    double widthLower = 0;
    if (facePts.length > 3) {
      final left = facePts.first;
      final right = facePts.last;
      widthLower = (right.x - left.x).toDouble();
    } else {
      widthLower = w.toDouble() * 0.8;
    }
    final lowerBand = sampleBoxAvg(crop, w ~/ 2, (h * 0.85).toInt(), w ~/ 2, h ~/ 10);
    final midBand = sampleBoxAvg(crop, w ~/ 2, (h * 0.65).toInt(), w ~/ 2, h ~/ 10);
    final luminanceDiff = (midBand - lowerBand).abs();
    final widthRatio = (widthLower / (w + 1e-6)).clamp(0.0, 1.0);
    final jawPuffiness = (0.6 * widthRatio + 0.4 * (1.0 - luminanceDiff)).clamp(0.0, 1.0);

    return {
      'eyeBrightness': eyeB,
      'darkCircle': darkCircleIdx,
      'browBalance': browBalance,
      'noseGloss': noseGloss,
      'jawPuffiness': jawPuffiness,
    };
  }

  /// シミ面積比の推定（0..1）
  static Future<double> _estimateSpotDensity(img.Image faceRegion) async {
    // マスク内でのDoG + 適応しきい値（p60）で暗斑比率を推定
    final mask = _skinMask(faceRegion);
    final gray = img.grayscale(faceRegion);
    final blur1 = img.gaussianBlur(gray, radius: 1);
    final blur2 = img.gaussianBlur(gray, radius: 3);
    final vals = <int>[];
    int idx = 0;
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++, idx++) {
        if (!mask[idx]) continue;
        final a = blur1.getPixel(x, y).r;
        final b = blur2.getPixel(x, y).r;
        final dog = (a - b);
        vals.add(dog.toInt());
      }
    }
    vals.sort();
    // 負側分布の60パーセンタイルをしきい値に（環境に追従）
    final pIdx = (vals.length * 0.4).toInt().clamp(0, vals.length - 1);
    final thr = vals[pIdx];
    int dark = 0;
    for (final v in vals) {
      if (v <= thr) dark++;
    }
    final ratio = (dark / (vals.isEmpty ? 1 : vals.length)).clamp(0.0, 1.0);
    // 軽量セグメント化スタブで補正（U-Net/YOLO代替の接続口）
    final seg = await _segmentBlemishRatio(faceRegion);
    return (0.7 * ratio + 0.3 * seg).clamp(0.0, 1.0);
  }

  /// ニキビ活動度の推定（0..1）
  static Future<double> _estimateAcneActivity(img.Image faceRegion) async {
    // 赤み（適応しきい値）+ 粒状テクスチャ + ツヤ低下
    final mask = _skinMask(faceRegion);
    final bytes = faceRegion.getBytes();
    final reds = <double>[];
    int idx = 0;
    for (int i = 0; i < bytes.length; i += 4) {
      if (!mask[idx++]) continue;
      final r = bytes[i].toDouble(), g = bytes[i + 1].toDouble(), b = bytes[i + 2].toDouble();
      reds.add((r - (g + b) * 0.5));
    }
    reds.sort();
    final rThr = reds[(reds.length * 0.8).toInt().clamp(0, reds.length - 1)];
    int redCount = 0;
    double redSum = 0;
    for (final v in reds) {
      if (v >= rThr) {
        redCount++;
        redSum += v;
      }
    }
    final redScore = ((redSum / (redCount == 0 ? 1 : redCount)) / 255.0).clamp(0.0, 1.0);

    final gray = img.grayscale(faceRegion);
    final blur = img.gaussianBlur(gray, radius: 1);
    double tex = 0;
    int pix = 0;
    for (int y = 1; y < gray.height - 1; y++) {
      for (int x = 1; x < gray.width - 1; x++) {
        final v = gray.getPixel(x, y).r.toDouble();
        final vb = blur.getPixel(x, y).r.toDouble();
        final m = mask[y * gray.width + x];
        if (!m) continue;
        tex += (v - vb).abs();
        pix++;
      }
    }
    final texScore = (tex / (pix == 0 ? 1 : pix)) / 48.0; // より敏感に
    final glossLoss = (1.0 - _analyzeBrightness(faceRegion)).clamp(0.0, 1.0);
    // セグメント化スタブ（赤み領域）で補助
    final seg = await _segmentBlemishRatio(faceRegion);
    final score = (0.40 * redScore + 0.30 * texScore + 0.20 * glossLoss + 0.10 * seg).clamp(0.0, 1.0);
    return score;
  }

  /// しわ密度の推定（0..1）
  static double _estimateWrinkleDensity(img.Image faceRegion) {
    try {
      // マスク内でSobel強度の上位パーセンタイルで密度化（照明に頑健）
      final mask = _skinMask(faceRegion);
      final gray = img.grayscale(faceRegion);
      final edges = img.sobel(gray);

      // マスクとエッジ画像のサイズが一致することを確認
      final expectedMaskSize = edges.width * edges.height;
      if (mask.length != expectedMaskSize) {
        print('[SkinAnalyzer] ⚠️ しわ分析: マスクサイズが一致しません。mask.length=${mask.length}, expected=$expectedMaskSize');
        return 0.2; // デフォルト値
      }

      final vals = <int>[];
      int idx = 0;
      for (int y = 0; y < edges.height; y++) {
        for (int x = 0; x < edges.width; x++, idx++) {
          // インデックスの範囲チェック
          if (idx < 0 || idx >= mask.length) continue;
          if (!mask[idx]) continue;
          try {
            vals.add(edges.getPixel(x, y).r.toInt());
          } catch (e) {
            // ピクセル取得エラーは無視
            continue;
          }
        }
      }

      if (vals.isEmpty) {
        print('[SkinAnalyzer] ⚠️ しわ分析: エッジ値が空です');
        return 0.2; // デフォルト値（50%ではなく低めの値）
      }

      vals.sort();

      // より敏感に反応するように閾値を調整（85パーセンタイル→75パーセンタイル）
      final percentileIndex = (vals.length * 0.75).toInt().clamp(0, vals.length - 1);
      final thr = vals[percentileIndex];

      // 強いエッジをカウント
      int strong = 0;
      for (final v in vals) {
        if (v >= thr) strong++;
      }

      // エッジの強度分布を分析
      final avgEdge = vals.reduce((a, b) => a + b) / vals.length;
      final maxEdge = vals.last;
      final edgeIntensity = (avgEdge / 255.0).clamp(0.0, 1.0);
      final strongRatio = (strong / vals.length).clamp(0.0, 1.0);

      // 複数の指標を組み合わせてしわ密度を計算
      // エッジ強度と強いエッジの割合を組み合わせ
      final wrinkleScore = (edgeIntensity * 0.5 + strongRatio * 0.5).clamp(0.0, 1.0);

      // より敏感に反応するように拡大（0.0-1.0を0.0-1.0に拡大）
      final expandedScore = (wrinkleScore * 1.5).clamp(0.0, 1.0);

      print(
          '[SkinAnalyzer] しわ分析詳細: vals.length=${vals.length}, thr=$thr, strong=$strong, strongRatio=$strongRatio, avgEdge=$avgEdge, maxEdge=$maxEdge, edgeIntensity=$edgeIntensity, wrinkleScore=$wrinkleScore, expandedScore=$expandedScore');
      return expandedScore;
    } catch (e, stackTrace) {
      print('[SkinAnalyzer] ❌ しわ分析エラー: $e');
      print('[SkinAnalyzer] スタックトレース: ${stackTrace.toString().split("\n").take(5).join("\n")}');
      return 0.2; // デフォルト値（50%ではなく低めの値）
    }
  }

  // 値のキャリブレーション（0..1の範囲を上下限とガンマで整形）
  static double _calibrate(double v, {double cap = 0.85, double floor = 0.02, double gamma = 1.0}) {
    final x = v.clamp(0.0, 1.0);
    final y = math.pow(x, gamma).toDouble();
    return y.clamp(floor, cap);
  }

  /// 軽量セグメント化スタブ：赤み/暗斑に反応する2段しきい値+モルフォロジで近似
  /// セグメンテーションベースのニキビ/シミ検出
  /// AIモデル（BlemishSegmentation）が利用可能な場合はそちらを使用、そうでなければ従来の画像処理を使用
  static Future<double> _segmentBlemishRatio(img.Image faceRegion) async {
    // AIセグメンテーションモデルが利用可能な場合は試行
    try {
      final seg = BlemishSegmentation('${AppAiConfig.modelsDir}blemish.tflite');
      final aiResult = await seg.inferMaskRatio(faceRegion);
      if (aiResult != null) {
        return aiResult;
      }
    } catch (_) {
      // AIモデルが利用できない場合はフォールバック
    }

    // フォールバック: 従来の画像処理ベースの検出
    final w = faceRegion.width, h = faceRegion.height;
    int count = 0, mark = 0;
    // ぼかし
    final blur = img.gaussianBlur(faceRegion, radius: 1);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = blur.getPixel(x, y);
        final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
        final l = 0.299 * r + 0.587 * g + 0.114 * b;
        final redEx = r - (g + b) * 0.5; // 赤み
        final dark = 180 - l; // 暗さ
        // 2段しきい値
        if (redEx > 35 || dark > 30) mark++;
        count++;
      }
    }
    // 粗いモルフォ相当の平滑化（比率で代替）
    final ratio = (mark / (count == 0 ? 1 : count)).clamp(0.0, 1.0);
    return ratio;
  }

  /// シミ検出
  /// 【C】ゼロ除算を修正
  static bool _detectSpots(img.Image faceRegion) {
    // 局所的な色の変化を検出
    final gray = img.grayscale(faceRegion);
    final edges = img.sobel(gray);

    double edgeDensity = 0;
    int edgeCount = 0;

    for (int y = 0; y < edges.height; y++) {
      for (int x = 0; x < edges.width; x++) {
        final pixel = edges.getPixel(x, y);
        if (pixel.r > 50) {
          edgeCount++;
          edgeDensity += pixel.r;
        }
      }
    }

    // 【C】ゼロ除算を修正: edgeCount==0の場合はfalseを返す
    if (edgeCount == 0) {
      return false;
    }

    // エッジ密度が閾値を超える場合、シミがあると判定
    return (edgeDensity / edgeCount) > 80;
  }

  /// ニキビ跡検出
  static bool _detectAcneScars(img.Image faceRegion) {
    // 小さな凹みや凸凹を検出
    final gray = img.grayscale(faceRegion);
    final blurred = img.gaussianBlur(gray, radius: 3);

    double textureVariation = 0;
    int comparisons = 0;

    for (int y = 3; y < blurred.height - 3; y++) {
      for (int x = 3; x < blurred.width - 3; x++) {
        final centerPixel = blurred.getPixel(x, y);
        final centerBrightness = centerPixel.r;

        for (int dy = -3; dy <= 3; dy++) {
          for (int dx = -3; dx <= 3; dx++) {
            if (dx == 0 && dy == 0) continue;

            final neighborPixel = blurred.getPixel(x + dx, y + dy);
            textureVariation += (centerBrightness - neighborPixel.r).abs();
            comparisons++;
          }
        }
      }
    }

    return (textureVariation / comparisons) > 20;
  }

  /// 毛穴の目立ち検出
  static bool _detectVisiblePores(img.Image faceRegion) {
    // 小さな円形の暗い領域を検出
    final gray = img.grayscale(faceRegion);

    int darkSpotCount = 0;

    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        final pixel = gray.getPixel(x, y);
        if (pixel.r < 50) {
          darkSpotCount++;
        }
      }
    }

    final totalPixels = gray.width * gray.height;
    return (darkSpotCount / totalPixels) > 0.01; // 1%以上
  }

  /// くすみ検出
  static bool _detectDullness(img.Image faceRegion) {
    final brightness = _analyzeBrightness(faceRegion);
    return brightness < 0.6; // 明度が60%未満
  }

  /// 顔の各領域を分析
  static Map<String, double> _analyzeRegions(img.Image faceRegion, Face face) {
    final width = faceRegion.width;
    final height = faceRegion.height;

    return {
      '額': _analyzeOiliness(img.copyCrop(faceRegion, x: 0, y: 0, width: width, height: height ~/ 3)),
      '頬': _analyzeOiliness(img.copyCrop(faceRegion, x: 0, y: height ~/ 3, width: width, height: height ~/ 3)),
      '鼻': _analyzeOiliness(
          img.copyCrop(faceRegion, x: width ~/ 3, y: height ~/ 3, width: width ~/ 3, height: height ~/ 3)),
      '顎': _analyzeOiliness(img.copyCrop(faceRegion, x: 0, y: 2 * height ~/ 3, width: width, height: height ~/ 3)),
    };
  }

  /// 肌タイプを判定
  static String _determineSkinType(double oiliness, double smoothness, double uniformity) {
    if (oiliness > 0.7) {
      return '脂性肌';
    } else if (oiliness < 0.3) {
      return '乾性肌';
    } else if (uniformity > 0.8 && smoothness > 0.8) {
      return '普通肌';
    } else {
      return '混合肌';
    }
  }

  /// 推奨ケアを生成
  static String _generateRecommendation(String skinType, List<String> issues, double oiliness) {
    List<String> recommendations = [];

    switch (skinType) {
      case '脂性肌':
        recommendations.add('オイルフリーの洗顔料を使用');
        recommendations.add('皮脂をコントロールする化粧水');
        break;
      case '乾性肌':
        recommendations.add('保湿力の高いクリーム');
        recommendations.add('セラミド配合のスキンケア');
        break;
      case '混合肌':
        recommendations.add('Tゾーンはオイルフリー、頬は保湿重視');
        recommendations.add('部位別ケアを実践');
        break;
      default:
        recommendations.add('バランスの良いスキンケア');
    }

    if (issues.contains('シミ・そばかす')) {
      recommendations.add('ビタミンC配合の美容液');
      recommendations.add('日焼け止めの使用');
    }

    if (issues.contains('毛穴の目立ち')) {
      recommendations.add('毛穴を引き締める化粧水');
      recommendations.add('定期的な角質ケア');
    }

    return recommendations.join('、');
  }

  /// デフォルト結果を返す
  /// [aiClassification]を指定した場合、AI診断結果を含める
  static SkinAnalysisResult _getDefaultResult(
      {Map<String, double>? aiClassification, double? textureFineness, double? colorUniformity}) {
    return SkinAnalysisResult(
      skinType: '普通肌',
      oiliness: 0.5,
      smoothness: 0.7,
      uniformity: 0.8,
      poreSize: 0.3,
      brightness: 0.7,
      skinIssues: ['分析エラー'],
      regionAnalysis: {'額': 0.5, '頬': 0.5, '鼻': 0.5, '顎': 0.5},
      recommendation: '基本的なスキンケアを継続してください',
      aiClassification: aiClassification, // AI診断結果があれば保存
      textureFineness: textureFineness,
      colorUniformity: colorUniformity,
    );
  }
}
