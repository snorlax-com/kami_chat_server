import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../utils/preview_transform.dart';

class FaceOverlayPainter extends CustomPainter {
  final List<Face> faces;
  final PreviewTransform transform;
  final Rect guideRect;
  final bool debug;

  FaceOverlayPainter({
    required this.faces,
    required this.transform,
    required this.guideRect,
    this.debug = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ガイド枠（常に表示）
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.orange.withOpacity(0.9);

    canvas.drawRRect(
      RRect.fromRectAndRadius(guideRect, const Radius.circular(16)),
      guidePaint,
    );

    // デバッグ：Painter生存確認
    if (debug) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.greenAccent;
      canvas.drawRect(const Rect.fromLTWH(12, 12, 40, 40), p);
    }

    // 顔枠
    final facePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.lightBlueAccent.withOpacity(0.95);

    for (final face in faces) {
      final r = transform.mapRect(face.boundingBox);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(12)),
        facePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) {
    return oldDelegate.faces != faces || oldDelegate.guideRect != guideRect || oldDelegate.debug != debug;
  }
}
