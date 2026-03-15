import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/models/face_data_model.dart';

/// データ保存サービス（SQLite + SharedPreferences）
class StorageService {
  static const String _baselineKey = 'baseline_face';
  static const String _historyKey = 'fortune_history_list_v2';

  /// 基礎相（baseline）を保存
  static Future<void> saveBaseline(FaceData faceData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baselineKey, faceData.toJsonString());
  }

  /// 基礎相を取得
  static Future<FaceData?> getBaseline() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_baselineKey);
    if (jsonString == null) return null;
    try {
      return FaceData.fromJsonString(jsonString);
    } catch (e) {
      print('[StorageService] Error loading baseline: $e');
      return null;
    }
  }

  /// 基礎相が存在するか確認
  static Future<bool> hasBaseline() async {
    final baseline = await getBaseline();
    return baseline != null;
  }

  /// 運勢結果を保存（SharedPreferences配列）
  static Future<void> saveFortuneResult(FortuneResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? <String>[];
    list.add(jsonEncode(result.toJson()));
    await prefs.setStringList(_historyKey, list);
  }

  /// 全履歴を取得
  static Future<List<FortuneResult>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? <String>[];
    final results = list
        .map((s) {
          try {
            return FortuneResult.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<FortuneResult>()
        .toList();
    results.sort((a, b) => b.date.compareTo(a.date));
    return results;
  }

  /// 指定期間の履歴を取得
  static Future<List<FortuneResult>> getHistoryByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final all = await getHistory();
    return all
        .where((r) =>
            r.date.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
            r.date.isBefore(end.add(const Duration(milliseconds: 1))))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// 今日の運勢を取得
  static Future<FortuneResult?> getTodayFortune() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));

    final results = await getHistoryByDateRange(start, end);
    return results.isNotEmpty ? results.first : null;
  }

  /// 週次データを取得（過去7日間）
  static Future<List<FortuneResult>> getWeeklyData() async {
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 7));
    return await getHistoryByDateRange(start, end);
  }

  /// 月次データを取得（過去30日間）
  static Future<List<FortuneResult>> getMonthlyData() async {
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: 30));
    return await getHistoryByDateRange(start, end);
  }

  /// 神ごとの降臨回数を取得
  static Future<Map<String, int>> getDeityCounts() async {
    final history = await getHistory();
    final counts = <String, int>{};
    for (final result in history) {
      counts[result.deity] = (counts[result.deity] ?? 0) + 1;
    }
    return counts;
  }

  /// 履歴をクリア（デバッグ用）
  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  /// 互換API（何もしない）
  static Future<void> close() async {}
}
