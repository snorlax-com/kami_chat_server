// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:kami_face_oracle/web/web_camera_types.dart';

/// Web 専用: getUserMedia + video 要素でカメラを制御。
class WebCameraController {
  WebCameraController() {
    _ready = false;
    _lastError = null;
  }

  static bool get isSupported => true;

  bool _ready = false;
  WebCameraError? _lastError;
  html.MediaStream? _stream;
  html.VideoElement? _video;
  static const String _logPrefix = '[WebCamera]';

  bool get isReady => _ready;
  WebCameraError? get lastError => _lastError;

  /// 安全に secure context かどうか取得（未対応環境では true 扱い）
  static bool _getIsSecureContext() {
    try {
      final v = js_util.getProperty(html.window, 'isSecureContext');
      return v == true;
    } catch (_) {
      return true;
    }
  }

  /// getUserMedia の例外を WebCameraError に変換
  static WebCameraError _errorFromDomException(html.DomException e) {
    final name = e.name.toLowerCase();
    if (name.contains('notallowed') || name.contains('permission')) return WebCameraError.permissionDenied;
    if (name.contains('notfound')) return WebCameraError.notFound;
    if (name.contains('notreadable')) return WebCameraError.notReadable;
    if (name.contains('overconstrained')) return WebCameraError.overconstrained;
    if (name.contains('security')) return WebCameraError.notSecureContext;
    return WebCameraError.unknown;
  }

  /// カメラ起動。videoElementId は既に DOM に存在する video 要素の id。
  Future<void> start(String videoElementId) async {
    stop();
    _ready = false;
    _lastError = null;

    if (!_getIsSecureContext()) {
      _lastError = WebCameraError.notSecureContext;
      debugPrint('$_logPrefix not secure context');
      return;
    }

    final video = html.document.getElementById(videoElementId) as html.VideoElement?;
    if (video == null) {
      _lastError = WebCameraError.unknown;
      debugPrint('$_logPrefix video element not found: $videoElementId');
      return;
    }
    _video = video;

    // iOS 対策: ユーザー操作から start する前提。autoplay に頼らない。
    video.autoplay = false;
    video.setAttribute('playsinline', 'true');
    video.muted = true;

    final constraints = <String, dynamic>{
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
      },
      'audio': false,
    };

    final mediaDevices = js_util.getProperty(html.window.navigator, 'mediaDevices');
    if (mediaDevices == null) {
      _lastError = WebCameraError.unknown;
      debugPrint('$_logPrefix mediaDevices is null');
      return;
    }

    try {
      final streamObj = await js_util.promiseToFuture<dynamic>(
        js_util.callMethod(mediaDevices, 'getUserMedia', [js_util.jsify(constraints)]),
      );
      _stream = streamObj as html.MediaStream;
      video.srcObject = _stream;
      await video.play();
      _ready = true;
      _lastError = null;
      debugPrint('$_logPrefix start ok');
    } catch (e) {
      if (e is html.DomException) {
        _lastError = _errorFromDomException(e);
        debugPrint('$_logPrefix getUserMedia error: ${e.name} ${e.message}');
      } else {
        _lastError = WebCameraError.unknown;
        debugPrint('$_logPrefix getUserMedia error: $e');
      }

      // フォールバック: enumerateDevices で front を探して deviceId 指定で再試行
      try {
        final devicesPromise = js_util.callMethod(mediaDevices, 'enumerateDevices', []);
        final devicesList = await js_util.promiseToFuture<dynamic>(devicesPromise);
        final list =
            (js_util.dartify(devicesList) as List).where((d) => (d is Map && (d['kind'] == 'videoinput'))).toList();
        debugPrint('$_logPrefix device list count: ${list.length}');
        String? deviceId;
        for (final d in list) {
          final m = d is Map ? d : <String, dynamic>{};
          final label = ((m['label'] ?? '') as String).toLowerCase();
          if (label.contains('front') || label.contains('user') || label.contains('face')) {
            deviceId = m['deviceId'] as String?;
            break;
          }
        }
        deviceId ??= list.isNotEmpty && list.first is Map ? (list.first as Map)['deviceId'] as String? : null;
        if (deviceId != null && deviceId.isNotEmpty) {
          debugPrint('$_logPrefix retry with deviceId');
          final fallbackConstraints = <String, dynamic>{
            'video': {
              'deviceId': {'exact': deviceId},
              'width': {'ideal': 720},
              'height': {'ideal': 720}
            },
            'audio': false,
          };
          final streamObj = await js_util.promiseToFuture<dynamic>(
            js_util.callMethod(mediaDevices, 'getUserMedia', [js_util.jsify(fallbackConstraints)]),
          );
          _stream = streamObj as html.MediaStream;
          video.srcObject = _stream;
          await video.play();
          _ready = true;
          _lastError = null;
          debugPrint('$_logPrefix start ok (fallback)');
        }
      } catch (_) {
        debugPrint('$_logPrefix fallback failed');
      }
    }
  }

  void stop() {
    try {
      _stream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    _stream = null;
    if (_video != null) {
      _video!.srcObject = null;
      _video = null;
    }
    _ready = false;
    debugPrint('$_logPrefix stop');
  }

  static const int _maxLongEdge = 640;
  static const int _fallbackLongEdge = 320;
  static const double _serverJpegQuality = 0.85;

  /// 現在の video フレームを JPEG bytes で返す。複数サイズ・リトライで実機でも成功しやすくする。
  Future<List<int>> captureJpegBytes({double quality = 0.92}) async {
    if (!_ready || _video == null) throw StateError('Camera not ready');
    final v = _video!;
    int w = v.videoWidth;
    int h = v.videoHeight;
    if (w == 0 || h == 0) {
      for (int i = 0; i < 25; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        w = v.videoWidth;
        h = v.videoHeight;
        if (w > 0 && h > 0) break;
      }
      if (w == 0 || h == 0) throw StateError('Video not ready (wait timeout)');
    }
    final q = (quality >= 0 && quality <= 1) ? quality : _serverJpegQuality;

    Future<List<int>> doCaptureAt(int longEdge, double qualityVal) async {
      final maxEdge = w > h ? w : h;
      final cw = maxEdge > longEdge ? (w * (longEdge / maxEdge)).round().clamp(1, 2048) : w;
      final ch = maxEdge > longEdge ? (h * (longEdge / maxEdge)).round().clamp(1, 2048) : h;
      final canvas = html.CanvasElement(width: cw, height: ch);
      final ctx = canvas.context2D;
      try {
        ctx.drawImageScaled(v, 0, 0, cw, ch);
      } catch (_) {
        ctx.drawImage(v, 0, 0);
      }
      final blob = await canvas.toBlob('image/jpeg', qualityVal);
      return await _readBlobAsBytes(blob);
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final longEdge = attempt == 0 ? _maxLongEdge : (attempt == 1 ? _fallbackLongEdge : _maxLongEdge);
        final qVal = attempt == 2 ? 0.7 : q;
        final bytes = await doCaptureAt(longEdge, qVal);
        debugPrint('$_logPrefix capture: longEdge=$longEdge bytes=${bytes.length} attempt=${attempt + 1}');
        return bytes;
      } catch (e) {
        debugPrint('$_logPrefix capture attempt ${attempt + 1} failed: $e');
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 400));
        } else {
          rethrow;
        }
      }
    }
    throw StateError('capture failed after retry');
  }

  static Future<List<int>> _readBlobAsBytes(html.Blob blob) async {
    final reader = html.FileReader();
    reader.readAsArrayBuffer(blob);
    await reader.onLoadEnd.first;
    final result = reader.result;
    if (result == null) throw StateError('FileReader failed');
    final buf = result as ByteBuffer;
    return Uint8List.view(buf).toList();
  }
}
