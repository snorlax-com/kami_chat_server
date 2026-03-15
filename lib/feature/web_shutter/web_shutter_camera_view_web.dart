// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

/// Platform view を登録（Web 初回表示時に1回だけ呼ぶ）
void registerWebShutterViewFactory() {
  ui_web.platformViewRegistry.registerViewFactory(
    'web-shutter-view',
    (int viewId) {
      final div = html.DivElement()
        ..id = 'web_shutter_container_$viewId'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.position = 'relative'
        ..style.overflow = 'hidden'
        ..style.backgroundColor = 'black';

      // 内側ラッパー: 4:3 で画面を覆い、はみ出しは crop（細長く伸びない）
      final inner = html.DivElement()
        ..style.position = 'absolute'
        ..style.left = '50%'
        ..style.top = '50%'
        ..style.transform = 'translate(-50%, -50%)'
        ..style.minWidth = '100%'
        ..style.minHeight = '100%'
        ..style.aspectRatio = '4/3'
        ..style.width = 'auto'
        ..style.height = 'auto'
        ..style.maxWidth = 'none'
        ..style.maxHeight = 'none';

      // アスペクト比を保つ: video は cover で表示
      final video = html.VideoElement()
        ..id = 'web_shutter_video'
        ..setAttribute('autoplay', 'true')
        ..setAttribute('playsinline', 'true')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.objectPosition = 'center';

      // canvas は video と同じ領域に重ねる（ラッパー内なので伸びない）
      final canvas = html.CanvasElement()
        ..id = 'web_shutter_canvas'
        ..style.position = 'absolute'
        ..style.left = '0'
        ..style.top = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = 'none';

      inner.append(video);
      inner.append(canvas);
      div.append(inner);
      return div;
    },
  );
}

/// Web: video + canvas を埋め込んだ div の HtmlElementView
Widget buildWebShutterCameraView() {
  return const HtmlElementView(
    viewType: 'web-shutter-view',
  );
}
