/// 性格診断のエントリーポイント（最終強制版）
/// Web では bytes 版を使用。モバイルでは File / bytes 両対応。
/// E2E 時（?e2e=1）はサーバーを呼ばず固定結果を返す。

import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/services/server_personality_service.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';

/// E2E用の固定診断結果
PersonalityTreeDiagnosisResult _e2eMockResult() {
  return PersonalityTreeDiagnosisResult(
    personalityType: 1,
    personalityTypeName: 'E2E固定タイプ（協調的リーダー型）',
    personalityDescription: 'E2E固定結果：診断フローのUI検証用',
    hasError: false,
    warnings: [],
    layerResults: const {},
    layerValues: const {},
    layerReasons: const {},
    decisionFlow: const [],
    evidence: const {},
  );
}

/// 性格診断を実行（bytes 版・Web/モバイル共通）
Future<PersonalityTreeDiagnosisResult> runDiagnosisBytes(List<int> bytes, String filename) async {
  if (E2E.isEnabled) {
    await Future.delayed(const Duration(milliseconds: 300));
    return _e2eMockResult();
  }
  print("🔥🔥🔥 RUN_DIAGNOSIS_BYTES_CALLED 🔥🔥🔥");
  try {
    final result = await ServerPersonalityService.diagnoseFromServerBytes(bytes, filename);
    if (result == null) throw Exception("STOP_HERE_SERVER_INFERENCE_REQUIRED: サーバー推論がnullを返しました");
    print("🔥🔥🔥 サーバー推論成功: タイプ=${result.personalityType} 🔥🔥🔥");
    return result;
  } catch (e) {
    print("🔥🔥🔥 サーバー推論エラー: $e 🔥🔥🔥");
    throw Exception("STOP_HERE_SERVER_INFERENCE_REQUIRED: $e");
  }
}

/// 性格診断を実行（File 版・モバイル用）
Future<PersonalityTreeDiagnosisResult> runDiagnosis(io.File imageFile) async {
  if (E2E.isEnabled) {
    await Future.delayed(const Duration(milliseconds: 300));
    return _e2eMockResult();
  }
  print("🔥🔥🔥 RUN_DIAGNOSIS_CALLED 🔥🔥🔥");
  try {
    final result = await ServerPersonalityService.diagnoseFromServer(imageFile);
    if (result == null) throw Exception("STOP_HERE_SERVER_INFERENCE_REQUIRED: サーバー推論がnullを返しました");
    print("🔥🔥🔥 サーバー推論成功: タイプ=${result.personalityType} 🔥🔥🔥");
    return result;
  } catch (e) {
    print("🔥🔥🔥 サーバー推論エラー: $e 🔥🔥🔥");
    throw Exception("STOP_HERE_SERVER_INFERENCE_REQUIRED: $e");
  }
}
