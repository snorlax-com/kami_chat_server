import 'package:flutter_test/flutter_test.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/services/tutorial_diagnosis_local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

PersonalityTreeDiagnosisResult _sample() {
  return PersonalityTreeDiagnosisResult(
    personalityType: 3,
    personalityTypeName: 'テスト型',
    personalityDescription: 'テスト',
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('ログインせず終了後は自動チュートリアルをスキップする', () async {
    expect(await TutorialDiagnosisLocalStore.shouldSkipAutoTutorialLaunch(), isFalse);
    await TutorialDiagnosisLocalStore.markGuestExitedWithoutLogin();
    expect(await TutorialDiagnosisLocalStore.shouldSkipAutoTutorialLaunch(), isTrue);
    expect(await TutorialDiagnosisLocalStore.didGuestExitWithoutLogin(), isTrue);
  });

  test('診断結果保存後は自動チュートリアルをスキップする', () async {
    await TutorialDiagnosisLocalStore.persistTutorialResult(_sample());
    expect(await TutorialDiagnosisLocalStore.shouldSkipAutoTutorialLaunch(), isTrue);
    expect(await TutorialDiagnosisLocalStore.hasStoredResult(), isTrue);
  });

  test('サブスク再診断準備で消費フラグがクリアされる', () async {
    await TutorialDiagnosisLocalStore.markGuestExitedWithoutLogin();
    await TutorialDiagnosisLocalStore.prepareForRetakeDiagnosis();
    expect(await TutorialDiagnosisLocalStore.shouldSkipAutoTutorialLaunch(), isFalse);
  });
}
