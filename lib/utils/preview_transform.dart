import 'dart:ui';

class PreviewTransform {
  final Size imageSize;
  final Size viewSize;
  final bool isFrontCamera;

  late final double scale;
  late final Offset offset;

  PreviewTransform({
    required this.imageSize,
    required this.viewSize,
    required this.isFrontCamera,
  }) {
    final sx = viewSize.width / imageSize.width;
    final sy = viewSize.height / imageSize.height;
    scale = sx > sy ? sx : sy;

    final fittedW = imageSize.width * scale;
    final fittedH = imageSize.height * scale;

    offset = Offset(
      (viewSize.width - fittedW) / 2.0,
      (viewSize.height - fittedH) / 2.0,
    );
  }

  Offset _mapPoint(Offset p) {
    var x = p.dx * scale + offset.dx;
    var y = p.dy * scale + offset.dy;

    if (isFrontCamera) {
      x = viewSize.width - x; // mirror補正
    }
    return Offset(x, y);
  }

  Rect mapRect(Rect r) {
    final p1 = _mapPoint(Offset(r.left, r.top));
    final p2 = _mapPoint(Offset(r.right, r.bottom));

    final left = p1.dx < p2.dx ? p1.dx : p2.dx;
    final right = p1.dx > p2.dx ? p1.dx : p2.dx;
    final top = p1.dy < p2.dy ? p1.dy : p2.dy;
    final bottom = p1.dy > p2.dy ? p1.dy : p2.dy;

    return Rect.fromLTRB(left, top, right, bottom);
  }
}
