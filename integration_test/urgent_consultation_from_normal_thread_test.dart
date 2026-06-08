import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/main_runner_io.dart' as app;
import 'package:kami_face_oracle/testing/e2e_diagnostics.dart';
import 'package:kami_face_oracle/testing/integration_test_consultation_mail_stub.dart';
import 'package:kami_face_oracle/testing/integration_test_seed.dart';

Future<void> _dismissOverlays(WidgetTester tester) async {
  for (final label in ['あとで', '閉じる', 'キャンセル', 'OK']) {
    final finder = find.text(label);
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
}

Future<void> _waitForConsultationReady(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    await _dismissOverlays(tester);
    final hasSend = find.byKey(const Key('consultation_send_button')).evaluate().isNotEmpty;
    final hasTickets = find.textContaining('至急券').evaluate().isNotEmpty;
    if (hasSend && hasTickets) return;
  }
  fail('占い相談画面が準備できませんでした');
}

Future<void> _selectUrgent(WidgetTester tester) async {
  final selector = find.byKey(const Key('consultation-send-kind-selector'));
  expect(selector, findsOneWidget);
  await tester.ensureVisible(selector);
  await tester.pump();
  final urgentSegment = find.descendant(
    of: selector,
    matching: find.text('至急'),
  );
  await tester.tap(urgentSegment.first, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapSendWithText(WidgetTester tester, String text) async {
  final inputFinder = find.byKey(const Key('consultation_message_input'));
  final sendFinder = find.byKey(const Key('consultation_send_button'));
  await tester.ensureVisible(inputFinder);
  await tester.tap(inputFinder);
  await tester.pump();
  await tester.enterText(inputFinder, text);
  await tester.pump();

  FilledButton? sendBtn;
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (sendFinder.evaluate().isEmpty) continue;
    sendBtn = tester.widget<FilledButton>(sendFinder);
    if (sendBtn.onPressed != null) break;
  }
  expect(sendBtn?.onPressed, isNotNull);
  sendBtn!.onPressed!();
  await tester.pump();
}

Future<void> _waitForCapturedSendBody(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    await _dismissOverlays(tester);
    if (IntegrationTestConsultationMailStub.lastSendBody != null) return;
  }
  fail('メール送信ペイロードがキャプチャされませんでした');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('通常スレッド上で至急選択時はメール用別IDで至急送信し画面は同一', (WidgetTester tester) async {
    E2EDiagnostics.reset();
    IntegrationTestConsultationMailStub.install();
    await IntegrationTestSeed.seedForUrgentFromNormalThread();
    await app.runAppAsync();

    await tester.pump();
    await _waitForConsultationReady(tester);

    expect(find.text('通常スレッドの1通目'), findsOneWidget);
    await _selectUrgent(tester);
    await _tapSendWithText(tester, 'エミュレーター至急テスト_通常スレッドから');
    await _waitForCapturedSendBody(tester);

    final body = IntegrationTestConsultationMailStub.lastSendBody!;
    expect(body['urgent'], isTrue);
    expect(body['consultationType'], ConsultationMailType.priorityGuidance);
    expect(
      IntegrationTestConsultationMailStub.lastSendChatId,
      isNot(IntegrationTestSeed.normalThreadChatId),
    );
    expect(find.text('通常スレッドの1通目'), findsOneWidget);
    expect(find.textContaining('エミュレーター至急テスト_通常スレッドから'), findsOneWidget);
    expect(
      find.textContaining('至急相談を送信しました。通常の相談と同じ画面に表示されます'),
      findsOneWidget,
    );
  });
}
