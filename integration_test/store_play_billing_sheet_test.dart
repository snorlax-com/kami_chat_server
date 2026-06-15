import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/config/play_billing_products.dart';
import 'package:kami_face_oracle/main_runner_io.dart' as app;
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/testing/integration_test_seed.dart';

/// ストア購入タップで「テスト購入」ではなく Google Play 課金（launchBillingFlow）へ進むこと。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('券不足→ストア→Play課金起動（テスト購入ダイアログなし）', (WidgetTester tester) async {
    AppNavigation.pendingReturnToConsultationAfterTicketStore = false;
    await IntegrationTestSeed.seedForPlayBillingSheetTest();
    await app.runAppAsync();
    await ConsultationSubscriptionService.setActive(true);
    await ConsultationTicketService.setBalances(normal: 0, priority: 0);

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
    expect(find.byKey(const Key('consultation_send_button')), findsOneWidget);

    final inputFinder = find.byKey(const Key('consultation_message_input'));
    final sendFinder = find.byKey(const Key('consultation_send_button'));
    await tester.ensureVisible(inputFinder);
    await tester.enterText(inputFinder, 'Playボトムシート確認');
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
    expect(find.byKey(const ValueKey<String>('main_tab_title_ストア')), findsOneWidget);

    final buyKey = Key('store_buy_${PlayBillingProducts.ticketNormal600}');
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      if (find.byKey(buyKey).evaluate().isNotEmpty) break;
    }
    expect(find.byKey(buyKey), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(buyKey), 120);
    await tester.ensureVisible(find.byKey(buyKey));
    await tester.tap(find.byKey(buyKey), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.textContaining('ADB 直インストールのため Google Play 課金は使えません'),
      findsNothing,
      reason: 'INTEGRATION_TEST_FORCE_PLAY_BILLING 時は sideload テスト購入ダイアログを出さない',
    );
    expect(
      find.widgetWithText(AlertDialog, 'テスト購入'),
      findsNothing,
    );

    // Play 課金 UI はネイティブのため Flutter ツリーには出ない。起動待ち。
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  });
}
