import 'dart:math';
import 'dart:ui' as ui;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class FaceFeatures {
  final double smile; // 0..1
  final double eyeOpen; // 0..1
  final double gloss; // 肌ツヤ(輝度/ハイライト比)
  final double straightness; // 輪郭の直線率(0..1)
  final double claim; // 主張(目・眉・唇の強さ)
  FaceFeatures(this.smile, this.eyeOpen, this.gloss, this.straightness, this.claim);

  // 近似口角スコア（微笑の強さ）
  double mouthCorner() {
    // smileを代理指標として使用
    return smile.clamp(0.0, 1.0);
  }
}

class FaceAnalyzer {
  FaceDetector? _detector; // 毎回再生成するため、nullableに変更

  /// FaceDetectorを再生成（画像処理ごとに呼び出す）
  FaceDetector _createFaceDetector() {
    // 既存のFaceDetectorを閉じる
    _detector?.close();

    // 新しいFaceDetectorを作成
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableContours: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    print('[FaceAnalyzer] ✅ FaceDetectorを再生成しました（キャッシュをクリア）');
    return detector;
  }

  Future<FaceFeatures?> analyze(ui.Image flutterImage) async {
    try {
      // ✅ 修正: 画像処理ごとにFaceDetectorを再生成（キャッシュをクリア）
      _detector = _createFaceDetector();

      final bytes = await flutterImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) {
        print('[FaceAnalyzer] toByteData failed');
        await _detector?.close(); // エラー時も閉じる
        _detector = null;
        return null;
      }

      final input = InputImage.fromBytes(
        bytes: bytes.buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: ui.Size(flutterImage.width.toDouble(), flutterImage.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: flutterImage.width * 4,
        ),
      );

      final faces = await _detector!.processImage(input);

      // ✅ 修正: ランドマークのデバッグログを追加
      if (faces.isNotEmpty) {
        final f = faces.first;
        print('[FaceAnalyzer] ✅ ランドマーク数: ${f.landmarks.length}');
        print('[FaceAnalyzer] ✅ Contour数: ${f.contours.length}');

        // 重要なランドマークポイントをログ出力
        try {
          final leftEye = f.landmarks[FaceLandmarkType.leftEye];
          final rightEye = f.landmarks[FaceLandmarkType.rightEye];
          final leftMouth = f.landmarks[FaceLandmarkType.leftMouth];
          final rightMouth = f.landmarks[FaceLandmarkType.rightMouth];
          final noseBase = f.landmarks[FaceLandmarkType.noseBase];

          print('[FaceAnalyzer] ✅ raw landmark(左目): ${leftEye?.position}');
          print('[FaceAnalyzer] ✅ raw landmark(右目): ${rightEye?.position}');
          print('[FaceAnalyzer] ✅ raw landmark(口左): ${leftMouth?.position}');
          print('[FaceAnalyzer] ✅ raw landmark(口右): ${rightMouth?.position}');
          print('[FaceAnalyzer] ✅ raw landmark(鼻): ${noseBase?.position}');
        } catch (e) {
          print('[FaceAnalyzer] ⚠️ ランドマークログ出力エラー: $e');
        }
      }

      // 処理完了後、FaceDetectorを閉じる（キャッシュを残さない）
      await _detector!.close();
      _detector = null;
      if (faces.isEmpty) return null;
      final f = faces.first;

      // ① 表情: 笑顔確率 + 目の開き
      final smile = f.smilingProbability ?? 0.5;
      final leftEye = f.leftEyeOpenProbability ?? 0.5;
      final rightEye = f.rightEyeOpenProbability ?? 0.5;
      final eyeOpen = ((leftEye + rightEye) / 2.0).clamp(0.0, 1.0);

      // 画像→image.Image へ
      final decoded = img.decodeBmp(bytes.buffer.asUint8List()) ?? img.Image(width: 1, height: 1);

      // 顔矩形のパディング抽出
      final r = f.boundingBox.inflate(8);
      final rx = r.left.clamp(0, decoded.width - 1).toInt();
      final ry = r.top.clamp(0, decoded.height - 1).toInt();
      final rw = (r.width).clamp(1, decoded.width - rx).toInt();
      final rh = (r.height).clamp(1, decoded.height - ry).toInt();
      final crop = img.copyCrop(decoded, x: rx, y: ry, width: rw, height: rh);

      // ② 肌ツヤ: 平均輝度 + ハイライト比（しきい値は経験値）
      final luma = _avgLuma(crop);
      final highlightRatio = _highlightRatio(crop, thr: 220);
      final gloss = (0.6 * (luma / 255.0) + 0.4 * highlightRatio).clamp(0.0, 1.0);

      // ③ 輪郭直線率（顎～頬の輪郭点から曲率を概算）
      double straightness = 0.5;
      if (f.contours[FaceContourType.face] != null) {
        final pts = f.contours[FaceContourType.face]!.points;
        straightness = _linearity(pts); // 0..1 で直線的ほど高く
      }

      // ④ 主張: 目・眉・唇の強さを簡易に（コントラスト + 面積比）
      final claim = _facialClaim(crop);

      return FaceFeatures(smile, eyeOpen, gloss, straightness, claim);
    } catch (e) {
      print('[FaceAnalyzer] Error analyzing face: $e');
      // エラー時もFaceDetectorを閉じる
      await _detector?.close();
      _detector = null;
      return null;
    }
  }

  /// リソースを解放
  Future<void> dispose() async {
    await _detector?.close();
    _detector = null;
  }

  double _avgLuma(img.Image im) {
    final bytes = im.getBytes();
    double sum = 0;
    for (int i = 0; i < bytes.length; i += 4) {
      final r = bytes[i];
      final g = bytes[i + 1];
      final b = bytes[i + 2];
      sum += 0.299 * r + 0.587 * g + 0.114 * b;
    }
    return sum / (im.width * im.height);
  }

  double _highlightRatio(img.Image im, {int thr = 220}) {
    final bytes = im.getBytes();
    int count = 0, high = 0;
    for (int i = 0; i < bytes.length; i += 4) {
      final r = bytes[i];
      final g = bytes[i + 1];
      final b = bytes[i + 2];
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      if (l >= thr) high++;
      count++;
    }
    return (high / count).clamp(0.0, 1.0);
  }

  double _linearity(List<Point<int>> pts) {
    if (pts.length < 4) return 0.5;
    // 近似: 端点と中点の距離から曲率を推定
    final a = pts.first, b = pts[pts.length ~/ 2], c = pts.last;
    final ab = _dist(a, b), bc = _dist(b, c), ac = _dist(a, c);
    final detour = (ab + bc) / (ac + 1e-6);
    // detourが1に近いほど直線 → 1.2以上は丸み
    return (2 - detour).clamp(0.0, 1.0);
  }

  double _dist(Point p, Point q) => sqrt(pow(p.x - q.x, 2) + pow(p.y - q.y, 2));

  double _facialClaim(img.Image crop) {
    // ざっくり: 全体コントラスト(標準偏差)で主張度を近似
    final bytes = crop.getBytes();
    final lum = <double>[];
    for (int i = 0; i < bytes.length; i += 4) {
      final r = bytes[i];
      final g = bytes[i + 1];
      final b = bytes[i + 2];
      lum.add(0.299 * r + 0.587 * g + 0.114 * b);
    }
    final mean = lum.reduce((a, b) => a + b) / lum.length;
    final varSum = lum.fold<double>(0, (p, v) => p + (v - mean) * (v - mean));
    final std = sqrt(varSum / lum.length);
    return (std / 128.0).clamp(0.0, 1.0);
  }
}
