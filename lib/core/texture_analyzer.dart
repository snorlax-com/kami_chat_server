import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// 肌の質感と色調を分析するクラス
class TextureAnalyzer {
  /// 滑らかさを測定（0.0-1.0、高いほど滑らか）
  /// Laplacian分散を使用してテクスチャの粗さを評価
  static double calculateSmoothness(img.Image image) {
    try {
      // グレースケールに変換
      final gray = img.grayscale(img.copyResize(image, width: 256, height: 256));

      // Laplacianフィルタを適用してエッジを検出
      double variance = 0.0;
      int count = 0;

      // 3x3 Laplacianカーネル
      final laplacianKernel = [
        [0, -1, 0],
        [-1, 4, -1],
        [0, -1, 0],
      ];

      for (int y = 1; y < gray.height - 1; y++) {
        for (int x = 1; x < gray.width - 1; x++) {
          double sum = 0.0;
          for (int ky = -1; ky <= 1; ky++) {
            for (int kx = -1; kx <= 1; kx++) {
              final pixel = gray.getPixel(x + kx, y + ky);
              final value = pixel.r.toDouble();
              sum += value * laplacianKernel[ky + 1][kx + 1];
            }
          }
          variance += sum * sum;
          count++;
        }
      }

      final laplacianVariance = variance / count;

      // 分散が低いほど滑らか（逆転して0-1に正規化）
      // 経験的に、variance < 100 は非常に滑らか、variance > 1000 は粗い
      final smoothness = (1.0 - (laplacianVariance / 2000.0).clamp(0.0, 1.0));

      print(
          '[TextureAnalyzer] 滑らかさ: ${(smoothness * 100).toStringAsFixed(1)}% (Laplacian分散: ${laplacianVariance.toStringAsFixed(2)})');

      return smoothness.clamp(0.0, 1.0);
    } catch (e) {
      print('[TextureAnalyzer] 滑らかさ計算エラー: $e');
      return 0.5; // デフォルト値
    }
  }

  /// キメの細かさを測定（0.0-1.0、高いほどキメが細かい）
  /// テクスチャの細かさを評価（小さいパターンの存在）
  static double calculateTextureFineness(img.Image image) {
    try {
      // グレースケールに変換
      final gray = img.grayscale(img.copyResize(image, width: 256, height: 256));

      // ガウシアンブラーを適用して細かいテクスチャを抽出
      final blurred = _applyGaussianBlur(gray, radius: 2);

      // 元画像とブラー画像の差分を計算（細かいテクスチャ）
      double fineTextureSum = 0.0;
      int count = 0;

      for (int y = 0; y < gray.height; y++) {
        for (int x = 0; x < gray.width; x++) {
          final original = gray.getPixel(x, y).r.toDouble();
          final blurredValue = blurred.getPixel(x, y).r.toDouble();
          final diff = (original - blurredValue).abs();
          fineTextureSum += diff;
          count++;
        }
      }

      final fineTextureAvg = fineTextureSum / count;

      // 細かいテクスチャが多いほどキメが細かい
      // 経験的に、avg < 3 はキメが粗い、avg > 15 はキメが細かい
      // より感度の高いスケーリングを使用（範囲を拡大）
      final normalizedAvg = fineTextureAvg / 25.0; // 25を最大値として正規化（範囲を拡大）
      final fineness = normalizedAvg.clamp(0.0, 1.0);

      // 値の範囲を拡張（より広い範囲で値を返す）
      // 中央値0.4を基準に拡大（元の範囲0.0-1.0をより広く）
      final center = 0.4;
      final expansion = 1.5; // 拡大係数
      final expandedFineness = center + (fineness - center) * expansion;

      // 最小値を下げて振れ幅を拡大（0%に近い値も許容）
      final adjustedFineness = expandedFineness.clamp(0.05, 0.95);

      print(
          '[TextureAnalyzer] キメの細かさ: ${(adjustedFineness * 100).toStringAsFixed(1)}% (細かいテクスチャ平均: ${fineTextureAvg.toStringAsFixed(2)}, 正規化値: ${normalizedAvg.toStringAsFixed(3)}, 拡大後: ${expandedFineness.toStringAsFixed(3)})');

      return adjustedFineness;
    } catch (e) {
      print('[TextureAnalyzer] キメの細かさ計算エラー: $e');
      return 0.5; // デフォルト値
    }
  }

  /// 色調の均一性を測定（0.0-1.0、高いほど均一）
  /// 色の分散を計算して均一性を評価
  static double calculateColorUniformity(img.Image image) {
    try {
      // 肌領域を抽出（簡易版：中央部分を分析）
      final centerX = image.width ~/ 2;
      final centerY = image.height ~/ 2;
      final regionSize = math.min(image.width, image.height) ~/ 2;

      final startX = (centerX - regionSize ~/ 2).clamp(0, image.width);
      final startY = (centerY - regionSize ~/ 2).clamp(0, image.height);
      final endX = (startX + regionSize).clamp(0, image.width);
      final endY = (startY + regionSize).clamp(0, image.height);

      // HSV色空間で分析
      List<double> hValues = [];
      List<double> sValues = [];
      List<double> vValues = [];

      for (int y = startY; y < endY; y++) {
        for (int x = startX; x < endX; x++) {
          final pixel = image.getPixel(x, y);
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();

          // RGBからHSVに変換
          final hsv = _rgbToHsv(r, g, b);
          hValues.add(hsv[0]);
          sValues.add(hsv[1]);
          vValues.add(hsv[2]);
        }
      }

      // 標準偏差を計算
      final hStdDev = _calculateStdDev(hValues);
      final sStdDev = _calculateStdDev(sValues);
      final vStdDev = _calculateStdDev(vValues);

      // 標準偏差が小さいほど均一（逆転して0-1に正規化）
      // 経験的に、stdDev < 0.1 は非常に均一、stdDev > 0.3 は不均一
      // より感度の高いスケーリングを使用（範囲を拡大）
      final hUniformity = (1.0 - (hStdDev / 0.5).clamp(0.0, 1.0)); // 範囲を拡大（0.4 → 0.5）
      final sUniformity = (1.0 - (sStdDev / 0.5).clamp(0.0, 1.0));
      final vUniformity = (1.0 - (vStdDev / 0.5).clamp(0.0, 1.0));

      // 重み付け平均（明度が最も重要）
      final uniformity = (hUniformity * 0.2 + sUniformity * 0.3 + vUniformity * 0.5);

      // 値の範囲を拡張（より広い範囲で値を返す）
      // 中央値0.5を基準に拡大（元の範囲0.0-1.0をより広く）
      final center = 0.5;
      final expansion = 1.5; // 拡大係数
      final expandedUniformity = center + (uniformity - center) * expansion;

      // 最小値を下げて振れ幅を拡大（0%に近い値も許容）
      final adjustedUniformity = expandedUniformity.clamp(0.10, 0.95);

      print(
          '[TextureAnalyzer] 色調の均一性: ${(adjustedUniformity * 100).toStringAsFixed(1)}% (H: ${hStdDev.toStringAsFixed(3)}, S: ${sStdDev.toStringAsFixed(3)}, V: ${vStdDev.toStringAsFixed(3)}, 調整前: ${(uniformity * 100).toStringAsFixed(1)}%, 拡大後: ${expandedUniformity.toStringAsFixed(3)})');

      return adjustedUniformity;
    } catch (e) {
      print('[TextureAnalyzer] 色調の均一性計算エラー: $e');
      return 0.5; // デフォルト値
    }
  }

  /// くすみを測定（0.0-1.0、高いほどくすみが強い）
  /// 明度と彩度を分析してくすみを評価
  static double calculateDullness(img.Image image) {
    try {
      // 肌領域を抽出（簡易版：中央部分を分析）
      final centerX = image.width ~/ 2;
      final centerY = image.height ~/ 2;
      final regionSize = math.min(image.width, image.height) ~/ 2;

      final startX = (centerX - regionSize ~/ 2).clamp(0, image.width);
      final startY = (centerY - regionSize ~/ 2).clamp(0, image.height);
      final endX = (startX + regionSize).clamp(0, image.width);
      final endY = (startY + regionSize).clamp(0, image.height);

      double totalBrightness = 0.0;
      double totalSaturation = 0.0;
      int count = 0;

      for (int y = startY; y < endY; y++) {
        for (int x = startX; x < endX; x++) {
          final pixel = image.getPixel(x, y);
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();

          // RGBからHSVに変換
          final hsv = _rgbToHsv(r, g, b);
          final brightness = hsv[2]; // V値（明度）
          final saturation = hsv[1]; // S値（彩度）

          totalBrightness += brightness;
          totalSaturation += saturation;
          count++;
        }
      }

      final avgBrightness = totalBrightness / count;
      final avgSaturation = totalSaturation / count;

      // くすみ = 明度が低い + 彩度が低い
      // 明度が低いほどくすみ（0.0-1.0に正規化、逆転）
      final brightnessDullness = (1.0 - avgBrightness);
      // 彩度が低いほどくすみ（0.0-1.0に正規化、逆転）
      final saturationDullness = (1.0 - avgSaturation);

      // 重み付け平均（明度がより重要）
      final dullness = (brightnessDullness * 0.7 + saturationDullness * 0.3);

      print(
          '[TextureAnalyzer] くすみ: ${(dullness * 100).toStringAsFixed(1)}% (明度: ${(avgBrightness * 100).toStringAsFixed(1)}%, 彩度: ${(avgSaturation * 100).toStringAsFixed(1)}%)');

      return dullness.clamp(0.0, 1.0);
    } catch (e) {
      print('[TextureAnalyzer] くすみ計算エラー: $e');
      return 0.5; // デフォルト値
    }
  }

  /// ガウシアンブラーを適用
  static img.Image _applyGaussianBlur(img.Image image, {int radius = 2}) {
    final blurred = img.Image(width: image.width, height: image.height);

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        double sum = 0.0;
        double weightSum = 0.0;

        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = (x + dx).clamp(0, image.width - 1);
            final ny = (y + dy).clamp(0, image.height - 1);

            final distance = math.sqrt(dx * dx + dy * dy);
            final weight = math.exp(-(distance * distance) / (2 * radius * radius));

            final pixel = image.getPixel(nx, ny);
            sum += pixel.r.toDouble() * weight;
            weightSum += weight;
          }
        }

        final value = (sum / weightSum).clamp(0, 255).toInt();
        blurred.setPixel(x, y, img.ColorRgb8(value, value, value));
      }
    }

    return blurred;
  }

  /// RGBからHSVに変換
  static List<double> _rgbToHsv(double r, double g, double b) {
    r /= 255.0;
    g /= 255.0;
    b /= 255.0;

    final max = math.max(math.max(r, g), b);
    final min = math.min(math.min(r, g), b);
    final delta = max - min;

    double h = 0.0;
    if (delta != 0) {
      if (max == r) {
        h = 60.0 * (((g - b) / delta) % 6);
      } else if (max == g) {
        h = 60.0 * (((b - r) / delta) + 2);
      } else {
        h = 60.0 * (((r - g) / delta) + 4);
      }
    }
    if (h < 0) h += 360;
    h /= 360.0; // 0-1に正規化

    final s = max == 0 ? 0.0 : (delta / max);
    final v = max;

    return [h, s, v];
  }

  /// 標準偏差を計算
  static double _calculateStdDev(List<double> values) {
    if (values.isEmpty) return 0.0;

    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;

    return math.sqrt(variance);
  }
}
