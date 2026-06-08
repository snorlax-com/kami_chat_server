import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/core/integration_test_flags.dart';
import 'package:kami_face_oracle/main_runner_io.dart' as app;
import 'package:kami_face_oracle/testing/integration_test_seed.dart';

/// エミュレーター向けスモーク: 1 APK ビルドで主要フローを連続検証する。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> waitForResultPage(WidgetTester tester) async {
    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('性格診断結果').evaluate().isNotEmpty ||
          find.byKey(const Key('guest-login-detail-button')).evaluate().isNotEmpty) {
        return;
      }
    }
    fail('性格診断結果画面に到達しませんでした');
  }

  Future<void> bootstrapTutorialToResult(WidgetTester tester) async {
    await IntegrationTestSeed.seedTutorialRevealFlow();
    expect(IntegrationTestFlags.cameraRoute, isTrue);
    expect(E2E.isEnabled, isTrue);
    await app.runAppAsync();
    await tester.pump();

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
      sawResult = sawResult ||
          find.text('性格診断結果').evaluate().isNotEmpty ||
          find.textContaining('ログインして詳細を見る').evaluate().isNotEmpty;
      if (sawResult) return;
    }
    fail('チュートリアル結果画面に到達しませんでした');
  }

  testWidgets('① 疑似撮影→Reveal→性格診断結果', (tester) async {
    Object? capturedError;
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      capturedError ??= details.exception;
      oldHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);

    await bootstrapTutorialToResult(tester);
    expect(capturedError, isNull);
    expect(find.textContaining('ログインして詳細を見る'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('② ログイン処理中の戻るで処理中が解除される', (tester) async {
    await bootstrapTutorialToResult(tester);
    await waitForResultPage(tester);

    await IntegrationTestFlags.armGoogleSignInHangForTest();
    await tester.tap(find.byKey(const Key('guest-login-detail-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('処理中…'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.textContaining('ログインして詳細を見る').evaluate().isNotEmpty &&
          find.text('処理中…').evaluate().isEmpty) {
        break;
      }
    }

    expect(find.text('処理中…'), findsNothing);
    expect(find.textContaining('ログインして詳細を見る'), findsOneWidget);
    expect(find.text('性格診断結果'), findsOneWidget);
    expect(find.text('ログインせずに終了しますか？'), findsNothing);

    await tester.tap(find.byKey(const Key('guest-result-back-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ログインせずに終了しますか？'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('③ 戻る矢印→終了するでホームへ遷移', (tester) async {
    await bootstrapTutorialToResult(tester);
    await waitForResultPage(tester);

    await tester.tap(find.byKey(const Key('guest-result-back-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ログインせずに終了しますか？'), findsOneWidget);

    await tester.tap(find.text('終了する'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('性格診断結果').evaluate().isEmpty &&
          find.text('ログインせずに終了しますか？').evaluate().isEmpty) {
        break;
      }
    }

    expect(find.text('性格診断結果'), findsNothing);
    expect(find.text('ログインせずに終了しますか？'), findsNothing);
    // ホームタブ（占い相談 or ストア等）のいずれかが見えること
    final onHome = find.text('占い相談').evaluate().isNotEmpty ||
        find.text('ストア').evaluate().isNotEmpty ||
        find.text('ホーム').evaluate().isNotEmpty ||
        find.byType(BottomNavigationBar).evaluate().isNotEmpty;
    expect(onHome, isTrue, reason: '終了後に MainTabShell（ホーム）へ遷移すること');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('④ 終了確認ダイアログをAndroid戻るで閉じられる', (tester) async {
    await bootstrapTutorialToResult(tester);
    await waitForResultPage(tester);

    await tester.tap(find.byKey(const Key('guest-result-back-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ログインせずに終了しますか？'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ログインせずに終了しますか？'), findsNothing);
    expect(find.text('性格診断結果'), findsOneWidget);
    expect(find.textContaining('ログインして詳細を見る'), findsOneWidget);

    // busy 復旧後、再度戻る矢印でダイアログが出る
    await tester.tap(find.byKey(const Key('guest-result-back-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ログインせずに終了しますか？'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 3)));

  Future<void> exitTutorialToHome(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('guest-result-back-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ログインせずに終了しますか？'), findsOneWidget);
    await tester.tap(find.text('終了する'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('性格診断結果').evaluate().isEmpty &&
          find.text('ログインせずに終了しますか？').evaluate().isEmpty) {
        break;
      }
    }
  }

  testWidgets('⑤ 保存診断→2回目ログイン後もログインせずに終了できる', (tester) async {
    await bootstrapTutorialToResult(tester);
    await waitForResultPage(tester);
    await exitTutorialToHome(tester);

    final savedButton = find.text('保存された性格診断を開く');
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (savedButton.evaluate().isNotEmpty) break;
    }
    expect(savedButton, findsOneWidget);
    await tester.tap(savedButton);
    await waitForResultPage(tester);
    expect(find.byKey(const Key('guest-exit-without-login')), findsNothing);

    for (var attempt = 0; attempt < 2; attempt++) {
      await IntegrationTestFlags.armGoogleSignInHangForTest();
      await tester.tap(find.byKey(const Key('guest-login-detail-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('処理中…'), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('処理中…').evaluate().isEmpty) break;
      }
      expect(find.text('処理中…'), findsNothing);
    }

    await tester.tap(find.byKey(const Key('guest-result-back-button')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.text('性格診断結果').evaluate().isEmpty) break;
    }
    expect(find.text('性格診断結果'), findsNothing);
    expect(find.text('保存された性格診断を開く'), findsOneWidget);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
