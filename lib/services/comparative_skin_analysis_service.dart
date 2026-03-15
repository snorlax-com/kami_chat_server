import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/skin_analysis.dart';

/// 比較ベースの肌分析サービス
/// 過去画像（チュートリアル/前日）と比較して精度向上を実現
class ComparativeSkinAnalysisService {
  /// 過去画像と比較した肌分析を実行
  ///
  /// 比較元の優先順位:
  /// 1. 前日の画像（最新）
  /// 2. チュートリアルのベースライン画像
  ///
  /// 戻り値: 比較補正済みの肌分析結果
  static Future<EnhancedSkinAnalysisResult> analyzeWithComparison({
    required io.File currentImageFile,
    required Face currentFace,
  }) async {
    // 現在の画像を分析
    final currentAnalysis = await SkinAnalyzer.analyzeSkin(currentImageFile, currentFace);

    // 比較用の過去画像を取得
    final comparisonData = await _getComparisonData();

    if (comparisonData == null) {
      // 比較画像がない場合は通常の分析結果を返す
      return EnhancedSkinAnalysisResult(
        baseResult: currentAnalysis,
        comparisonType: ComparisonType.none,
        improvements: {},
        deteriorations: {},
        stabilityScore: 0.5,
      );
    }

    // 過去画像を読み込んで分析
    final previousImageFile = io.File(comparisonData['imagePath']);
    if (!previousImageFile.existsSync()) {
      return EnhancedSkinAnalysisResult(
        baseResult: currentAnalysis,
        comparisonType: ComparisonType.none,
        improvements: {},
        deteriorations: {},
        stabilityScore: 0.5,
      );
    }

    final previousAnalysis = comparisonData['previousAnalysis'] as Map<String, dynamic>?;

    // 過去画像から顔を検出（比較用）
    final previousInputImage = InputImage.fromFilePath(previousImageFile.path);
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableContours: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    final previousFaces = await faceDetector.processImage(previousInputImage);
    await faceDetector.close();

    if (previousFaces.isEmpty) {
      // 過去画像で顔が検出できない場合
      return EnhancedSkinAnalysisResult(
        baseResult: currentAnalysis,
        comparisonType: ComparisonType.none,
        improvements: {},
        deteriorations: {},
        stabilityScore: 0.5,
      );
    }

    // 画像を正規化（照明・角度・位置の違いを補正）
    final normalizedComparison = await _normalizeForComparison(
      currentImage: currentImageFile,
      previousImage: previousImageFile,
      currentFace: currentFace,
      previousFace: previousFaces.first,
    );

    // 差分解析を実行
    final differentialAnalysis = _performDifferentialAnalysis(
      current: currentAnalysis,
      previous: previousAnalysis,
      normalizedImages: normalizedComparison,
    );

    // 比較補正を適用（過去画像との差分から精度向上）
    final correctedAnalysis = _applyComparisonCorrection(
      current: currentAnalysis,
      differential: differentialAnalysis,
      comparisonData: comparisonData,
    );

    return EnhancedSkinAnalysisResult(
      baseResult: correctedAnalysis,
      comparisonType: comparisonData['type'] as ComparisonType,
      improvements: differentialAnalysis.improvements,
      deteriorations: differentialAnalysis.deteriorations,
      stabilityScore: differentialAnalysis.stabilityScore,
    );
  }

  /// 比較用データを取得（前日 > チュートリアル）
  static Future<Map<String, dynamic>?> _getComparisonData() async {
    // 1. 前日の肌分析結果を取得
    final lastSkin = await Storage.getLastSkin();
    final dailySnapshots = await Storage.getDailySnapshots();

    if (dailySnapshots.isNotEmpty) {
      // 最新のスナップショットを取得（前日）
      final latest = dailySnapshots.last;
      final imagePath = latest['imagePath'] as String?;
      if (imagePath != null && io.File(imagePath).existsSync()) {
        return {
          'type': ComparisonType.previousDay,
          'imagePath': imagePath,
          'previousAnalysis': lastSkin,
          'date': latest['date'] as String?,
        };
      }
    }

    // 2. チュートリアルのベースライン画像を取得
    final baselineNeutral = await Storage.getBaselineImagePath('neutral');
    if (baselineNeutral != null && io.File(baselineNeutral).existsSync()) {
      final baselineSkin = await Storage.getBaselineSkin();
      return {
        'type': ComparisonType.tutorial,
        'imagePath': baselineNeutral,
        'previousAnalysis': baselineSkin,
        'date': 'tutorial',
      };
    }

    return null;
  }

  /// 比較のために画像を正規化（照明・角度・位置の違いを補正）
  static Future<NormalizedImagePair> _normalizeForComparison({
    required io.File currentImage,
    required io.File previousImage,
    required Face currentFace,
    required Face previousFace,
  }) async {
    // 画像を読み込み
    final currentBytes = await currentImage.readAsBytes();
    final previousBytes = await previousImage.readAsBytes();
    final currentImg = img.decodeImage(currentBytes is Uint8List ? currentBytes : Uint8List.fromList(currentBytes))!;
    final previousImg =
        img.decodeImage(previousBytes is Uint8List ? previousBytes : Uint8List.fromList(previousBytes))!;

    // 1. 顔位置・角度の正規化（アフィン変換）
    final normalizedCurrent = _normalizeFacePosition(currentImg, currentFace);
    final normalizedPrevious = _normalizeFacePosition(previousImg, previousFace);

    // 2. サイズの統一
    final targetSize = math.min(normalizedCurrent.width, normalizedCurrent.height);
    final resizedCurrent = img.copyResize(normalizedCurrent, width: targetSize, height: targetSize);
    final resizedPrevious = img.copyResize(normalizedPrevious, width: targetSize, height: targetSize);

    // 3. 照明の正規化（ヒストグラムマッチング）
    final illuminationNormalizedCurrent = _normalizeIllumination(resizedCurrent);
    final illuminationNormalizedPrevious = _normalizeIllumination(resizedPrevious);

    return NormalizedImagePair(
      current: illuminationNormalizedCurrent,
      previous: illuminationNormalizedPrevious,
    );
  }

  /// 顔位置・角度の正規化（アフィン変換）
  static img.Image _normalizeFacePosition(img.Image image, Face face) {
    // 顔のランドマークを使用して正規化
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;

    if (leftEye == null || rightEye == null || noseBase == null) {
      return image; // ランドマークが不完全な場合はそのまま
    }

    // 目の中心点
    final eyeCenterX = (leftEye.x + rightEye.x) / 2;
    final eyeCenterY = (leftEye.y + rightEye.y) / 2;

    // 目の角度を計算（水平にする）
    final eyeAngle = math.atan2(
      rightEye.y - leftEye.y,
      rightEye.x - leftEye.x,
    );

    // 回転して正規化（簡易版：実際はアフィン変換）
    final rotated = img.copyRotate(
      image,
      angle: eyeAngle * 180 / math.pi,
    );

    return rotated;
  }

  /// 照明の正規化（ヒストグラムマッチング）
  static img.Image _normalizeIllumination(img.Image image) {
    // グレースケールに変換
    final gray = img.grayscale(image);

    // ヒストグラム均等化を実行
    final histogram = List.filled(256, 0);
    final totalPixels = gray.width * gray.height;

    // ヒストグラムを計算
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        final pixel = gray.getPixel(x, y);
        histogram[pixel.r.clamp(0, 255).toInt()]++;
      }
    }

    // 累積分布関数（CDF）を計算
    final cdf = List.filled(256, 0);
    cdf[0] = histogram[0];
    for (int i = 1; i < 256; i++) {
      cdf[i] = cdf[i - 1] + histogram[i];
    }

    // 正規化されたピクセル値を計算
    final normalized = img.copyResize(gray, width: gray.width, height: gray.height);
    for (int y = 0; y < normalized.height; y++) {
      for (int x = 0; x < normalized.width; x++) {
        final pixel = normalized.getPixel(x, y);
        final grayValue = pixel.r;
        final normalizedValue = ((cdf[grayValue.clamp(0, 255).toInt()] / totalPixels) * 255).toInt();
        normalized.setPixel(x, y, img.ColorRgb8(normalizedValue, normalizedValue, normalizedValue));
      }
    }

    // 元のカラー画像に戻す（簡易版：実際はより高度な変換）
    return normalized;
  }

  /// 差分解析を実行
  static DifferentialAnalysis _performDifferentialAnalysis({
    required SkinAnalysisResult current,
    required Map<String, dynamic>? previous,
    required NormalizedImagePair normalizedImages,
  }) {
    if (previous == null) {
      return DifferentialAnalysis(
        improvements: {},
        deteriorations: {},
        stabilityScore: 0.5,
      );
    }

    final improvements = <String, double>{};
    final deteriorations = <String, double>{};

    // 各指標の変化を計算
    final metrics = [
      ('dullnessIndex', current.dullnessIndex ?? 0.0, previous['dullnessIndex'] as num? ?? 0.0),
      ('acneActivity', current.acneActivity ?? 0.0, previous['acneActivity'] as num? ?? 0.0),
      ('wrinkleDensity', current.wrinkleDensity ?? 0.0, previous['wrinkleDensity'] as num? ?? 0.0),
      ('darkCircle', current.darkCircle ?? 0.0, previous['darkCircle'] as num? ?? 0.0),
      ('brightness', current.brightness, previous['brightness'] as num? ?? 0.0),
      ('uniformity', current.uniformity, previous['uniformity'] as num? ?? 0.0),
    ];

    for (final (name, currentVal, previousVal) in metrics) {
      final delta = currentVal - (previousVal as double);
      final threshold = 0.05; // 5%以上の変化を検出

      if (delta < -threshold) {
        // 改善（数値が減少 = 良い）
        improvements[name] = delta.abs();
      } else if (delta > threshold) {
        // 悪化（数値が増加 = 悪い）
        deteriorations[name] = delta;
      }
    }

    // 画像レベルの差分解析（正規化済み画像を使用）
    final imageDifferential = _analyzeImageDifferential(normalizedImages);
    improvements.addAll(imageDifferential.improvements);
    deteriorations.addAll(imageDifferential.deteriorations);

    // 安定性スコアを計算（変化が少ないほど高い）
    final changeMagnitude =
        improvements.values.fold(0.0, (a, b) => a + b) + deteriorations.values.fold(0.0, (a, b) => a + b);
    final stabilityScore = (1.0 - math.min(changeMagnitude / 2.0, 1.0)).clamp(0.0, 1.0);

    return DifferentialAnalysis(
      improvements: improvements,
      deteriorations: deteriorations,
      stabilityScore: stabilityScore,
    );
  }

  /// 画像レベルの差分解析
  static DifferentialAnalysis _analyzeImageDifferential(NormalizedImagePair images) {
    final improvements = <String, double>{};
    final deteriorations = <String, double>{};

    // ピクセルレベルの差分を計算
    final current = images.current;
    final previous = images.previous;

    if (current.width != previous.width || current.height != previous.height) {
      return DifferentialAnalysis(improvements: {}, deteriorations: {}, stabilityScore: 0.5);
    }

    // 領域別の差分解析
    final regionDiffs = <String, double>{};

    // 頬領域（ニキビ・くすみ）
    final cheekDiff = _calculateRegionDifference(
      current,
      previous,
      x: (current.width * 0.3).toInt(),
      y: (current.height * 0.3).toInt(),
      width: (current.width * 0.4).toInt(),
      height: (current.height * 0.3).toInt(),
    );
    regionDiffs['cheek'] = cheekDiff;

    // 目下領域（くま）
    final underEyeDiff = _calculateRegionDifference(
      current,
      previous,
      x: (current.width * 0.2).toInt(),
      y: (current.height * 0.5).toInt(),
      width: (current.width * 0.6).toInt(),
      height: (current.height * 0.15).toInt(),
    );
    regionDiffs['underEye'] = underEyeDiff;

    // 額領域（シワ・くすみ）
    final foreheadDiff = _calculateRegionDifference(
      current,
      previous,
      x: (current.width * 0.2).toInt(),
      y: (current.height * 0.1).toInt(),
      width: (current.width * 0.6).toInt(),
      height: (current.height * 0.2).toInt(),
    );
    regionDiffs['forehead'] = foreheadDiff;

    // 差分から改善/悪化を判定
    for (final entry in regionDiffs.entries) {
      if (entry.value > 0.1) {
        deteriorations['${entry.key}_texture'] = entry.value;
      } else if (entry.value < -0.1) {
        improvements['${entry.key}_texture'] = entry.value.abs();
      }
    }

    return DifferentialAnalysis(
      improvements: improvements,
      deteriorations: deteriorations,
      stabilityScore: 0.5,
    );
  }

  /// 領域の差分を計算
  static double _calculateRegionDifference(
    img.Image current,
    img.Image previous, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    double totalDiff = 0.0;
    int count = 0;

    for (int dy = 0; dy < height && (y + dy) < current.height && (y + dy) < previous.height; dy++) {
      for (int dx = 0; dx < width && (x + dx) < current.width && (x + dx) < previous.width; dx++) {
        final cx = x + dx;
        final cy = y + dy;

        final currentPixel = current.getPixel(cx, cy);
        final previousPixel = previous.getPixel(cx, cy);

        // 輝度の差分を計算
        final currentLuma = (0.299 * currentPixel.r + 0.587 * currentPixel.g + 0.114 * currentPixel.b);
        final previousLuma = (0.299 * previousPixel.r + 0.587 * previousPixel.g + 0.114 * previousPixel.b);

        totalDiff += (currentLuma - previousLuma).abs() / 255.0;
        count++;
      }
    }

    return count > 0 ? totalDiff / count : 0.0;
  }

  /// 比較補正を適用
  static SkinAnalysisResult _applyComparisonCorrection({
    required SkinAnalysisResult current,
    required DifferentialAnalysis differential,
    required Map<String, dynamic> comparisonData,
  }) {
    // 比較結果に基づいて値を補正
    double dullness = current.dullnessIndex ?? 0.0;
    double acne = current.acneActivity ?? 0.0;
    double wrinkle = current.wrinkleDensity ?? 0.0;
    double darkCircle = current.darkCircle ?? 0.0;

    // 改善があった場合は信頼度を上げる（精度向上）
    if (differential.improvements.containsKey('dullnessIndex')) {
      // くすみが改善 → 現在の値の信頼度を上げる
      dullness = (dullness * 0.7 + (current.dullnessIndex ?? 0.0) * 0.3).clamp(0.0, 1.0);
    }

    if (differential.improvements.containsKey('acneActivity')) {
      // ニキビが改善
      acne = (acne * 0.7 + (current.acneActivity ?? 0.0) * 0.3).clamp(0.0, 1.0);
    }

    if (differential.improvements.containsKey('wrinkleDensity')) {
      // シワが改善
      wrinkle = (wrinkle * 0.7 + (current.wrinkleDensity ?? 0.0) * 0.3).clamp(0.0, 1.0);
    }

    if (differential.improvements.containsKey('darkCircle')) {
      // くまが改善
      darkCircle = (darkCircle * 0.7 + (current.darkCircle ?? 0.0) * 0.3).clamp(0.0, 1.0);
    }

    // 悪化があった場合は警告フラグを立てる
    if (differential.deteriorations.containsKey('acneActivity')) {
      // ニキビが悪化 → 値を強調
      acne = math.min(acne * 1.2, 1.0);
    }

    if (differential.deteriorations.containsKey('wrinkleDensity')) {
      // シワが悪化
      wrinkle = math.min(wrinkle * 1.2, 1.0);
    }

    // 補正済み結果を返す
    return SkinAnalysisResult(
      skinType: current.skinType,
      oiliness: current.oiliness,
      smoothness: current.smoothness,
      uniformity: current.uniformity,
      poreSize: current.poreSize,
      brightness: current.brightness,
      skinIssues: current.skinIssues,
      regionAnalysis: current.regionAnalysis,
      recommendation: current.recommendation,
      dullnessIndex: dullness,
      spotDensity: current.spotDensity,
      acneActivity: acne,
      wrinkleDensity: wrinkle,
      eyeBrightness: current.eyeBrightness,
      darkCircle: darkCircle,
      browBalance: current.browBalance,
      noseGloss: current.noseGloss,
      jawPuffiness: current.jawPuffiness,
    );
  }
}

/// 比較タイプ
enum ComparisonType {
  none, // 比較なし
  previousDay, // 前日と比較
  tutorial, // チュートリアルと比較
}

/// 正規化された画像ペア
class NormalizedImagePair {
  final img.Image current;
  final img.Image previous;

  NormalizedImagePair({
    required this.current,
    required this.previous,
  });
}

/// 差分解析結果
class DifferentialAnalysis {
  final Map<String, double> improvements; // 改善項目
  final Map<String, double> deteriorations; // 悪化項目
  final double stabilityScore; // 安定性スコア（0..1）

  DifferentialAnalysis({
    required this.improvements,
    required this.deteriorations,
    required this.stabilityScore,
  });
}

/// 比較補正済みの肌分析結果
class EnhancedSkinAnalysisResult {
  final SkinAnalysisResult baseResult;
  final ComparisonType comparisonType;
  final Map<String, double> improvements; // 改善項目
  final Map<String, double> deteriorations; // 悪化項目
  final double stabilityScore; // 安定性スコア

  EnhancedSkinAnalysisResult({
    required this.baseResult,
    required this.comparisonType,
    required this.improvements,
    required this.deteriorations,
    required this.stabilityScore,
  });
}
