import 'dart:convert';
import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;
import 'package:http/http.dart' as http;
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/features/consent/consent_service.dart';

/// サーバーで性格診断を実行するサービス
class ServerPersonalityService {
  // サーバーURL（環境変数や設定ファイルから読み込むことも可能）
  static const String serverUrl = 'http://45.77.26.42:8000';
  static const String apiKey = ''; // 必要に応じて設定

  /// 撮影後・正面判定。同意不要。OK なら is_frontal: true、NG なら reasons / suggestion を返す。
  static Future<Map<String, dynamic>> validateFace(List<int> jpegBytes) async {
    final uri = Uri.parse('$serverUrl/validate_face');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/octet-stream'},
          body: jpegBytes,
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('正面判定がタイムアウトしました。'),
        );

    if (res.statusCode != 200) {
      if (res.statusCode == 503) {
        throw Exception('正面判定は現在利用できません。');
      }
      if (res.statusCode == 400) {
        throw Exception('画像が不正です。もう一度撮影してください。');
      }
      throw Exception('正面判定エラー: ${res.statusCode}');
    }

    final map = json.decode(res.body) as Map<String, dynamic>;
    if (map['ok'] != true || !map.containsKey('result')) {
      throw Exception('正面判定の応答形式が不正です。');
    }
    return map['result'] as Map<String, dynamic>;
  }

  /// 画像 bytes をサーバーに送信して性格診断を実行（Web / 共通用）
  static Future<PersonalityTreeDiagnosisResult?> diagnoseFromServerBytes(
    List<int> bytes,
    String filename,
  ) async {
    try {
      print('[ServerPersonalityService] サーバーに画像を送信中（bytes）... size=${bytes.length} filename=$filename');
      final sessionId = await ConsentService.instance.getOrCreateSessionId();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/predict'),
      );
      request.headers['X-Consent-Session-ID'] = sessionId;
      if (apiKey.isNotEmpty) request.headers['X-API-Key'] = apiKey;
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename.isEmpty ? 'upload.jpg' : filename,
      ));
      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('サーバーへのリクエストがタイムアウトしました'),
          );
      final response = await http.Response.fromStream(streamedResponse);
      print('[ServerPersonalityService] 応答: status=${response.statusCode} bodyLength=${response.body.length}');
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        final serverInference = jsonData['server_inference'] as bool?;
        if (serverInference != true) throw Exception('サーバー推論が確認できませんでした。');
        print('[ServerPersonalityService] ✅ サーバー推論成功（bytes）');
        return _convertServerResponseToResult(jsonData);
      }
      if (response.statusCode == 403) {
        print('[ServerPersonalityService] ❌ 403 Consent required');
        throw Exception('CONSENT_REQUIRED');
      }
      final msg = _statusCodeToMessage(response.statusCode);
      print('[ServerPersonalityService] ❌ サーバーエラー: ${response.statusCode}');
      throw Exception(msg);
    } catch (e, stackTrace) {
      if (e is TimeoutException) {
        print('[ServerPersonalityService] ❌ タイムアウト');
      } else {
        print('[ServerPersonalityService] ❌ エラー: $e');
        print('[ServerPersonalityService] スタック: ${stackTrace?.toString().split("\n").take(5).join("\n")}');
      }
      rethrow;
    }
  }

  static String _statusCodeToMessage(int code) {
    if (code == 400) return 'リクエストが不正です。';
    if (code == 403) return '同意が未登録です。最初に生体データ同意で「I Agree」をタップしてください。';
    if (code == 404) return 'サーバーが見つかりません。';
    if (code >= 500 && code < 600) return 'サーバーエラーです。しばらく待ってから再撮影してください。';
    return 'サーバーエラー: $code。ネットワークを確認するか、時間をおいて再撮影してください。';
  }

  /// 画像をサーバーに送信して性格診断を実行（モバイル用・File 利用）
  static Future<PersonalityTreeDiagnosisResult?> diagnoseFromServer(
    io.File imageFile,
  ) async {
    try {
      print('[ServerPersonalityService] 診断を送信中…');
      final sessionId = await ConsentService.instance.getOrCreateSessionId();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/predict'),
      );
      request.headers['X-Consent-Session-ID'] = sessionId;
      if (apiKey.isNotEmpty) request.headers['X-API-Key'] = apiKey;
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          imageFile.path,
        ),
      );

      // リクエストを送信
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('サーバーへのリクエストがタイムアウトしました');
        },
      );

      // レスポンスを読み込み
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        print('[ServerPersonalityService] ✅ サーバーからの応答を受信');
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        print('[ServerPersonalityService] レスポンスキー: ${jsonData.keys.toList()}');
        print('[ServerPersonalityService] 完全なレスポンス: ${jsonEncode(jsonData)}');

        // 🔴 必須チェック: server_inference フラグを確認
        final serverInference = jsonData['server_inference'] as bool?;
        if (serverInference != true) {
          print('[ServerPersonalityService] ❌ サーバー推論が確認できませんでした: server_inference=$serverInference');
          throw Exception('サーバー推論が確認できませんでした。server_inferenceフラグがtrueではありません。');
        }

        final requestId = jsonData['request_id'] as String?;
        final elapsedSec = jsonData['elapsed_sec'] as double?;
        print(
            '[ServerPersonalityService] ✅ サーバー推論確認: request_id=$requestId, elapsed=${elapsedSec?.toStringAsFixed(3)}s');

        // サーバーからの結果を PersonalityTreeDiagnosisResult に変換
        final result = _convertServerResponseToResult(jsonData);

        // 詳細ページに直接遷移する場合はここで処理
        // （現在は結果を返すだけ）

        return result;
      } else if (response.statusCode == 403) {
        print('[ServerPersonalityService] ❌ 403 Consent required');
        throw Exception('CONSENT_REQUIRED');
      } else {
        print('[ServerPersonalityService] ❌ サーバーエラー: ${response.statusCode}');
        print('[ServerPersonalityService] レスポンス: ${response.body}');
        throw Exception('サーバーエラー: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      print('[ServerPersonalityService] ❌ エラー: $e');
      print('[ServerPersonalityService] スタックトレース: ${stackTrace.toString().split("\n").take(5).join("\n")}');
      // 🔴 フォールバック禁止: エラー時は例外を再スロー
      rethrow;
    }
  }

  /// サーバーからのレスポンスを PersonalityTreeDiagnosisResult に変換
  static PersonalityTreeDiagnosisResult _convertServerResponseToResult(
    Map<String, dynamic> jsonData,
  ) {
    // Layer結果を取得（サーバーからのL1-L9を日本語形式に変換）
    final layerResults = <String, String>{};
    final layerNames = {
      'L1': '第1層（眉の角度）',
      'L2': '第2層（眉の形状）',
      'L3': '第3層（眉の濃さ）',
      'L4': '第4層（眉の長さ）',
      'L5': '第5層（眉間の幅）',
      'L6': '第6層（眉と目の距離）',
      'L7': '第7層（目の形状）',
      'L8': '第8層（口の大きさ）',
      'L9': '第9層（顔の型）',
    };

    for (int i = 1; i <= 9; i++) {
      final layerKey = 'L$i';
      if (jsonData.containsKey(layerKey)) {
        final layerName = layerNames[layerKey] ?? layerKey;
        layerResults[layerName] = jsonData[layerKey].toString();
        print('[ServerPersonalityService] $layerName: ${jsonData[layerKey]}');
      }
    }

    // 性格タイプを取得
    final personalityType = jsonData['personality_type'] as int? ?? 1;
    final personalityTypeName = jsonData['personality_type_name'] as String? ?? 'タイプ$personalityType';

    // 柱情報を取得（サーバーから来る場合）
    final pillarId = jsonData['pillar_id'] as String?;
    final pillarName = jsonData['pillar_name'] as String?;
    final pillarTitle = jsonData['pillar_title'] as String?;
    final characterImage = jsonData['character_image'] as String?;
    final illustrationImage = jsonData['illustration_image'] as String?;

    // 柱情報をログ出力
    if (pillarId != null) {
      print('[ServerPersonalityService] 柱情報: $pillarId ($pillarTitle)');
      print('[ServerPersonalityService] キャラクター画像: $characterImage');
    }

    // Layer値を数値化（サーバーからは文字列で来るため、必要に応じて変換）
    final layerValues = <String, double>{};
    for (final entry in layerResults.entries) {
      // 簡易的な変換（実際の値はサーバー側で計算済み）
      layerValues[entry.key] = 0.5; // デフォルト値
    }

    // デバッグログ: 変換後の結果を確認
    print('[ServerPersonalityService] ✅ サーバー推論結果を変換完了');
    print('[ServerPersonalityService] personalityType: $personalityType ($personalityTypeName)');
    print('[ServerPersonalityService] layerResults数: ${layerResults.length}');
    for (final entry in layerResults.entries) {
      print('[ServerPersonalityService]   ${entry.key}: ${entry.value}');
    }

    // PersonalityTreeDiagnosisResult を作成
    return PersonalityTreeDiagnosisResult(
      personalityType: personalityType,
      personalityTypeName: personalityTypeName,
      personalityDescription: _getPersonalityDescription(personalityType),
      layerResults: layerResults,
      layerValues: layerValues,
      layerReasons: <String, String>{}, // サーバーからは理由が来ないため空
      hasError: false,
      warnings: [],
    );
  }

  /// 性格タイプの説明を取得（新しい15タイプ対応）
  static String _getPersonalityDescription(int type) {
    // 性格タイプの説明（新しい15タイプ）
    final descriptions = {
      1: '協調的リーダー型: 周囲との調和を保ちながら物事を前へ進める力を持つ、穏やかなリーダー。',
      2: '情熱的革新者型: 新しい発想と大胆な行動力を持つ革新者。変化を恐れません。',
      3: '柔軟な適応者型: 環境に応じて自分を調整できる、柔らかな適応の天才。',
      4: '情熱的表現者型: 感情豊かで魅力的、多くの人に愛される表現者タイプ。',
      5: '堅実な計画者型: 責任感と慎重さが際立つ、信頼度の高い実務タイプ。',
      6: '社交的楽天家型: 明るくポジティブで、人を笑顔にする力を持つ社交タイプ。',
      7: 'バランス型実務家: 主張しすぎず、控えすぎず。どんな環境でも穏やかに安定して働けるタイプ。',
      8: '情熱的リーダー型: 意志が強く、目標に向かって全力で進むカリスマ型リーダー。',
      9: '積極的開拓者型: 未知の領域に最初に踏み込むパイオニア。',
      10: '複雑な個性型: 複数の性質が同居し、状況によって別人格のように振る舞うタイプ。',
      11: '冷静な観察者型: 一歩引いた視点で物事を観察し、冷静に判断できる知的タイプ。',
      12: '寛大な支援者型: 人の成長を心から願い、支えることに喜びを感じるタイプ。',
      13: '内向的芸術家型: 繊細な感受性と独自の美意識を持つ、内面的クリエイター。',
      14: '情熱的革新者（協調寄り）: 情熱と創造力に溢れながら、人との調和も大切にするタイプ。',
      15: '冷静な完璧主義者型: 論理性・集中力・精度を極限まで高めようとする、孤高の研究者タイプ。',
    };
    return descriptions[type] ?? 'タイプ$type の性格診断結果です。';
  }

  /// サーバーのヘルスチェック
  static Future<bool> checkServerHealth() async {
    try {
      print('[ServerPersonalityService] ヘルスチェック: $serverUrl/health');
      final response = await http
          .get(
        Uri.parse('$serverUrl/health'),
      )
          .timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('サーバーヘルスチェックがタイムアウトしました');
        },
      );

      final isHealthy = response.statusCode == 200;
      print('[ServerPersonalityService] ヘルスチェック結果: ${isHealthy ? "✅ 正常" : "❌ 異常"} (${response.statusCode})');
      return isHealthy;
    } catch (e) {
      print('[ServerPersonalityService] ヘルスチェックエラー: $e');
      return false;
    }
  }
}

/// TimeoutException クラス
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
