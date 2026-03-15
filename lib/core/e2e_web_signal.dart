import 'e2e_web_signal_stub.dart' if (dart.library.html) 'e2e_web_signal_web.dart' as impl;

/// E2E 時に結果画面表示を Web の window に通知（Playwright が待機する用）。
/// 非 Web では no-op。
void signalE2EResultShown() => impl.signalE2EResultShown();
