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

void main() {
  testWidgets('ログイン処理中の戻るで処理中が解除される', (tester) async {
    await IntegrationTestFlags.armGoogleSignInHangForTest();
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

    await tester.tap(find.byKey(const Key('guest-login-detail-button')));
    await tester.pump();
    expect(find.text('処理中…'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('処理中…'), findsNothing);
    expect(find.textContaining('ログインして詳細を見る'), findsOneWidget);
  });

  testWidgets('保存診断でもログイン処理中の戻るで処理中が解除される', (tester) async {
    await IntegrationTestFlags.armGoogleSignInHangForTest();
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalityDiagnosisResultPage(
          diagnosisResult: _mockDiagnosis(),
          isTutorialFlow: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('guest-login-detail-button')));
    await tester.pump();
    expect(find.text('処理中…'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('処理中…'), findsNothing);
    expect(find.byKey(const Key('guest-exit-without-login')), findsNothing);
    expect(find.textContaining('ログインして詳細を見る'), findsOneWidget);
  });
}
