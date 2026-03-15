// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

/// Web カメラ用 video 要素の id（WebCameraController.start に渡す）
const String kWebCameraVideoElementId = 'web_camera_video';

/// Platform view を登録（初回のみ）。video は playsinline / muted、autoplay は付けない（iOS 対策）。
void registerWebCameraViewFactory() {
  ui_web.platformViewRegistry.registerViewFactory(
    'web-camera-view',
    (int viewId) {
      final div = html.DivElement()
        ..id = 'web_camera_container_$viewId'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'relative'
        ..style.overflow = 'hidden'
        ..style.backgroundColor = 'black';

      final video = html.VideoElement()
        ..id = kWebCameraVideoElementId
        ..autoplay = false
        ..setAttribute('playsinline', 'true')
        ..muted = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.objectPosition = 'center';

      div.append(video);
      return div;
    },
  );
}

Widget buildWebCameraView() {
  return const HtmlElementView(
    viewType: 'web-camera-view',
  );
}
