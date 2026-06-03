import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/config/play_billing_products.dart';
import 'package:kami_face_oracle/main_runner_io.dart' as app;
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/testing/e2e_diagnostics.dart';
import 'package:kami_face_oracle/testing/integration_test_seed.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('券不足→ストア→テスト購入後に占い相談タブへ戻る', (WidgetTester tester) async {
    E2EDiagnostics.reset();
    AppNavigation.storeForTicketsNavigateCount = 0;
    AppNavigation.pendingReturnToConsultationAfterTicketStore = false;
    await IntegrationTestSeed.seedSubscribedWithNoTickets();
    await app.runAppAsync();

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

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

    final inputFinder = find.byKey(const Key('consultation_message_input'));
    final sendFinder = find.byKey(const Key('consultation_send_button'));
    await tester.ensureVisible(inputFinder);
    await tester.tap(inputFinder);
    await tester.pump();
    await tester.enterText(inputFinder, '購入後に相談へ戻るテスト');
    await tester.pump();

    final sendBtn = tester.widget<FilledButton>(sendFinder);
    expect(sendBtn.onPressed, isNotNull);
    sendBtn.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byKey(const ValueKey<String>('main_tab_title_ストア')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey<String>('main_tab_title_ストア')), findsOneWidget);
    expect(AppNavigation.pendingReturnToConsultationAfterTicketStore, isTrue);

    final buyKey = Key('store_buy_${PlayBillingProducts.ticketNormal600}');
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.byKey(buyKey).evaluate().isNotEmpty) break;
    }
    expect(find.byKey(buyKey), findsOneWidget);

    await tester.tap(find.byKey(buyKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final confirmButtons = find.text('テスト購入');
    expect(confirmButtons, findsWidgets);
    await tester.tap(confirmButtons.last);
    await tester.pump();

    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byKey(const ValueKey<String>('main_tab_title_占い相談')).evaluate().isNotEmpty &&
          find.byKey(const Key('consultation_send_button')).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(
      find.byKey(const ValueKey<String>('main_tab_title_占い相談')),
      findsOneWidget,
      reason: 'テスト購入後に占い相談タブへ戻ること',
    );
    expect(
      find.byKey(const ValueKey<String>('main_tab_title_ストア')),
      findsNothing,
      reason: 'ストアタブのまま残らないこと',
    );
    expect(find.byKey(const Key('consultation_send_button')), findsOneWidget);
  });
}
