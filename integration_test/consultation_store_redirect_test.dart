import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/main_runner_io.dart' as app;
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/testing/e2e_diagnostics.dart';
import 'package:kami_face_oracle/testing/integration_test_seed.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('券不足の送信でストアタブへ自動遷移する', (WidgetTester tester) async {
    E2EDiagnostics.reset();
    AppNavigation.storeForTicketsNavigateCount = 0;
    await IntegrationTestSeed.seedSubscribedWithNoTickets();
    expect(await ConsultationSubscriptionService.isActive(), isTrue);
    expect(await ConsultationTicketService.normalTickets(), 0);
    await app.runAppAsync();

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    // 起動・IAP 初期化・年齢確認を待つ
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byKey(const Key('consultation_send_button')).evaluate().isNotEmpty) {
        break;
      }
      if (find.text('あとで').evaluate().isNotEmpty) {
        await tester.tap(find.text('あとで').first);
        await tester.pump();
      }
    }

    expect(find.byKey(const Key('consultation_send_button')), findsOneWidget);

    final inputFinder = find.byKey(const Key('consultation_message_input'));
    final sendFinder = find.byKey(const Key('consultation_send_button'));
    await tester.ensureVisible(inputFinder);
    await tester.tap(inputFinder);
    await tester.pump();
    await tester.enterText(inputFinder, '統合テスト券不足');
    await tester.pump();
    await tester.ensureVisible(sendFinder);

    FilledButton? sendBtn;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (sendFinder.evaluate().isEmpty) continue;
      sendBtn = tester.widget<FilledButton>(sendFinder);
      if (sendBtn.onPressed != null) break;
    }
    expect(sendBtn?.onPressed, isNotNull, reason: '送信ボタンが有効になるまで待つ');
    sendBtn!.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byKey(const ValueKey<String>('main_tab_title_ストア')).evaluate().isNotEmpty) {
        break;
      }
      if (find.text('あとで').evaluate().isNotEmpty) {
        await tester.tap(find.text('あとで').first);
        await tester.pump();
      }
    }

    expect(E2EDiagnostics.sendPressed, greaterThan(0), reason: '送信ボタンが押されたこと');
    expect(
      E2EDiagnostics.insufficientTickets + AppNavigation.storeForTicketsNavigateCount,
      greaterThan(0),
      reason: 'send=${E2EDiagnostics.sendPressed} insufficient=${E2EDiagnostics.insufficientTickets} '
          'subPrompt=${E2EDiagnostics.subscriptionPrompt} storeNav=${AppNavigation.storeForTicketsNavigateCount}',
    );
    expect(
      find.byKey(const ValueKey<String>('main_tab_title_ストア')),
      findsOneWidget,
      reason: '券不足時に下部ナビのストアタブへ切り替わること',
    );
    expect(find.textContaining('質問券（通常）'), findsWidgets);
  });
}
