// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// Web: JS 自動シャッターエンジンとのブリッジ
class WebShutterBridge {
  static bool get isSupported => true;

  /// MediaPipe スクリプトが window にアタッチされているか
  static bool get isScriptLoaded {
    try {
      final fn = js_util.getProperty(html.window, 'initShutterEngine');
      return fn != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> init(String videoElementId, String canvasElementId) async {
    final promise = js_util.callMethod(html.window, 'initShutterEngine', [videoElementId, canvasElementId]);
    await js_util.promiseToFuture(promise);
  }

  static String getShutterStateJson() {
    final result = js_util.callMethod(html.window, 'getShutterStateJson', []);
    return result as String;
  }

  static void startAutoShutterLoop(String onFireCallbackName) {
    js_util.callMethod(html.window, 'startAutoShutterLoop', [onFireCallbackName]);
  }

  static void stopAutoShutterLoop() {
    js_util.callMethod(html.window, 'stopAutoShutterLoop', []);
  }

  static void setOnCaptureCallback(void Function(String base64DataUrl)? callback) {
    if (callback == null) {
      js_util.setProperty(html.window, 'onWebShutterCapture', null);
      return;
    }
    js_util.setProperty(html.window, 'onWebShutterCapture', js_util.allowInterop((String s) {
      callback(s);
    }));
  }

  static void setOnCaptureErrorCallback(void Function(String message)? callback) {
    if (callback == null) {
      js_util.setProperty(html.window, 'onWebShutterCaptureError', null);
      return;
    }
    js_util.setProperty(html.window, 'onWebShutterCaptureError', js_util.allowInterop((String s) {
      callback(s);
    }));
  }
}
