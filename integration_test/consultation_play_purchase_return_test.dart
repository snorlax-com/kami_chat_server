import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/config/play_billing_products.dart';
import 'package:kami_face_oracle/main_runner_io.dart' as app;
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/testing/integration_test_seed.dart';

/// Play 課金ストリーム相当（IAP コールバック）でも占い相談へ戻ること。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('券不足→ストア→IAPコールバックで占い相談タブへ戻る', (WidgetTester tester) async {
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
    await tester.enterText(inputFinder, 'Playコールバック復帰テスト');
    await tester.pump();
    tester.widget<FilledButton>(sendFinder).onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byKey(const ValueKey<String>('main_tab_title_ストア')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(AppNavigation.pendingReturnToConsultationAfterTicketStore, isTrue);

    await ConsultationTicketService.addNormalTickets(1);
    IAPService.instance.onTicketsGranted?.call(
      1,
      PlayBillingProducts.ticketNormal600,
      isUrgent: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (find.byKey(const ValueKey<String>('main_tab_title_占い相談')).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(
      find.byKey(const ValueKey<String>('main_tab_title_占い相談')),
      findsOneWidget,
      reason: 'IAPコールバック後に占い相談タブへ戻ること',
    );
    expect(find.byKey(const ValueKey<String>('main_tab_title_ストア')), findsNothing);
  });
}
