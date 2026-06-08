import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/ui/pages/personality_diagnosis_result_page.dart';
import 'package:kami_face_oracle/ui/pages/reveal_page.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';
import 'package:kami_face_oracle/ui/widgets/tutorial_guest_exit_scope.dart';

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
  testWidgets('TutorialGuestExitScope は Router なし MaterialApp でクラッシュしない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TutorialGuestExitScope(
          enabled: true,
          tutorialFlow: true,
          child: const Scaffold(body: Text('scoped-child')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('scoped-child'), findsOneWidget);
  });

  testWidgets('RevealPage チュートリアルモードが Router なしでビルドできる', (tester) async {
    final diagnosis = _mockDiagnosis();
    await tester.pumpWidget(
      MaterialApp(
        home: RevealPage(
          features: FaceFeatures(0.5, 0.5, 0.5, 0.5, 0.5),
          isTutorial: true,
          personalityDiagnosisResult: diagnosis,
          tutorialImageBytes: Uint8List.fromList(E2E.minimalJpegBytes),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('e2e-result-screen')), findsOneWidget);
    // RevealPage のタイムアウト Timer を消化
    await tester.pump(const Duration(seconds: 13));
  });

  testWidgets('PersonalityDiagnosisResultPage チュートリアルフローがビルドできる', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalityDiagnosisResultPage(
          diagnosisResult: _mockDiagnosis(),
          isTutorialFlow: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('性格診断結果'), findsOneWidget);
    expect(find.textContaining('ログインして詳細を見る'), findsOneWidget);
  });
}
