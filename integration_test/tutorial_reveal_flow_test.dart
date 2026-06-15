import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/core/integration_test_flags.dart';
import 'package:kami_face_oracle/main_runner_io.dart' as app;
import 'package:kami_face_oracle/testing/integration_test_seed.dart';

/// チュートリアル疑似撮影 → Reveal → 性格診断結果画面（クラッシュ・白画面の回帰テスト）。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('E2E疑似撮影後にクラッシュせず結果画面へ到達する', (WidgetTester tester) async {
    await IntegrationTestSeed.seedTutorialRevealFlow();
    expect(IntegrationTestFlags.cameraRoute, isTrue, reason: 'cameraRoute フラグが有効であること');
    expect(E2E.isEnabled, isTrue, reason: 'E2E モードが有効であること');
    await app.runAppAsync();
    await tester.pump();

    Object? capturedError;
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      capturedError ??= details.exception;
      oldHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);

    var sawCamera = false;
    var sawReveal = false;
    var sawResult = false;

    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 200));

      for (final label in ['Accept all', 'Reject non-essential', 'I am 18 or older']) {
        final f = find.text(label);
        if (f.evaluate().isNotEmpty) {
          await tester.tap(f.first);
          await tester.pump(const Duration(milliseconds: 400));
        }
      }

      sawCamera = sawCamera || find.byKey(const Key('e2e-camera-screen')).evaluate().isNotEmpty;
      sawReveal = sawReveal || find.byKey(const Key('e2e-result-screen')).evaluate().isNotEmpty;
      sawResult = sawResult ||
          find.text('性格診断結果').evaluate().isNotEmpty ||
          find.textContaining('ログインして詳細を見る').evaluate().isNotEmpty ||
          find.textContaining('E2E固定タイプ').evaluate().isNotEmpty;

      if (sawResult) break;
    }

    expect(capturedError, isNull, reason: 'Reveal/結果画面で FlutterError が発生しないこと');
    expect(sawReveal || sawResult, isTrue, reason: 'Reveal($sawReveal)または結果($sawResult)に到達すること');
    expect(sawResult, isTrue, reason: '性格診断結果画面まで到達すること');
    // カメラ画面は 800ms 程度で遷移するため、長い pump 1 回では検出できないことがある
    expect(sawCamera || sawReveal || sawResult, isTrue, reason: 'フロー途中のいずれかの画面に到達すること');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
