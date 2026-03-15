import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// ROI（Region of Interest）の定義
/// 顔の各部位を矩形で定義（相対座標: 0.0-1.0）
class SkinROI {
  // Tゾーン（額・鼻）
  static ui.Rect getTZone(ui.Rect faceBox) {
    return ui.Rect.fromLTWH(
      faceBox.left + faceBox.width * 0.2,
      faceBox.top,
      faceBox.width * 0.6,
      faceBox.height * 0.4,
    );
  }

  // Uゾーン（両頬）
  static ui.Rect getUZone(ui.Rect faceBox) {
    return ui.Rect.fromLTWH(
      faceBox.left + faceBox.width * 0.1,
      faceBox.top + faceBox.height * 0.4,
      faceBox.width * 0.8,
      faceBox.height * 0.3,
    );
  }

  // 鼻周り（小鼻・鼻横）
  static ui.Rect getNoseArea(ui.Rect faceBox) {
    return ui.Rect.fromLTWH(
      faceBox.left + faceBox.width * 0.35,
      faceBox.top + faceBox.height * 0.35,
      faceBox.width * 0.3,
      faceBox.height * 0.2,
    );
  }

  // 目の下
  static ui.Rect getUnderEye(ui.Rect faceBox) {
    return ui.Rect.fromLTWH(
      faceBox.left + faceBox.width * 0.2,
      faceBox.top + faceBox.height * 0.3,
      faceBox.width * 0.6,
      faceBox.height * 0.15,
    );
  }

  // 口周り
  static ui.Rect getMouthArea(ui.Rect faceBox) {
    return ui.Rect.fromLTWH(
      faceBox.left + faceBox.width * 0.25,
      faceBox.top + faceBox.height * 0.6,
      faceBox.width * 0.5,
      faceBox.height * 0.15,
    );
  }

  // フェイスライン
  static ui.Rect getFaceLine(ui.Rect faceBox) {
    return ui.Rect.fromLTWH(
      faceBox.left + faceBox.width * 0.1,
      faceBox.top + faceBox.height * 0.7,
      faceBox.width * 0.8,
      faceBox.height * 0.2,
    );
  }

  // 額中央（眉間周辺）
  static ui.Rect getForeheadCenter(ui.Rect faceBox) {
    return ui.Rect.fromLTWH(
      faceBox.left + faceBox.width * 0.3,
      faceBox.top + faceBox.height * 0.05,
      faceBox.width * 0.4,
      faceBox.height * 0.25,
    );
  }
}

/// 肌質指標の計算パラメータ（チューニング用）
class SkinQualityParams {
  // 皮脂量（Oiliness）
  static const double highlightThreshold = 220.0; // ハイライト判定の閾値（0-255）
  static const double oilinessHighlightWeight = 0.7; // ハイライト割合の重み
  static const double oilinessLuminanceWeight = 0.3; // 平均輝度の重み

  // 乾燥（Dryness）
  static const double drynessHighlightThreshold = 200.0; // テカり判定の閾値
  static const double drynessTextureWeight = 0.6; // テクスチャの重み
  static const double drynessHighlightWeight = 0.4; // テカりの重み（逆）

  // キメ/テクスチャ（Texture）
  static const int textureGridSize = 8; // グリッド分割サイズ
  static const double textureSmoothThreshold = 0.05; // 滑らかさの閾値

  // 透明感/色ムラ（Evenness）
  static const double evennessVarianceThreshold = 0.1; // 分散の閾値

  // 毛穴（Pores）
  static const double poreContrastThreshold = 30.0; // コントラスト閾値
  static const double poreDarkThreshold = 100.0; // 暗い点の閾値

  // 赤み（Redness）
  static const double rednessThreshold = 0.4; // R/(R+G+B)の閾値

  // ハリ・弾力（Firmness）
  static const double firmnessEdgeThreshold = 50.0; // エッジ検出の閾値
  static const double firmnessShadowWeight = 0.5; // 影の重み
  static const double firmnessEdgeWeight = 0.5; // エッジの重み

  // ニキビ・炎症（Acne）
  static const double acneRedThreshold = 0.45; // 赤みの閾値
  static const double acneContrastThreshold = 25.0; // コントラスト閾値
  static const int acneMinPatchSize = 3; // 最小パッチサイズ

  // 肌タイプ判定の閾値
  static const double oilyThreshold = 60.0; // 脂性肌の閾値
  static const double dryThreshold = 60.0; // 乾燥肌の閾値
  static const double sensitiveRednessThreshold = 50.0; // 敏感肌の赤み閾値
  static const double sensitiveAcneThreshold = 40.0; // 敏感肌のニキビ閾値
}

/// 肌質分析の詳細指標を計算するクラス
class SkinQualityAnalyzer {
  /// 画像からROIを抽出
  static img.Image extractROI(img.Image image, ui.Rect roi) {
    try {
      // 画像サイズの確認
      if (image.width <= 0 || image.height <= 0) {
        throw Exception('画像サイズが無効です: ${image.width}x${image.height}');
      }

      final x = roi.left.clamp(0, image.width - 1).toInt();
      final y = roi.top.clamp(0, image.height - 1).toInt();
      final w = roi.width.clamp(1, image.width - x).toInt();
      final h = roi.height.clamp(1, image.height - y).toInt();

      // デバッグログ
      if (w <= 0 || h <= 0) {
        print(
            '[SkinQualityAnalyzer] ⚠️ ROI抽出エラー: x=$x, y=$y, w=$w, h=$h, imageSize=${image.width}x${image.height}, roi=$roi');
        // 無効なROIの場合は、顔領域全体の一部を返す（フォールバック）
        final fallbackW = math.min(100, image.width);
        final fallbackH = math.min(100, image.height);
        final fallbackX = (image.width - fallbackW) ~/ 2;
        final fallbackY = (image.height - fallbackH) ~/ 2;
        return img.copyCrop(image, x: fallbackX, y: fallbackY, width: fallbackW, height: fallbackH);
      }

      return img.copyCrop(image, x: x, y: y, width: w, height: h);
    } catch (e) {
      print('[SkinQualityAnalyzer] ❌ ROI抽出エラー: $e');
      // エラー時は最小限のROIを返す
      final fallbackW = math.min(50, image.width);
      final fallbackH = math.min(50, image.height);
      final fallbackX = (image.width - fallbackW) ~/ 2;
      final fallbackY = (image.height - fallbackH) ~/ 2;
      return img.copyCrop(image, x: fallbackX, y: fallbackY, width: fallbackW, height: fallbackH);
    }
  }

  /// 1. 皮脂量（Oiliness）を計算
  /// 対象: Tゾーン、小鼻周り
  /// 高いほど皮脂が多い（0-100）
  static double calculateOiliness(img.Image image, ui.Rect faceBox) {
    try {
      final tZone = extractROI(image, SkinROI.getTZone(faceBox));
      final noseArea = extractROI(image, SkinROI.getNoseArea(faceBox));

      // Tゾーンの分析
      final tZoneScore = _analyzeOilinessInROI(tZone);
      final noseScore = _analyzeOilinessInROI(noseArea);

      // 重み付け平均（Tゾーン70%、鼻30%）
      final oiliness = (tZoneScore * 0.7 + noseScore * 0.3).clamp(0.0, 100.0);
      print('[SkinQualityAnalyzer] 皮脂量: tZone=$tZoneScore, nose=$noseScore, 最終=$oiliness');
      return oiliness;
    } catch (e) {
      print('[SkinQualityAnalyzer] ❌ 皮脂量計算エラー: $e');
      return 50.0; // デフォルト値
    }
  }

  /// ROI内の皮脂量を分析
  static double _analyzeOilinessInROI(img.Image roi) {
    if (roi.width == 0 || roi.height == 0) {
      print('[SkinQualityAnalyzer] ⚠️ 皮脂量分析: ROIが空です');
      return 50.0; // デフォルト値
    }

    double totalLuminance = 0.0;
    int highlightCount = 0;
    int totalPixels = 0;

    final bytes = roi.getBytes();
    for (int i = 0; i < bytes.length; i += 4) {
      final r = bytes[i].toDouble();
      final g = bytes[i + 1].toDouble();
      final b = bytes[i + 2].toDouble();
      final luminance = 0.299 * r + 0.587 * g + 0.114 * b;

      totalLuminance += luminance;
      if (luminance >= SkinQualityParams.highlightThreshold) {
        highlightCount++;
      }
      totalPixels++;
    }

    if (totalPixels == 0) {
      print('[SkinQualityAnalyzer] ⚠️ 皮脂量分析: ピクセル数が0です');
      return 50.0; // デフォルト値
    }

    final avgLuminance = totalLuminance / totalPixels;
    final highlightRatio = highlightCount / totalPixels;

    // ハイライト割合と平均輝度を組み合わせてスコア化
    // より敏感に反応するように重みを調整
    final normalizedLuminance = (avgLuminance / 255.0).clamp(0.0, 1.0);
    // ハイライトの影響を大きくする（皮脂が多いほどハイライトが多い）
    final highlightScore = highlightRatio * 1.5; // 感度を上げる
    final luminanceScore = normalizedLuminance * 0.8; // 感度を下げる（補助的な指標）
    final score = (highlightScore * 0.8 + luminanceScore * 0.2).clamp(0.0, 1.0) * 100.0;

    print(
        '[SkinQualityAnalyzer] 皮脂量分析詳細: avgLuminance=$avgLuminance, highlightCount=$highlightCount, highlightRatio=$highlightRatio, highlightScore=$highlightScore, luminanceScore=$luminanceScore, score=$score');
    return score.clamp(0.0, 100.0);
  }

  /// 2. 乾燥（Dryness）を計算
  /// 対象: 頬、口周り
  /// 高いほど乾燥している（0-100）
  static double calculateDryness(img.Image image, ui.Rect faceBox) {
    try {
      final uZone = extractROI(image, SkinROI.getUZone(faceBox));
      final mouthArea = extractROI(image, SkinROI.getMouthArea(faceBox));

      final uZoneScore = _analyzeDrynessInROI(uZone);
      final mouthScore = _analyzeDrynessInROI(mouthArea);

      // 重み付け平均（頬60%、口周り40%）
      final dryness = (uZoneScore * 0.6 + mouthScore * 0.4).clamp(0.0, 100.0);
      print('[SkinQualityAnalyzer] 乾燥: uZone=$uZoneScore, mouth=$mouthScore, 最終=$dryness');
      return dryness;
    } catch (e) {
      print('[SkinQualityAnalyzer] ❌ 乾燥計算エラー: $e');
      return 50.0; // デフォルト値
    }
  }

  /// ROI内の乾燥度を分析
  static double _analyzeDrynessInROI(img.Image roi) {
    if (roi.width == 0 || roi.height == 0) {
      print('[SkinQualityAnalyzer] ⚠️ 乾燥分析: ROIが空です');
      return 50.0; // デフォルト値
    }

    // テカり（ハイライト）が少ないほど乾燥
    int highlightCount = 0;
    double textureVariance = 0.0;
    int totalPixels = 0;

    final bytes = roi.getBytes();
    final luminances = <double>[];

    for (int i = 0; i < bytes.length; i += 4) {
      final r = bytes[i].toDouble();
      final g = bytes[i + 1].toDouble();
      final b = bytes[i + 2].toDouble();
      final luminance = 0.299 * r + 0.587 * g + 0.114 * b;

      luminances.add(luminance);
      if (luminance >= SkinQualityParams.drynessHighlightThreshold) {
        highlightCount++;
      }
      totalPixels++;
    }

    if (totalPixels == 0) {
      print('[SkinQualityAnalyzer] ⚠️ 乾燥分析: ピクセル数が0です');
      return 50.0; // デフォルト値
    }

    // テクスチャの分散を計算（局所分散）
    if (luminances.isNotEmpty) {
      final mean = luminances.reduce((a, b) => a + b) / luminances.length;
      textureVariance = luminances.map((l) => math.pow(l - mean, 2)).reduce((a, b) => a + b) / luminances.length;
    }

    final highlightRatio = highlightCount / totalPixels;
    // より敏感に反応するように正規化範囲を調整
    final textureScore = (textureVariance / 5000.0).clamp(0.0, 1.0); // 10000→5000に変更

    // テカりが少なく、テクスチャが荒いほど乾燥
    // 重みを調整して、より敏感に反応
    final highlightScore = (1.0 - highlightRatio) * 1.2; // 感度を上げる
    final textureScoreAdjusted = textureScore * 1.1; // 感度を上げる
    final dryness = ((highlightScore * 0.5 + textureScoreAdjusted * 0.5).clamp(0.0, 1.0)) * 100.0;

    print(
        '[SkinQualityAnalyzer] 乾燥分析詳細: highlightCount=$highlightCount, highlightRatio=$highlightRatio, textureVariance=$textureVariance, textureScore=$textureScore, highlightScore=$highlightScore, textureScoreAdjusted=$textureScoreAdjusted, dryness=$dryness');
    return dryness.clamp(0.0, 100.0);
  }

  /// 3. キメ/テクスチャ（Texture）を計算
  /// 対象: 頬
  /// 高いほどキメが細かい（0-100）
  static double calculateTexture(img.Image image, ui.Rect faceBox) {
    try {
      final uZone = extractROI(image, SkinROI.getUZone(faceBox));
      final texture = _analyzeTextureInROI(uZone);
      print('[SkinQualityAnalyzer] キメ: $texture');
      return texture;
    } catch (e) {
      print('[SkinQualityAnalyzer] ❌ キメ計算エラー: $e');
      return 50.0; // デフォルト値
    }
  }

  /// ROI内のキメ/テクスチャを分析
  static double _analyzeTextureInROI(img.Image roi) {
    if (roi.width == 0 || roi.height == 0) {
      print('[SkinQualityAnalyzer] ⚠️ キメ分析: ROIが空です');
      return 50.0;
    }

    // グレースケール変換
    final gray = img.grayscale(roi);

    // グリッドに分割して各グリッドの標準偏差を計算
    final gridSize = SkinQualityParams.textureGridSize;
    final gridWidth = (gray.width / gridSize).ceil();
    final gridHeight = (gray.height / gridSize).ceil();

    final variances = <double>[];

    for (int gy = 0; gy < gridSize; gy++) {
      for (int gx = 0; gx < gridSize; gx++) {
        final x = gx * gridWidth;
        final y = gy * gridHeight;
        final w = math.min(gridWidth, gray.width - x);
        final h = math.min(gridHeight, gray.height - y);

        if (w <= 0 || h <= 0) continue;

        final grid = img.copyCrop(gray, x: x, y: y, width: w, height: h);
        final bytes = grid.getBytes();
        final values = <double>[];

        for (int i = 0; i < bytes.length; i += 4) {
          values.add(bytes[i].toDouble());
        }

        if (values.isNotEmpty) {
          final mean = values.reduce((a, b) => a + b) / values.length;
          final variance = values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
          variances.add(variance);
        }
      }
    }

    if (variances.isEmpty) {
      print('[SkinQualityAnalyzer] ⚠️ キメ分析: 分散が計算できませんでした');
      return 50.0;
    }

    // 平均分散を計算（分散が小さいほどキメが細かい）
    final avgVariance = variances.reduce((a, b) => a + b) / variances.length;
    // 分散の範囲を調整（より敏感に反応するように）
    // 一般的な肌の分散は500-5000程度、理想的な肌は500以下
    final minVariance = 200.0;
    final maxVariance = 8000.0;
    final normalizedVariance = ((avgVariance - minVariance) / (maxVariance - minVariance)).clamp(0.0, 1.0);

    // キメが細かいほどスコアが高い（分散の逆数）
    final textureScore = (1.0 - normalizedVariance) * 100.0;
    print(
        '[SkinQualityAnalyzer] キメ分析詳細: avgVariance=$avgVariance, minVariance=$minVariance, maxVariance=$maxVariance, normalizedVariance=$normalizedVariance, textureScore=$textureScore');
    return textureScore.clamp(0.0, 100.0);
  }

  /// 4. 透明感/色ムラ（Evenness）を計算
  /// 対象: 頬、額
  /// 高いほど透明感があり色ムラが少ない（0-100）
  static double calculateEvenness(img.Image image, ui.Rect faceBox) {
    try {
      final uZone = extractROI(image, SkinROI.getUZone(faceBox));
      final forehead = extractROI(image, SkinROI.getForeheadCenter(faceBox));

      final uZoneScore = _analyzeEvennessInROI(uZone);
      final foreheadScore = _analyzeEvennessInROI(forehead);

      // 重み付け平均（頬60%、額40%）
      final evenness = (uZoneScore * 0.6 + foreheadScore * 0.4).clamp(0.0, 100.0);
      print('[SkinQualityAnalyzer] 透明感: uZone=$uZoneScore, forehead=$foreheadScore, 最終=$evenness');
      return evenness;
    } catch (e) {
      print('[SkinQualityAnalyzer] ❌ 透明感計算エラー: $e');
      return 50.0; // デフォルト値
    }
  }

  /// ROI内の透明感/色ムラを分析
  static double _analyzeEvennessInROI(img.Image roi) {
    if (roi.width == 0 || roi.height == 0) {
      print('[SkinQualityAnalyzer] ⚠️ 透明感分析: ROIが空です');
      return 50.0;
    }

    final bytes = roi.getBytes();
    final luminances = <double>[];
    final saturations = <double>[];

    for (int i = 0; i < bytes.length; i += 4) {
      final r = bytes[i].toDouble();
      final g = bytes[i + 1].toDouble();
      final b = bytes[i + 2].toDouble();

      // 明度を計算
      final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
      luminances.add(luminance);

      // 彩度を計算（簡易版: RGBの最大値と最小値の差）
      final max = math.max(math.max(r, g), b);
      final min = math.min(math.min(r, g), b);
      final saturation = max > 0 ? (max - min) / max : 0.0;
      saturations.add(saturation);
    }

    if (luminances.isEmpty) {
      print('[SkinQualityAnalyzer] ⚠️ 透明感分析: 明度データが空です');
      return 50.0;
    }

    // 明度と彩度の分散を計算
    final luminanceMean = luminances.reduce((a, b) => a + b) / luminances.length;
    final luminanceVariance =
        luminances.map((l) => math.pow(l - luminanceMean, 2)).reduce((a, b) => a + b) / luminances.length;

    final saturationMean = saturations.reduce((a, b) => a + b) / saturations.length;
    final saturationVariance =
        saturations.map((s) => math.pow(s - saturationMean, 2)).reduce((a, b) => a + b) / saturations.length;

    // 分散が小さいほど均一（透明感がある）
    // より敏感に反応するように正規化範囲を調整
    final normalizedLuminanceVar = (luminanceVariance / 5000.0).clamp(0.0, 1.0); // 10000→5000に変更
    final normalizedSaturationVar = (saturationVariance / 0.5).clamp(0.0, 1.0); // 1.0→0.5に変更

    final evenness = (1.0 - (normalizedLuminanceVar * 0.6 + normalizedSaturationVar * 0.4)) * 100.0;
    print(
        '[SkinQualityAnalyzer] 透明感分析詳細: luminanceVar=$luminanceVariance, saturationVar=$saturationVariance, normalizedLuminanceVar=$normalizedLuminanceVar, normalizedSaturationVar=$normalizedSaturationVar, evenness=$evenness');
    return evenness.clamp(0.0, 100.0);
  }

  /// 5. 毛穴（Pores）を計算
  /// 対象: 鼻、小鼻横、頬（小鼻近く）
  /// 高いほど毛穴が目立つ（0-100）
  static double calculatePores(img.Image image, ui.Rect faceBox) {
    try {
      final noseArea = extractROI(image, SkinROI.getNoseArea(faceBox));
      final uZone = extractROI(image, SkinROI.getUZone(faceBox));

      final noseScore = _analyzePoresInROI(noseArea);
      final cheekScore = _analyzePoresInROI(uZone);

      // 重み付け平均（鼻70%、頬30%）
      final pores = (noseScore * 0.7 + cheekScore * 0.3).clamp(0.0, 100.0);
      print('[SkinQualityAnalyzer] 毛穴: nose=$noseScore, cheek=$cheekScore, 最終=$pores');
      return pores;
    } catch (e) {
      print('[SkinQualityAnalyzer] ❌ 毛穴計算エラー: $e');
      return 50.0; // デフォルト値
    }
  }

  /// ROI内の毛穴を分析
  static double _analyzePoresInROI(img.Image roi) {
    if (roi.width == 0 || roi.height == 0) {
      print('[SkinQualityAnalyzer] ⚠️ 毛穴分析: ROIが空です');
      return 50.0; // デフォルト値
    }

    // グレースケール変換
    final gray = img.grayscale(roi);

    // Sobelエッジ検出（簡易版: コントラストの強い点を検出）
    int darkPointCount = 0;
    int highContrastCount = 0;
    int totalPixels = 0;

    final bytes = gray.getBytes();
    for (int i = 0; i < bytes.length; i += 4) {
      final luminance = bytes[i].toDouble();
      totalPixels++;

      // 暗い点をカウント
      if (luminance < SkinQualityParams.poreDarkThreshold) {
        darkPointCount++;
      }

      // 周囲とのコントラストを計算（簡易版）
      // 実際の実装では、周囲のピクセルとの差を計算する必要がある
      // ここでは簡易的に、明度の急激な変化を検出
    }

    if (totalPixels == 0) {
      print('[SkinQualityAnalyzer] ⚠️ 毛穴分析: ピクセル数が0です');
      return 50.0; // デフォルト値
    }

    // 暗い点の割合とコントラストから毛穴スコアを計算
    final darkRatio = darkPointCount / totalPixels;
    // 暗い点の割合を0-100の範囲に正規化（より敏感に反応するように調整）
    final pores = (darkRatio * 200.0).clamp(0.0, 100.0); // 感度を上げるため200倍

    print('[SkinQualityAnalyzer] 毛穴分析詳細: darkRatio=$darkRatio, pores=$pores');
    return pores;
  }

  /// 6. 赤み（Redness）を計算
  /// 対象: 頬、鼻横
  /// 高いほど赤みが強い（0-100）
  static double calculateRedness(img.Image image, ui.Rect faceBox) {
    try {
      final uZone = extractROI(image, SkinROI.getUZone(faceBox));
      final noseArea = extractROI(image, SkinROI.getNoseArea(faceBox));

      final uZoneScore = _analyzeRednessInROI(uZone);
      final noseScore = _analyzeRednessInROI(noseArea);

      // 重み付け平均（頬70%、鼻30%）
      final redness = (uZoneScore * 0.7 + noseScore * 0.3).clamp(0.0, 100.0);
      print('[SkinQualityAnalyzer] 赤み: uZone=$uZoneScore, nose=$noseScore, 最終=$redness');
      return redness;
    } catch (e) {
      print('[SkinQualityAnalyzer] ❌ 赤み計算エラー: $e');
      return 50.0; // デフォルト値
    }
  }

  /// ROI内の赤みを分析
  static double _analyzeRednessInROI(img.Image roi) {
    if (roi.width == 0 || roi.height == 0) {
      print('[SkinQualityAnalyzer] ⚠️ 赤み分析: ROIが空です');
      return 50.0; // デフォルト値
    }

    final bytes = roi.getBytes();
    double totalRedRatio = 0.0;
    int totalPixels = 0;

    for (int i = 0; i < bytes.length; i += 4) {
      final r = bytes[i].toDouble();
      final g = bytes[i + 1].toDouble();
      final b = bytes[i + 2].toDouble();
      final sum = r + g + b;

      if (sum > 0) {
        final redRatio = r / sum;
        totalRedRatio += redRatio;
        totalPixels++;
      }
    }

    if (totalPixels == 0) {
      print('[SkinQualityAnalyzer] ⚠️ 赤み分析: ピクセル数が0です');
      return 50.0; // デフォルト値
    }

    final avgRedRatio = totalRedRatio / totalPixels;
    // 赤みの強さをより正確に評価するため、閾値との比較を改善
    // 平均的な赤み比率（0.33-0.40程度）を基準に、それより高い場合は赤みが強いと判定
    final baseRedRatio = 0.33; // 基準値（RGBの平均的な比率）
    final rednessDiff = avgRedRatio - baseRedRatio;
    // 赤みの差を0-100の範囲に正規化（より敏感に反応）
    final redness = ((rednessDiff / 0.2).clamp(-1.0, 1.0) + 1.0) * 50.0; // -1.0~1.0を0~100に変換

    print(
        '[SkinQualityAnalyzer] 赤み分析詳細: avgRedRatio=$avgRedRatio, baseRedRatio=$baseRedRatio, rednessDiff=$rednessDiff, redness=$redness');
    return redness.clamp(0.0, 100.0);
  }

  /// 7. ハリ・弾力（Firmness）を計算
  /// 対象: 目の下、ほうれい線周り
  /// 高いほどハリがある（0-100）
  static double calculateFirmness(img.Image image, ui.Rect faceBox) {
    try {
      final underEye = extractROI(image, SkinROI.getUnderEye(faceBox));
      final faceLine = extractROI(image, SkinROI.getFaceLine(faceBox));

      final underEyeScore = _analyzeFirmnessInROI(underEye);
      final faceLineScore = _analyzeFirmnessInROI(faceLine);

      // 重み付け平均（目の下60%、フェイスライン40%）
      final firmness = (underEyeScore * 0.6 + faceLineScore * 0.4).clamp(0.0, 100.0);
      print('[SkinQualityAnalyzer] ハリ: underEye=$underEyeScore, faceLine=$faceLineScore, 最終=$firmness');
      return firmness;
    } catch (e) {
      print('[SkinQualityAnalyzer] ❌ ハリ計算エラー: $e');
      return 50.0; // デフォルト値
    }
  }

  /// ROI内のハリ・弾力を分析
  static double _analyzeFirmnessInROI(img.Image roi) {
    if (roi.width == 0 || roi.height == 0) return 50.0;

    // グレースケール変換
    final gray = img.grayscale(roi);

    // エッジ検出（簡易版: Sobel相当）
    int edgeCount = 0;
    double totalContrast = 0.0;
    int totalPixels = 0;

    final bytes = gray.getBytes();
    final width = gray.width;
    final height = gray.height;

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final idx = (y * width + x) * 4;
        if (idx + 4 >= bytes.length) continue;

        final center = bytes[idx].toDouble();
        final right = bytes[idx + 4].toDouble();
        // 【D】index計算バグを修正: (y+1)*width + x に *4 を適用（RGBAバイト配列のindex）
        final bottomIdx = ((y + 1) * width + x) * 4;

        if (bottomIdx >= bytes.length) continue;

        final bottomPixel = bytes[bottomIdx].toDouble();

        // 簡易エッジ検出（水平・垂直方向の勾配）
        final horizontalGradient = (right - center).abs();
        final verticalGradient = (bottomPixel - center).abs();
        final gradient = math.max(horizontalGradient, verticalGradient);

        totalContrast += gradient;
        if (gradient > SkinQualityParams.firmnessEdgeThreshold) {
          edgeCount++;
        }
        totalPixels++;
      }
    }

    if (totalPixels == 0) {
      print('[SkinQualityAnalyzer] ⚠️ ハリ分析: ピクセル数が0です');
      return 50.0; // デフォルト値
    }

    // エッジが少なく、コントラストが低いほどハリがある
    final edgeRatio = edgeCount / totalPixels;
    final avgContrast = totalContrast / totalPixels;
    // より敏感に反応するように正規化範囲を調整
    final normalizedContrast = (avgContrast / 128.0).clamp(0.0, 1.0); // 255→128に変更

    // しわが少ないほどハリが高い（エッジとコントラストの逆数）
    // エッジとコントラストの重みを調整して、より敏感に反応
    final firmness = (1.0 - (edgeRatio * 0.7 + normalizedContrast * 0.3)) * 100.0;

    print(
        '[SkinQualityAnalyzer] ハリ分析詳細: edgeCount=$edgeCount, totalPixels=$totalPixels, edgeRatio=$edgeRatio, avgContrast=$avgContrast, normalizedContrast=$normalizedContrast, firmness=$firmness');
    return firmness.clamp(0.0, 100.0);
  }

  /// 8. ニキビ・炎症（Acne）を計算
  /// 対象: 額、頬、フェイスライン
  /// 高いほどニキビが多い（0-100）
  static double calculateAcne(img.Image image, ui.Rect faceBox) {
    try {
      final tZone = extractROI(image, SkinROI.getTZone(faceBox));
      final uZone = extractROI(image, SkinROI.getUZone(faceBox));
      final faceLine = extractROI(image, SkinROI.getFaceLine(faceBox));

      final tZoneScore = _analyzeAcneInROI(tZone);
      final uZoneScore = _analyzeAcneInROI(uZone);
      final faceLineScore = _analyzeAcneInROI(faceLine);

      // 重み付け平均（額30%、頬50%、フェイスライン20%）
      final acne = (tZoneScore * 0.3 + uZoneScore * 0.5 + faceLineScore * 0.2).clamp(0.0, 100.0);
      print('[SkinQualityAnalyzer] ニキビ: tZone=$tZoneScore, uZone=$uZoneScore, faceLine=$faceLineScore, 最終=$acne');
      return acne;
    } catch (e) {
      print('[SkinQualityAnalyzer] ❌ ニキビ計算エラー: $e');
      return 50.0; // デフォルト値
    }
  }

  /// ROI内のニキビ・炎症を分析
  static double _analyzeAcneInROI(img.Image roi) {
    if (roi.width == 0 || roi.height == 0) {
      print('[SkinQualityAnalyzer] ⚠️ ニキビ分析: ROIが空です');
      return 50.0; // デフォルト値
    }

    final bytes = roi.getBytes();
    int acnePatchCount = 0;
    int totalPixels = 0;

    // より詳細なニキビ検出: 赤み、コントラスト、テクスチャの変化を総合的に評価
    double totalRedScore = 0.0;
    double totalContrastScore = 0.0;
    int validPixels = 0;

    for (int y = 1; y < roi.height - 1; y++) {
      for (int x = 1; x < roi.width - 1; x++) {
        final idx = (y * roi.width + x) * 4;
        // インデックスの範囲チェック（RGB+Alphaの4バイト分を確保）
        if (idx < 0 || idx + 3 >= bytes.length) continue;

        final r = bytes[idx].toDouble();
        final g = bytes[idx + 1].toDouble();
        final b = bytes[idx + 2].toDouble();
        final sum = r + g + b;

        if (sum > 0) {
          final redRatio = r / sum;
          final luminance = 0.299 * r + 0.587 * g + 0.114 * b;

          // 周囲のピクセルとのコントラストを計算（4方向）
          final rightIdx = (y * roi.width + (x + 1)) * 4;
          final leftIdx = (y * roi.width + (x - 1)) * 4;
          final bottomIdx = ((y + 1) * roi.width + x) * 4;
          final topIdx = ((y - 1) * roi.width + x) * 4;

          double maxContrast = 0.0;
          // 右のピクセル
          if (rightIdx + 2 < bytes.length && x + 1 < roi.width) {
            final rightLum = 0.299 * bytes[rightIdx] + 0.587 * bytes[rightIdx + 1] + 0.114 * bytes[rightIdx + 2];
            maxContrast = math.max(maxContrast, (luminance - rightLum).abs());
          }
          // 左のピクセル
          if (leftIdx >= 0 && leftIdx + 2 < bytes.length && x - 1 >= 0) {
            final leftLum = 0.299 * bytes[leftIdx] + 0.587 * bytes[leftIdx + 1] + 0.114 * bytes[leftIdx + 2];
            maxContrast = math.max(maxContrast, (luminance - leftLum).abs());
          }
          // 下のピクセル
          if (bottomIdx + 2 < bytes.length && y + 1 < roi.height) {
            final bottomLum = 0.299 * bytes[bottomIdx] + 0.587 * bytes[bottomIdx + 1] + 0.114 * bytes[bottomIdx + 2];
            maxContrast = math.max(maxContrast, (luminance - bottomLum).abs());
          }
          // 上のピクセル
          if (topIdx >= 0 && topIdx + 2 < bytes.length && y - 1 >= 0) {
            final topLum = 0.299 * bytes[topIdx] + 0.587 * bytes[topIdx + 1] + 0.114 * bytes[topIdx + 2];
            maxContrast = math.max(maxContrast, (luminance - topLum).abs());
          }

          // 赤みスコア（基準値0.33より高い場合）
          final baseRedRatio = 0.33;
          final redScore = math.max(0.0, (redRatio - baseRedRatio) / 0.2); // 0-1に正規化
          totalRedScore += redScore;

          // コントラストスコア（閾値より高い場合）
          final contrastScore = (maxContrast / 50.0).clamp(0.0, 1.0); // 0-1に正規化
          totalContrastScore += contrastScore;

          // 赤みとコントラストの両方が高い場合、ニキビの可能性が高い
          if (redRatio > 0.38 && maxContrast > 20.0) {
            // 閾値を緩和
            acnePatchCount++;
          }

          validPixels++;
        }
        totalPixels++;
      }
    }

    if (totalPixels == 0 || validPixels == 0) {
      print('[SkinQualityAnalyzer] ⚠️ ニキビ分析: ピクセル数が0です');
      return 50.0; // デフォルト値
    }

    // 複数の指標を組み合わせてニキビスコアを計算
    final avgRedScore = totalRedScore / validPixels;
    final avgContrastScore = totalContrastScore / validPixels;
    final acneRatio = acnePatchCount / totalPixels;

    // 重み付け平均でニキビスコアを計算（より敏感に反応）
    final combinedScore = (avgRedScore * 0.4 + avgContrastScore * 0.3 + acneRatio * 10.0 * 0.3).clamp(0.0, 1.0);
    final acne = combinedScore * 100.0;

    print(
        '[SkinQualityAnalyzer] ニキビ分析詳細: validPixels=$validPixels, acnePatchCount=$acnePatchCount, totalPixels=$totalPixels, avgRedScore=$avgRedScore, avgContrastScore=$avgContrastScore, acneRatio=$acneRatio, combinedScore=$combinedScore, acne=$acne');
    return acne.clamp(0.0, 100.0);
  }

  /// 肌タイプを判定
  /// 返り値: 'dry', 'oily', 'combination', 'sensitive', 'normal'
  static String detectSkinType({
    required double oiliness,
    required double dryness,
    required double redness,
    required double acne,
  }) {
    // 敏感肌の判定（赤みとニキビが多い）
    if (redness >= SkinQualityParams.sensitiveRednessThreshold || acne >= SkinQualityParams.sensitiveAcneThreshold) {
      return 'sensitive';
    }

    // 脂性肌の判定
    if (oiliness >= SkinQualityParams.oilyThreshold && dryness < 40.0) {
      return 'oily';
    }

    // 乾燥肌の判定
    if (dryness >= SkinQualityParams.dryThreshold && oiliness < 40.0) {
      return 'dry';
    }

    // 混合肌の判定（Tゾーンが脂性、Uゾーンが乾燥）
    // 注: ここでは簡易的に、oilinessとdrynessが両方中程度以上の場合
    if (oiliness >= 40.0 && dryness >= 40.0) {
      return 'combination';
    }

    // デフォルト: 普通肌
    return 'normal';
  }
}
