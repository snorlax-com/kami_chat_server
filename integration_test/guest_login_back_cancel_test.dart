import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kami_face_oracle/core/integration_test_flags.dart';
import 'package:kami_face_oracle/main_runner_io.dart' as app;
import 'package:kami_face_oracle/testing/integration_test_seed.dart';

/// 性格診断結果で「ログインして詳細を見る」→ Android 戻る → 処理中が解除されること。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ログイン処理中に戻ると処理中が解除され結果画面に留まる', (WidgetTester tester) async {
    await IntegrationTestSeed.seedTutorialRevealFlow();
    await app.runAppAsync();
    await tester.pump();

    var onResultPage = false;
    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      onResultPage = find.text('性格診断結果').evaluate().isNotEmpty ||
          find.byKey(const Key('guest-login-detail-button')).evaluate().isNotEmpty;
      if (onResultPage) break;
    }
    expect(onResultPage, isTrue, reason: '性格診断結果画面に到達すること');

    await IntegrationTestFlags.armGoogleSignInHangForTest();
    await tester.tap(find.byKey(const Key('guest-login-detail-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('処理中…'), findsOneWidget, reason: 'ログイン開始直後は処理中表示');

    expect(await tester.binding.handlePopRoute(), isTrue, reason: 'Android 戻るが PopScope で処理されること');

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.textContaining('ログインして詳細を見る').evaluate().isNotEmpty &&
          find.text('処理中…').evaluate().isEmpty) {
        break;
      }
    }

    expect(find.text('処理中…'), findsNothing, reason: '戻る後に処理中が残らないこと');
    expect(
      find.textContaining('ログインして詳細を見る'),
      findsOneWidget,
      reason: 'ログインボタンが再度押せる状態に戻ること',
    );
    expect(find.text('性格診断結果'), findsOneWidget, reason: '結果画面から勝手に離れないこと');
    expect(
      find.text('ログインせずに終了しますか？'),
      findsNothing,
      reason: 'ログインキャンセル時は終了確認ダイアログを出さないこと',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
