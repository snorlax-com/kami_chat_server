import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:math' as math;

class FacePainter extends CustomPainter {
  static DateTime? _lastPaintLogTime;

  /// paint 内のログを最大1秒に1回に制限（実機ログの flood 防止）
  static void _paintLogThrottled(String message) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    if (_lastPaintLogTime != null && now.difference(_lastPaintLogTime!).inMilliseconds < 1000) return;
    _lastPaintLogTime = now;
    debugPrint(message);
  }

  final List<Face> faces;
  final double faceOutlineProgress;
  final double leftEyeProgress;
  final double rightEyeProgress;
  final double leftEyebrowProgress;
  final double rightEyebrowProgress;
  final double noseProgress;
  final double mouthProgress;
  final Size imageSize;

  FacePainter({
    required this.faces,
    required this.faceOutlineProgress,
    required this.leftEyeProgress,
    required this.rightEyeProgress,
    required this.leftEyebrowProgress,
    required this.rightEyebrowProgress,
    required this.noseProgress,
    required this.mouthProgress,
    required this.imageSize,
  });

  /// 画像座標を画面座標に変換
  /// CustomPaintのsizeが既に表示サイズ（BoxFit.containで計算済み）になっているため、
  /// 単純にスケールするだけで良い
  /// ✅ 修正: MLKitのPoint型はdouble型なので、intではなくnum型で受け取る
  Offset _scalePoint(num x, num y, Size canvasSize) {
    // canvasSizeは既に表示サイズ（displayWidth, displayHeight）になっている
    // 画像座標を表示サイズにスケール
    final scaleX = canvasSize.width / imageSize.width;
    final scaleY = canvasSize.height / imageSize.height;

    return Offset(x.toDouble() * scaleX, y.toDouble() * scaleY);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintLogThrottled(
        '[FacePainter] paint() faces.length=${faces.length} imageSize=${imageSize.width}x${imageSize.height}');

    if (faces.isEmpty) return;

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0 // より太くして見やすく
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 影効果のためのペイント
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3) // 影を軽く
      ..strokeWidth = 3.0 // 影も細く
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final face in faces) {
      _paintLogThrottled(
          '[FacePainter] 顔を描画中: ${face.boundingBox} imageSize=${imageSize.width}x${imageSize.height} canvas=${size.width}x${size.height}');
      _drawFaceOutline(canvas, face, size, paint, shadowPaint);
      _drawEyes(canvas, face, size, paint, shadowPaint);
      _drawEyebrows(canvas, face, size, paint, shadowPaint);
      _drawNose(canvas, face, size, paint, shadowPaint);
      _drawMouth(canvas, face, size, paint, shadowPaint);
    }
  }

  void _drawFaceOutline(Canvas canvas, Face face, Size size, Paint paint, Paint shadowPaint) {
    if (faceOutlineProgress <= 0) return;

    final faceContour = face.contours[FaceContourType.face];
    if (faceContour == null) {
      debugPrint('[FacePainter] 顔の輪郭データがありません');
      return;
    }

    final points = faceContour.points;
    if (points.length < 3) {
      debugPrint('[FacePainter] 顔の輪郭ポイントが不足: ${points.length}');
      return;
    }

    debugPrint('[FacePainter] 顔の輪郭ポイント数: ${points.length}');

    // 点線で輪郭を描画
    _drawDashedContourWithProgress(canvas, points, faceOutlineProgress, paint, shadowPaint, size);

    // 輪郭を閉じる（最後のポイントと最初のポイントを繋ぐ）
    if (faceOutlineProgress >= 1.0 && points.length > 2) {
      // ✅ 修正: MLKitのPoint型からx, yを取得
      final firstX = (points.first as dynamic).x;
      final firstY = (points.first as dynamic).y;
      final lastX = (points.last as dynamic).x;
      final lastY = (points.last as dynamic).y;

      final firstPoint = _scalePoint(firstX, firstY, size);
      final lastPoint = _scalePoint(lastX, lastY, size);

      // 最後のポイントと最初のポイントの間も点線で描画
      final dx = firstPoint.dx - lastPoint.dx;
      final dy = firstPoint.dy - lastPoint.dy;
      final distance = math.sqrt(dx * dx + dy * dy);

      if (distance > 0) {
        final unitX = dx / distance;
        final unitY = dy / distance;
        const double dashLength = 4.0;
        const double dashGap = 3.0;

        double drawn = 0;
        while (drawn < distance) {
          final dashStart = math.min(drawn, distance);
          final dashEnd = math.min(drawn + dashLength, distance);

          final dashStartX = lastPoint.dx + unitX * dashStart;
          final dashStartY = lastPoint.dy + unitY * dashStart;
          final dashEndX = lastPoint.dx + unitX * dashEnd;
          final dashEndY = lastPoint.dy + unitY * dashEnd;

          canvas.drawLine(Offset(dashStartX, dashStartY), Offset(dashEndX, dashEndY), shadowPaint);
          canvas.drawLine(Offset(dashStartX, dashStartY), Offset(dashEndX, dashEndY), paint);

          drawn += dashLength + dashGap;
        }
      }
    }
  }

  void _drawEyes(Canvas canvas, Face face, Size size, Paint paint, Paint shadowPaint) {
    _drawLeftEye(canvas, face, size, paint, shadowPaint);
    _drawRightEye(canvas, face, size, paint, shadowPaint);
  }

  void _drawLeftEye(Canvas canvas, Face face, Size size, Paint paint, Paint shadowPaint) {
    if (leftEyeProgress <= 0) return;

    final leftEyeContour = face.contours[FaceContourType.leftEye];
    if (leftEyeContour == null) return;

    final points = leftEyeContour.points;
    if (points.length < 3) return;

    _drawDashedContourWithProgress(canvas, points, leftEyeProgress, paint, shadowPaint, size);
  }

  void _drawRightEye(Canvas canvas, Face face, Size size, Paint paint, Paint shadowPaint) {
    if (rightEyeProgress <= 0) return;

    final rightEyeContour = face.contours[FaceContourType.rightEye];
    if (rightEyeContour == null) return;

    final points = rightEyeContour.points;
    if (points.length < 3) return;

    _drawDashedContourWithProgress(canvas, points, rightEyeProgress, paint, shadowPaint, size);
  }

  void _drawEyebrows(Canvas canvas, Face face, Size size, Paint paint, Paint shadowPaint) {
    _drawLeftEyebrow(canvas, face, size, paint, shadowPaint);
    _drawRightEyebrow(canvas, face, size, paint, shadowPaint);
  }

  void _drawLeftEyebrow(Canvas canvas, Face face, Size size, Paint paint, Paint shadowPaint) {
    if (leftEyebrowProgress <= 0) return;

    debugPrint('[FacePainter] 左眉の描画を開始します。progress: $leftEyebrowProgress');

    // ML Kitには眉毛の輪郭が直接提供されていないため、目の位置を基準に計算

    final leftEyeLandmark = face.landmarks[FaceLandmarkType.leftEye];
    if (leftEyeLandmark == null) {
      debugPrint('[FacePainter] 左目のランドマークが検出されませんでした。');
      return;
    }

    final eyePos = leftEyeLandmark.position;
    debugPrint('[FacePainter] 左目の位置: x=${eyePos.x}, y=${eyePos.y}');

    final faceBoundingBox = face.boundingBox;
    final faceHeight = faceBoundingBox.height;
    final eyebrowOffset = (faceHeight * 0.08).toInt();
    final eyebrowY = eyePos.y - eyebrowOffset;

    final topLinePoints = [
      math.Point<int>(eyePos.x - (faceBoundingBox.width * 0.15).toInt(), eyebrowY - (eyebrowOffset * 0.05).toInt()),
      math.Point<int>(eyePos.x - (faceBoundingBox.width * 0.10).toInt(), eyebrowY - (eyebrowOffset * 0.08).toInt()),
      math.Point<int>(eyePos.x - (faceBoundingBox.width * 0.05).toInt(), eyebrowY - (eyebrowOffset * 0.12).toInt()),
      math.Point<int>(eyePos.x, eyebrowY - (eyebrowOffset * 0.15).toInt()),
      math.Point<int>(eyePos.x + (faceBoundingBox.width * 0.05).toInt(), eyebrowY - (eyebrowOffset * 0.12).toInt()),
      math.Point<int>(eyePos.x + (faceBoundingBox.width * 0.10).toInt(), eyebrowY - (eyebrowOffset * 0.08).toInt()),
      math.Point<int>(eyePos.x + (faceBoundingBox.width * 0.15).toInt(), eyebrowY - (eyebrowOffset * 0.05).toInt()),
    ];

    _drawDashedContourWithProgress(canvas, topLinePoints, leftEyebrowProgress, paint, shadowPaint, size);
    debugPrint('[FacePainter] 左眉の描画が完了しました。');
  }

  void _drawRightEyebrow(Canvas canvas, Face face, Size size, Paint paint, Paint shadowPaint) {
    if (rightEyebrowProgress <= 0) return;

    debugPrint('[FacePainter] 右眉の描画を開始します。progress: $rightEyebrowProgress');

    // ML Kitには眉毛の輪郭が直接提供されていないため、目の位置を基準に計算

    final rightEyeLandmark = face.landmarks[FaceLandmarkType.rightEye];
    if (rightEyeLandmark == null) {
      debugPrint('[FacePainter] 右目のランドマークが検出されませんでした。');
      return;
    }

    final eyePos = rightEyeLandmark.position;
    debugPrint('[FacePainter] 右目の位置: x=${eyePos.x}, y=${eyePos.y}');

    final faceBoundingBox = face.boundingBox;
    final faceHeight = faceBoundingBox.height;
    final eyebrowOffset = (faceHeight * 0.08).toInt();
    final eyebrowY = eyePos.y - eyebrowOffset;

    final topLinePoints = [
      math.Point<int>(eyePos.x - (faceBoundingBox.width * 0.15).toInt(), eyebrowY - (eyebrowOffset * 0.05).toInt()),
      math.Point<int>(eyePos.x - (faceBoundingBox.width * 0.10).toInt(), eyebrowY - (eyebrowOffset * 0.08).toInt()),
      math.Point<int>(eyePos.x - (faceBoundingBox.width * 0.05).toInt(), eyebrowY - (eyebrowOffset * 0.12).toInt()),
      math.Point<int>(eyePos.x, eyebrowY - (eyebrowOffset * 0.15).toInt()),
      math.Point<int>(eyePos.x + (faceBoundingBox.width * 0.05).toInt(), eyebrowY - (eyebrowOffset * 0.12).toInt()),
      math.Point<int>(eyePos.x + (faceBoundingBox.width * 0.10).toInt(), eyebrowY - (eyebrowOffset * 0.08).toInt()),
      math.Point<int>(eyePos.x + (faceBoundingBox.width * 0.15).toInt(), eyebrowY - (eyebrowOffset * 0.05).toInt()),
    ];

    _drawDashedContourWithProgress(canvas, topLinePoints, rightEyebrowProgress, paint, shadowPaint, size);
    debugPrint('[FacePainter] 右眉の描画が完了しました。');
  }

  void _drawNose(Canvas canvas, Face face, Size size, Paint paint, Paint shadowPaint) {
    if (noseProgress <= 0) return;

    debugPrint('[FacePainter] 鼻の描画を開始します。progress: $noseProgress');

    // 鼻のランドマークを使用
    final noseLandmark = face.landmarks[FaceLandmarkType.noseBase];
    if (noseLandmark == null) {
      debugPrint('[FacePainter] 鼻のランドマークが検出されませんでした。');
      return;
    }

    final position = noseLandmark.position;
    debugPrint('[FacePainter] 鼻の位置: x=${position.x}, y=${position.y}');

    // 目の位置を取得して、鼻の付け根を正確に計算
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    int noseTopY = position.y;

    if (leftEye != null && rightEye != null) {
      // 目の中心位置を取得
      int eyeCenterY = ((leftEye.position.y + rightEye.position.y) / 2).toInt();
      // 鼻の付け根は目の中心よりさらに上に配置（より正確な鼻の付け根の位置）
      // 目の中心から鼻底までの距離の15%の位置を使用
      int eyeToNoseDistance = position.y - eyeCenterY;
      noseTopY = eyeCenterY + (eyeToNoseDistance * 0.15).toInt();
      debugPrint(
          '[FacePainter] 鼻の付け根計算: eyeCenterY=$eyeCenterY, eyeToNoseDistance=$eyeToNoseDistance, noseTopY=$noseTopY');
    } else {
      // フォールバック: より長い距離を使用
      noseTopY = position.y - 35;
    }

    // 鼻筋の付け根から一番上までを点線で引く（進行度に応じて）
    final scaledVerticalStart = _scalePoint(position.x, noseTopY, size);
    final scaledVerticalEnd = _scalePoint(position.x, (position.y + 10).toInt(), size);
    debugPrint(
        '[FacePainter] 鼻の垂直線: start=(${scaledVerticalStart.dx},${scaledVerticalStart.dy}), end=(${scaledVerticalEnd.dx},${scaledVerticalEnd.dy})');

    _drawDashedLineWithProgress(canvas, scaledVerticalStart, scaledVerticalEnd, noseProgress, paint, shadowPaint);

    // 鼻の横幅を点線で表す（顔の幅を基準に計算、進行度に応じて）
    final faceBoundingBox = face.boundingBox;
    final faceWidth = faceBoundingBox.width;
    int horizontalY = position.y + 5; // 鼻の先端付近

    // 顔の幅の20%を鼻の横幅として使用（より広く）
    int noseWidth = (faceWidth * 0.20).toInt();
    int noseMinX = position.x - noseWidth ~/ 2;
    int noseMaxX = position.x + noseWidth ~/ 2;

    debugPrint('[FacePainter] 鼻の横幅計算: 顔の幅=$faceWidth, 鼻の幅=$noseWidth, 左端=$noseMinX, 右端=$noseMaxX, y=$horizontalY');

    final scaledHorizontalStart = _scalePoint(noseMinX, horizontalY, size);
    final scaledHorizontalEnd = _scalePoint(noseMaxX, horizontalY, size);
    debugPrint(
        '[FacePainter] 鼻の水平線: start=(${scaledHorizontalStart.dx},${scaledHorizontalStart.dy}), end=(${scaledHorizontalEnd.dx},${scaledHorizontalEnd.dy})');

    _drawDashedLineWithProgress(canvas, scaledHorizontalStart, scaledHorizontalEnd, noseProgress, paint, shadowPaint);

    debugPrint('[FacePainter] 鼻の描画が完了しました。');
  }

  void _drawMouth(Canvas canvas, Face face, Size size, Paint paint, Paint shadowPaint) {
    if (mouthProgress <= 0) return;

    debugPrint('[FacePainter] 口の描画を開始します。');

    // Google ML Kitのランドマークを取得
    final leftMouthLandmark = face.landmarks[FaceLandmarkType.leftMouth];
    final rightMouthLandmark = face.landmarks[FaceLandmarkType.rightMouth];
    final bottomMouthLandmark = face.landmarks[FaceLandmarkType.bottomMouth];
    final noseBaseLandmark = face.landmarks[FaceLandmarkType.noseBase];

    debugPrint(
        '[FacePainter] 口のランドマーク: left=$leftMouthLandmark, right=$rightMouthLandmark, bottom=$bottomMouthLandmark');
    debugPrint('[FacePainter] 鼻のランドマーク: noseBase=$noseBaseLandmark');

    if (leftMouthLandmark != null && rightMouthLandmark != null && bottomMouthLandmark != null) {
      debugPrint('[FacePainter] Google ML Kitのランドマークを使用して口を描画します。');

      final leftPos = leftMouthLandmark.position;
      final rightPos = rightMouthLandmark.position;
      final bottomPos = bottomMouthLandmark.position;

      // 口の幅と中心を計算
      final mouthCenterX = (leftPos.x + rightPos.x) ~/ 2;
      final mouthWidth = rightPos.x - leftPos.x;

      // Google ML Kitの鼻底の位置を使用して、口の位置を正確に推定
      int mouthTopY, mouthBottomY, mouthCenterY;

      if (noseBaseLandmark != null) {
        final noseBasePos = noseBaseLandmark.position;
        final noseToBottomMouthDistance = bottomPos.y - noseBasePos.y;
        final mouthBottomOffset = (noseToBottomMouthDistance * 0.20).toInt();
        mouthBottomY = bottomPos.y - mouthBottomOffset;
        final estimatedMouthHeight = noseToBottomMouthDistance * 0.45;
        mouthTopY = mouthBottomY - estimatedMouthHeight.toInt();
        mouthCenterY = mouthBottomY - (estimatedMouthHeight / 2).toInt();

        _paintLogThrottled(
            '[FacePainter] 鼻底を使用した計算: noseY=${noseBasePos.y}, bottomMouthY=${bottomPos.y}, mouthHeight=$estimatedMouthHeight');
      } else {
        mouthBottomY = bottomPos.y;
        final mouthHeight = mouthWidth ~/ 3;
        mouthTopY = mouthBottomY - mouthHeight;
        mouthCenterY = mouthBottomY - mouthHeight ~/ 2;
        debugPrint('[FacePainter] フォールバック計算: topY=$mouthTopY, centerY=$mouthCenterY, bottomY=$mouthBottomY');
      }

      // 実際のランドマークの位置をログ出力
      debugPrint(
          '[FacePainter] ランドマーク位置: left=(${leftPos.x},${leftPos.y}), right=(${rightPos.x},${rightPos.y}), bottom=(${bottomPos.x},${bottomPos.y})');

      // 口の幅と実際の高さを計算
      final actualMouthHeight = bottomPos.y - mouthTopY;
      debugPrint(
          '[FacePainter] 口の形状: 中心($mouthCenterX,$mouthCenterY), 幅($mouthWidth), topY=$mouthTopY, bottomY=$bottomPos.y, 実際の高さ=$actualMouthHeight');

      // 笑っているかどうかを判定（口の幅が高さの2倍以上なら笑っている）
      final isSmiling = mouthWidth > actualMouthHeight * 2.0;
      debugPrint('[FacePainter] 笑顔判定: isSmiling=$isSmiling (幅=$mouthWidth, 高さ=$actualMouthHeight)');

      // MediaPipe風の詳細な唇の描画（滑らかなカーブ）
      // 上唇の輪郭（V字型に中央が下がる）
      final upperLipPoints = <Offset>[];

      // 笑っている場合とそうでない場合で異なるV字型の深さを適用
      final vDepth = isSmiling ? actualMouthHeight * 0.3 : actualMouthHeight * 0.5;
      debugPrint('[FacePainter] V字型の深さ: $vDepth (笑顔=$isSmiling)');

      // 上唇は中央部が下がるV字型（ランドマークのbottomPos.yを使用して正確な位置を計算）
      for (int i = 0; i <= 10; i++) {
        final t = i / 10.0;
        final x = leftPos.x.toDouble() + (rightPos.x.toDouble() - leftPos.x.toDouble()) * t;
        // V字型のカーブ（実際の口の高さを使用、bottomPos.yから上方向へ上がるように計算）
        final curve = vDepth * 4 * (t - 0.5) * (t - 0.5);
        final y = bottomPos.y.toDouble() - actualMouthHeight + curve;
        upperLipPoints.add(_scalePoint(x.toInt(), y.toInt(), size));
      }

      // 上唇の点線を描画（進行度に応じて）
      final upperLipProgress = mouthProgress;
      final upperLipSegments = (upperLipPoints.length - 1).toDouble();
      for (int i = 0; i < upperLipPoints.length - 1; i++) {
        final segmentProgress = ((i + 1) / upperLipSegments) * upperLipProgress;
        if (segmentProgress <= 0) break;
        final segmentDrawProgress = (segmentProgress - (i / upperLipSegments) * upperLipProgress).clamp(0.0, 1.0);
        if (segmentDrawProgress > 0) {
          _drawDashedLineWithProgress(
              canvas, upperLipPoints[i], upperLipPoints[i + 1], segmentDrawProgress, paint, shadowPaint);
        }
      }

      // 下唇の輪郭（中央が軽く上がる緩やかなアーチ、bottomPos.yを基準に）
      final lowerLipPoints = <Offset>[];

      // 笑っている場合、下唇のアーチをより上げる
      final archHeight = isSmiling ? actualMouthHeight * 0.35 : actualMouthHeight * 0.2;
      debugPrint('[FacePainter] アーチの高さ: $archHeight (笑顔=$isSmiling)');

      for (int i = 0; i <= 10; i++) {
        final t = i / 10.0;
        final x = leftPos.x.toDouble() + (rightPos.x.toDouble() - leftPos.x.toDouble()) * t;
        // 緩やかなアーチ（実際のbottomPos.yを使用、中央部が上がる）
        final curve = archHeight * 4 * (t - 0.5) * (t - 0.5);
        final y = bottomPos.y.toDouble() - curve;
        lowerLipPoints.add(_scalePoint(x.toInt(), y.toInt(), size));
      }

      // 下唇の点線を描画（進行度に応じて）
      final lowerLipProgress = mouthProgress;
      final lowerLipSegments = (lowerLipPoints.length - 1).toDouble();
      for (int i = 0; i < lowerLipPoints.length - 1; i++) {
        final segmentProgress = ((i + 1) / lowerLipSegments) * lowerLipProgress;
        if (segmentProgress <= 0) break;
        final segmentDrawProgress = (segmentProgress - (i / lowerLipSegments) * lowerLipProgress).clamp(0.0, 1.0);
        if (segmentDrawProgress > 0) {
          _drawDashedLineWithProgress(
              canvas, lowerLipPoints[i], lowerLipPoints[i + 1], segmentDrawProgress, paint, shadowPaint);
        }
      }

      final lipDescription = isSmiling ? '笑顔（上唇V字型浅め、下唇アーチ型高め）' : '通常（上唇V字型、下唇アーチ型）';
      debugPrint('[FacePainter] MediaPipe風の唇の描画: $lipDescription');

      // 口の開口部を示す水平な点線（実際のランドマークのy座標を使用、進行度に応じて）
      if (mouthProgress >= 1.0) {
        final actualMouthCenterY = (mouthTopY + bottomPos.y) ~/ 2;
        final openingStart = _scalePoint(leftPos.x, actualMouthCenterY, size);
        final openingEnd = _scalePoint(rightPos.x, actualMouthCenterY, size);
        _drawDashedLineWithProgress(canvas, openingStart, openingEnd, mouthProgress, paint, shadowPaint);
      }

      debugPrint('[FacePainter] 口の描画が完了しました。');
    } else {
      debugPrint('[FacePainter] 口のランドマークが不足しています。');
    }
  }

  /// ✅ 修正: MLKitのPoint型に対応（dynamic型で受け取る）
  void _drawContourWithProgress(
    Canvas canvas,
    List points,
    double progress,
    Paint paint,
    Paint shadowPaint,
    Size size,
  ) {
    if (points.isEmpty) return;

    final path = Path();
    final shadowPath = Path();

    // 進捗に応じて描画するポイント数を制限
    final progressPoints = (points.length * progress).round();
    final pointsToDraw = points.take(progressPoints).toList();

    if (pointsToDraw.isNotEmpty) {
      // ✅ 修正: MLKitのPoint型からx, yを取得
      final firstX = (pointsToDraw.first as dynamic).x;
      final firstY = (pointsToDraw.first as dynamic).y;
      final firstPoint = _scalePoint(firstX, firstY, size);
      path.moveTo(firstPoint.dx, firstPoint.dy);
      shadowPath.moveTo(firstPoint.dx, firstPoint.dy);

      for (int i = 1; i < pointsToDraw.length; i++) {
        // ✅ 修正: MLKitのPoint型からx, yを取得
        final pointX = (pointsToDraw[i] as dynamic).x;
        final pointY = (pointsToDraw[i] as dynamic).y;
        final scaledPoint = _scalePoint(pointX, pointY, size);
        path.lineTo(scaledPoint.dx, scaledPoint.dy);
        shadowPath.lineTo(scaledPoint.dx, scaledPoint.dy);
      }
    }

    // 影を描画
    canvas.drawPath(shadowPath, shadowPaint);
    // メインの線を描画
    canvas.drawPath(path, paint);
  }

  /// 点線で輪郭を描画
  /// ✅ 修正: MLKitのPoint型に対応（dynamic型で受け取る）
  void _drawDashedContourWithProgress(
    Canvas canvas,
    List points,
    double progress,
    Paint paint,
    Paint shadowPaint,
    Size size,
  ) {
    if (points.isEmpty) return;

    // 進捗に応じて描画するポイント数を制限
    final progressPoints = (points.length * progress).round();
    final pointsToDraw = points.take(progressPoints).toList();

    if (pointsToDraw.length < 2) return;

    // ダッシュのパターン: 点線をより見やすく（線を長めに、空白を短めに）
    const double dashLength = 4.0;
    const double dashGap = 3.0;

    for (int i = 0; i < pointsToDraw.length - 1; i++) {
      // ✅ 修正: MLKitのPoint型からx, yを取得（dynamic型に対応）
      final startX = (pointsToDraw[i] as dynamic).x;
      final startY = (pointsToDraw[i] as dynamic).y;
      final endX = (pointsToDraw[i + 1] as dynamic).x;
      final endY = (pointsToDraw[i + 1] as dynamic).y;

      final startPoint = _scalePoint(startX, startY, size);
      final endPoint = _scalePoint(endX, endY, size);

      final dx = endPoint.dx - startPoint.dx;
      final dy = endPoint.dy - startPoint.dy;
      final distance = math.sqrt(dx * dx + dy * dy);

      if (distance == 0) continue;

      final unitX = dx / distance;
      final unitY = dy / distance;

      double drawn = 0;
      while (drawn < distance) {
        final dashStart = math.min(drawn, distance);
        final dashEnd = math.min(drawn + dashLength, distance);

        final dashStartX = startPoint.dx + unitX * dashStart;
        final dashStartY = startPoint.dy + unitY * dashStart;
        final dashEndX = startPoint.dx + unitX * dashEnd;
        final dashEndY = startPoint.dy + unitY * dashEnd;

        // 影を描画
        canvas.drawLine(
          Offset(dashStartX, dashStartY),
          Offset(dashEndX, dashEndY),
          shadowPaint,
        );

        // メインの線を描画
        canvas.drawLine(
          Offset(dashStartX, dashStartY),
          Offset(dashEndX, dashEndY),
          paint,
        );

        drawn += dashLength + dashGap;
      }
    }
  }

  /// 点線で2点間を描画
  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint, Paint shadowPaint) {
    _drawDashedLineWithProgress(canvas, start, end, 1.0, paint, shadowPaint);
  }

  /// 点線で2点間を進行度に応じて描画
  void _drawDashedLineWithProgress(
      Canvas canvas, Offset start, Offset end, double progress, Paint paint, Paint shadowPaint) {
    const double dashLength = 4.0;
    const double dashGap = 3.0;

    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    if (distance == 0 || progress <= 0) return;

    final unitX = dx / distance;
    final unitY = dy / distance;

    // 進行度に応じた最大距離
    final maxDistance = distance * progress;

    double drawn = 0;
    while (drawn < maxDistance) {
      final dashStart = math.min(drawn, maxDistance);
      final dashEnd = math.min(drawn + dashLength, maxDistance);

      final dashStartX = start.dx + unitX * dashStart;
      final dashStartY = start.dy + unitY * dashStart;
      final dashEndX = start.dx + unitX * dashEnd;
      final dashEndY = start.dy + unitY * dashEnd;

      canvas.drawLine(Offset(dashStartX, dashStartY), Offset(dashEndX, dashEndY), shadowPaint);
      canvas.drawLine(Offset(dashStartX, dashStartY), Offset(dashEndX, dashEndY), paint);

      drawn += dashLength + dashGap;
    }
  }

  /// 点線で二次ベジェ曲線を描画
  void _drawDashedQuadraticBezier(
      Canvas canvas, Offset start, Offset control, Offset end, Paint paint, Paint shadowPaint) {
    const int segments = 10; // 曲線を細かく分割
    const double dashLength = 3.0;
    const double dashGap = 2.0;

    for (int i = 0; i < segments; i++) {
      final t1 = i / segments;
      final t2 = (i + 1) / segments;

      // ベジェ曲線の座標を計算
      final p1 = Offset(
        (1 - t1) * (1 - t1) * start.dx + 2 * (1 - t1) * t1 * control.dx + t1 * t1 * end.dx,
        (1 - t1) * (1 - t1) * start.dy + 2 * (1 - t1) * t1 * control.dy + t1 * t1 * end.dy,
      );
      final p2 = Offset(
        (1 - t2) * (1 - t2) * start.dx + 2 * (1 - t2) * t2 * control.dx + t2 * t2 * end.dx,
        (1 - t2) * (1 - t2) * start.dy + 2 * (1 - t2) * t2 * control.dy + t2 * t2 * end.dy,
      );

      // この線分を点線で描画
      final dx = p2.dx - p1.dx;
      final dy = p2.dy - p1.dy;
      final distance = math.sqrt(dx * dx + dy * dy);

      if (distance == 0) continue;

      final unitX = dx / distance;
      final unitY = dy / distance;

      double drawn = 0;
      while (drawn < distance) {
        final dashStart = math.min(drawn, distance);
        final dashEnd = math.min(drawn + dashLength, distance);

        final dashStartX = p1.dx + unitX * dashStart;
        final dashStartY = p1.dy + unitY * dashStart;
        final dashEndX = p1.dx + unitX * dashEnd;
        final dashEndY = p1.dy + unitY * dashEnd;

        canvas.drawLine(Offset(dashStartX, dashStartY), Offset(dashEndX, dashEndY), shadowPaint);
        canvas.drawLine(Offset(dashStartX, dashStartY), Offset(dashEndX, dashEndY), paint);

        drawn += dashLength + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // アニメーション中は常に再描画
  }
}
