import 'dart:ui' as ui;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;

/// 画像正規化ユーティリティ
/// 顔の写真をアップロードした際に、顔の部分のみ適切な一定の比率で切り取り、
/// 全ての画像が同じ比率で処理できるように縮尺などを用いて正規化する
class ImageNormalizer {
  /// 標準的な顔画像サイズ（統一サイズ）
  static const int standardFaceSize = 512; // 512x512ピクセル

  /// 顔領域の拡張率（上下左右に拡張する割合）
  static const double faceExpandRatio = 0.2; // 20%拡張

  /// 顔領域を切り出して標準サイズにリサイズ
  ///
  /// [image] 元の画像
  /// [face] ML Kitで検出された顔
  ///
  /// 戻り値: 正規化された顔画像（standardFaceSize x standardFaceSize）
  static img.Image? normalizeFaceImage(img.Image image, Face face) {
    try {
      final boundingBox = face.boundingBox;

      // 顔領域を拡張（上下左右に20%拡張）
      final expandX = boundingBox.width * faceExpandRatio;
      final expandY = boundingBox.height * faceExpandRatio;

      final left = math.max(0, (boundingBox.left - expandX).toInt());
      final top = math.max(0, (boundingBox.top - expandY).toInt());
      final right = math.min(image.width, (boundingBox.right + expandX).toInt());
      final bottom = math.min(image.height, (boundingBox.bottom + expandY).toInt());

      final width = right - left;
      final height = bottom - top;

      if (width <= 0 || height <= 0) {
        print('[ImageNormalizer] ⚠️ 無効な顔領域サイズ: width=$width, height=$height');
        return null;
      }

      // 顔領域を切り出し
      final cropped = img.copyCrop(
        image,
        x: left,
        y: top,
        width: width,
        height: height,
      );

      // 標準サイズにリサイズ（アスペクト比を保持して中央に配置）
      final normalized = _resizeWithAspectRatio(
        cropped,
        targetSize: standardFaceSize,
      );

      print('[ImageNormalizer] ✅ 画像正規化完了: ${image.width}x${image.height} → ${normalized.width}x${normalized.height}');
      print('[ImageNormalizer]   顔領域: ${width}x${height} → 標準サイズ: ${standardFaceSize}x${standardFaceSize}');

      return normalized;
    } catch (e) {
      print('[ImageNormalizer] ❌ 画像正規化エラー: $e');
      return null;
    }
  }

  /// アスペクト比を保持してリサイズ（中央に配置）
  ///
  /// [image] 元の画像
  /// [targetSize] 目標サイズ（正方形）
  ///
  /// 戻り値: リサイズされた画像（targetSize x targetSize）
  static img.Image _resizeWithAspectRatio(
    img.Image image, {
    required int targetSize,
  }) {
    final aspectRatio = image.width / image.height;

    int newWidth, newHeight;
    if (aspectRatio > 1.0) {
      // 横長の場合
      newWidth = targetSize;
      newHeight = (targetSize / aspectRatio).toInt();
    } else {
      // 縦長または正方形の場合
      newWidth = (targetSize * aspectRatio).toInt();
      newHeight = targetSize;
    }

    // リサイズ
    final resized = img.copyResize(
      image,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.linear,
    );

    // 標準サイズの正方形画像を作成（中央に配置）
    // 背景色で塗りつぶされた画像を作成
    final avgColor = _getAverageColor(image);
    final normalized = img.Image(
      width: targetSize,
      height: targetSize,
    );

    // 背景色で塗りつぶす（各ピクセルを設定）
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        normalized.setPixel(x, y, avgColor);
      }
    }

    // リサイズした画像を中央に配置
    final offsetX = (targetSize - newWidth) ~/ 2;
    final offsetY = (targetSize - newHeight) ~/ 2;

    img.compositeImage(
      normalized,
      resized,
      dstX: offsetX,
      dstY: offsetY,
    );

    return normalized;
  }

  /// 画像の平均色を取得（背景色として使用）
  static img.Color _getAverageColor(img.Image image) {
    int r = 0, g = 0, b = 0;
    final pixelCount = image.width * image.height;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        r += pixel.r.toInt();
        g += pixel.g.toInt();
        b += pixel.b.toInt();
      }
    }

    return img.ColorRgb8(
      (r / pixelCount).round(),
      (g / pixelCount).round(),
      (b / pixelCount).round(),
    );
  }

  /// 顔の向きを正規化（回転補正）
  ///
  /// [image] 元の画像
  /// [face] ML Kitで検出された顔
  ///
  /// 戻り値: 回転補正された画像
  static img.Image? normalizeFaceOrientation(img.Image image, Face face) {
    try {
      final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
      final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

      if (leftEye == null || rightEye == null) {
        print('[ImageNormalizer] ⚠️ 目のランドマークが見つかりません');
        return image; // 回転補正なし
      }

      // 目の角度を計算（水平にする）
      final eyeAngle = math.atan2(
        rightEye.y - leftEye.y,
        rightEye.x - leftEye.x,
      );

      // 角度が小さい場合は回転不要
      if (eyeAngle.abs() < 0.01) {
        return image;
      }

      // 回転補正（度単位）
      final angleDegrees = eyeAngle * 180 / math.pi;

      print('[ImageNormalizer] 🔄 顔の向きを補正: ${angleDegrees.toStringAsFixed(2)}度');

      final rotated = img.copyRotate(
        image,
        angle: angleDegrees,
        interpolation: img.Interpolation.linear,
      );

      return rotated;
    } catch (e) {
      print('[ImageNormalizer] ⚠️ 回転補正エラー: $e');
      return image; // エラー時は元の画像を返す
    }
  }

  /// 回転補正のみを行う（切り出し・リサイズは行わない）
  ///
  /// [image] 元の画像
  /// [face] ML Kitで検出された顔
  ///
  /// 戻り値: 回転補正された画像
  static img.Image? normalizeFaceOrientationOnly(img.Image image, Face face) {
    return normalizeFaceOrientation(image, face);
  }

  /// 完全な正規化処理（回転補正 → 切り出し + リサイズ）
  ///
  /// 注意: 回転補正後の画像で再度顔検出を行う必要があります
  ///
  /// [image] 回転補正済みの画像
  /// [face] 回転補正後の画像で検出された顔
  ///
  /// 戻り値: 正規化された顔画像（standardFaceSize x standardFaceSize）
  static img.Image? fullyNormalizeFaceImage(img.Image image, Face face) {
    // 顔領域を切り出して標準サイズにリサイズ
    return normalizeFaceImage(image, face);
  }
}
