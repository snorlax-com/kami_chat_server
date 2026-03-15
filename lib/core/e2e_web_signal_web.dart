import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// E2E 結果画面表示を window にセット（Playwright が waitForFunction で待つ）
void signalE2EResultShown() {
  js_util.setProperty(html.window, 'e2eResultShown', true);
}
