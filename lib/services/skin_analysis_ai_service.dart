/// Hugging Face AIモデルを使用した肌分析サービス
/// Python APIサーバー経由で診断を行います

import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:kami_face_oracle/features/consent/consent_service.dart';

/// AI診断結果
class SkinAIDiagnosisResult {
  final bool success;
  final String? topDiagnosis;
  final double? topScore;
  final List<DiagnosisItem>? allResults;
  final String? error;
  // 8つの詳細指標（0-100スコア）
  final Map<String, double>? metrics; // {'oiliness': 27.29, 'dryness': 88.40, ...}

  SkinAIDiagnosisResult({
    required this.success,
    this.topDiagnosis,
    this.topScore,
    this.allResults,
    this.error,
    this.metrics,
  });

  factory SkinAIDiagnosisResult.fromJson(Map<String, dynamic> json) {
    if (json['success'] == true) {
      final topResult = json['top_result'];
      final results = (json['results'] as List?)?.map((e) => DiagnosisItem.fromJson(e)).toList();

      // 8つの詳細指標を取得（サーバーからのmetricsフィールド）
      Map<String, double>? metrics;
      if (json['metrics'] != null) {
        final metricsMap = json['metrics'] as Map<String, dynamic>;
        metrics = metricsMap.map((key, value) => MapEntry(key, (value as num).toDouble()));
      }

      return SkinAIDiagnosisResult(
        success: true,
        topDiagnosis: topResult?['label'],
        topScore: topResult?['score']?.toDouble(),
        allResults: results,
        metrics: metrics,
      );
    } else {
      return SkinAIDiagnosisResult(
        success: false,
        error: json['error'] ?? '不明なエラー',
      );
    }
  }
}

/// 診断項目
class DiagnosisItem {
  final String label;
  final double score;
  final String percentage;

  DiagnosisItem({
    required this.label,
    required this.score,
    required this.percentage,
  });

  factory DiagnosisItem.fromJson(Map<String, dynamic> json) {
    return DiagnosisItem(
      label: json['label'] ?? '',
      score: (json['score'] ?? 0.0).toDouble(),
      percentage: json['percentage'] ?? '0%',
    );
  }
}

/// 肌分析AIサービス
class SkinAnalysisAIService {
  // APIサーバーのURL（サーバー側の/predictと同じURLを使用）
  static const String _defaultApiUrl = 'http://45.77.26.42:8000';

  String? _apiUrl;

  SkinAnalysisAIService({String? apiUrl}) {
    _apiUrl = apiUrl ?? _defaultApiUrl;
  }

  /// APIサーバーの状態を確認（リトライ機能付き）
  Future<bool> checkServerHealth({int maxRetries = 3}) async {
    int retryCount = 0;
    while (retryCount < maxRetries) {
      try {
        final url = Uri.parse('$_apiUrl/health');
        final response = await http.get(url).timeout(
              const Duration(seconds: 5),
            );

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          // サーバー側は {"status": "ok"} を返す
          return json['status'] == 'ok' || json['status'] == 'healthy';
        }

        // リトライ可能なステータスコードの場合
        if (response.statusCode >= 500 && retryCount < maxRetries - 1) {
          retryCount++;
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
          continue;
        }

        return false;
      } catch (e) {
        retryCount++;
        if (retryCount < maxRetries) {
          print('[SkinAnalysisAIService] サーバー接続エラー（リトライ ${retryCount}/$maxRetries）: $e');
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        } else {
          print('[SkinAnalysisAIService] サーバー接続エラー（最終）: $e');
          return false;
        }
      }
    }
    return false;
  }

  /// 画像ファイルからAI診断を実行（リトライ機能付き）
  Future<SkinAIDiagnosisResult> analyzeFromFile(io.File imageFile, {int maxRetries = 3}) async {
    int retryCount = 0;
    Exception? lastError;
    final sessionId = await ConsentService.instance.getOrCreateSessionId();
    while (retryCount < maxRetries) {
      try {
        final url = Uri.parse('$_apiUrl/analyze');
        final request = http.MultipartRequest('POST', url);
        request.headers['X-Consent-Session-ID'] = sessionId;
        request.files.add(
          await http.MultipartFile.fromPath('image', imageFile.path),
        );

        final response = await request.send().timeout(
              const Duration(seconds: 30),
            );

        if (response.statusCode == 200) {
          final responseBody = await response.stream.bytesToString();
          final json = jsonDecode(responseBody);
          return SkinAIDiagnosisResult.fromJson(json);
        } else {
          // リトライ可能なステータスコードの場合
          if (response.statusCode >= 500 && retryCount < maxRetries - 1) {
            retryCount++;
            print('[SkinAnalysisAIService] HTTP ${response.statusCode} エラー（リトライ ${retryCount}/$maxRetries）');
            await Future.delayed(Duration(milliseconds: 500 * retryCount));
            continue;
          }

          return SkinAIDiagnosisResult(
            success: false,
            error: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          );
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        retryCount++;

        if (retryCount < maxRetries) {
          print('[SkinAnalysisAIService] 分析エラー（リトライ ${retryCount}/$maxRetries）: $e');
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        } else {
          print('[SkinAnalysisAIService] 分析エラー（最終）: $e');
          return SkinAIDiagnosisResult(
            success: false,
            error: 'ネットワークエラーまたはタイムアウト: $e',
          );
        }
      }
    }

    return SkinAIDiagnosisResult(
      success: false,
      error: 'リトライ回数上限に達しました: ${lastError?.toString() ?? "不明なエラー"}',
    );
  }

  /// 画像のバイトデータからAI診断を実行（リトライ機能付き）
  /// 注意: サーバー側はmultipart/form-dataを期待しているため、一時ファイルを作成してanalyzeFromFileを使用
  Future<SkinAIDiagnosisResult> analyzeFromBytes(List<int> imageBytes, {int maxRetries = 3}) async {
    // 一時ファイルを作成してanalyzeFromFileを使用
    io.File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      tempFile = io.File('${tempDir.path}/skin_analysis_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(imageBytes);

      final result = await analyzeFromFile(tempFile, maxRetries: maxRetries);
      return result;
    } catch (e) {
      return SkinAIDiagnosisResult(
        success: false,
        error: '画像データの処理に失敗しました: $e',
      );
    } finally {
      // 一時ファイルを削除
      if (tempFile != null) {
        try {
          await tempFile.delete();
        } catch (e) {
          print('[SkinAnalysisAIService] 一時ファイル削除エラー: $e');
        }
      }
    }
  }

  /// API URLを設定（Remote Configから取得した値を使用可能）
  void setApiUrl(String url) {
    _apiUrl = url;
  }
}

/// 診断ラベルの日本語翻訳
class DiagnosisLabelTranslator {
  static String translate(String label) {
    final translations = {
      'melanocytic_Nevi': '色素性母斑（ほくろ）',
      'actinic_keratoses': '光線角化症',
      'benign_keratosis-like_lesions': '良性角化症様病変',
      'melanoma': '悪性黒色腫',
      'basal_cell_carcinoma': '基底細胞癌',
      'benign': '良性',
      'malignant': '悪性',
      'akiec': '光線角化症',
      'bcc': '基底細胞癌',
      'bkl': '良性角化症様病変',
      'df': '皮膚線維腫',
      'mel': '悪性黒色腫',
      'nv': '色素性母斑',
      'vasc': '血管病変',
    };

    return translations[label] ?? label;
  }

  static String getDescription(String label) {
    final descriptions = {
      'melanocytic_Nevi': '一般的な「ほくろ」と呼ばれる良性の色素性病変です',
      'actinic_keratoses': '長期的な紫外線曝露により生じる前癌病変の可能性があります',
      'benign_keratosis-like_lesions': '良性の角化症様の病変です',
      'melanoma': '注意が必要な皮膚がんの一種です',
      'basal_cell_carcinoma': '最も一般的なタイプの皮膚がんです',
    };

    return descriptions[label] ?? '';
  }
}
