import 'package:flutter/material.dart';

/// Web 以外では表示しない
Widget buildWebShutterCameraView() {
  return const SizedBox.shrink();
}

/// Web 以外では no-op
void registerWebShutterViewFactory() {}
