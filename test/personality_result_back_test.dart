import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/core/integration_test_flags.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/ui/pages/personality_diagnosis_result_page.dart';

PersonalityTreeDiagnosisResult _mockDiagnosis() {
  return PersonalityTreeDiagnosisResult(
    personalityType: 6,
    personalityTypeName: 'テスト型',
    personalityDescription: 'テスト用',
    hasError: false,
    warnings: const [],
    layerResults: const {},
    layerValues: const {},
    layerReasons: const {},
    decisionFlow: const [],
    evidence: const {},
  );
}

Future<void> _openSavedResultPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PersonalityDiagnosisResultPage(
                        diagnosisResult: _mockDiagnosis(),
                        isTutorialFlow: false,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ホームから開いた結果は戻る矢印で pop できる', (tester) async {
    await _openSavedResultPage(tester);
    expect(find.text('性格診断結果'), findsOneWidget);

    await tester.tap(find.byKey(const Key('guest-result-back-button')));
    await tester.pumpAndSettle();

    expect(find.text('性格診断結果'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('保存診断の再表示ではログインせずに終了リンクは表示されない', (tester) async {
    await _openSavedResultPage(tester);
    expect(find.byKey(const Key('guest-exit-without-login')), findsNothing);
  });

  testWidgets('保存診断で戻る矢印からホームへ pop できる', (tester) async {
    await _openSavedResultPage(tester);
    await tester.tap(find.byKey(const Key('guest-result-back-button')));
    await tester.pumpAndSettle();

    expect(find.text('性格診断結果'), findsNothing);
    expect(find.text('ログインせずに終了しますか？'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('保存診断で2回目のログイン試行後もログインせずに終了できる', (tester) async {
    await IntegrationTestFlags.armGoogleSignInHangForTest();
    await _openSavedResultPage(tester);

    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.byKey(const Key('guest-login-detail-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('処理中…'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('処理中…'), findsNothing);
      expect(find.textContaining('ログインして詳細を見る'), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('guest-result-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('性格診断結果'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('チュートリアル結果の戻る矢印で終了確認ダイアログが出る', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalityDiagnosisResultPage(
          diagnosisResult: _mockDiagnosis(),
          isTutorialFlow: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('guest-result-back-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ログインせずに終了しますか？'), findsOneWidget);
  });
}
