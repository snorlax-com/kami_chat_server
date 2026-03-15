// Stub for non-Web platforms (no dart:html)

/// Web 以外では未対応
class WebShutterBridge {
  static bool get isSupported => false;
  static bool get isScriptLoaded => false;

  static Future<void> init(String videoElementId, String canvasElementId) async {
    throw UnsupportedError('WebShutterBridge is only supported on Web');
  }

  static String getShutterStateJson() {
    throw UnsupportedError('WebShutterBridge is only supported on Web');
  }

  static void startAutoShutterLoop(String onFireCallbackName) {
    throw UnsupportedError('WebShutterBridge is only supported on Web');
  }

  static void stopAutoShutterLoop() {
    throw UnsupportedError('WebShutterBridge is only supported on Web');
  }

  static void setOnCaptureCallback(void Function(String base64DataUrl)? callback) {}
  static void setOnCaptureErrorCallback(void Function(String message)? callback) {}
}
