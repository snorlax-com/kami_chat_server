import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';

class Storage {
  static const _historyKey = 'deity_history';
  static const _pointKey = 'point';
  static const _dailyPointKey = 'daily_point_date'; // 日次ポイント付与日付
  static const _baselineNeutralKey = 'baseline_neutral_image';
  static const _baselineSmilingKey = 'baseline_smiling_image';
  static const _baselineNeutralFeaturesKey = 'baseline_neutral_features';
  static const _baselineSmilingFeaturesKey = 'baseline_smiling_features';
  static const _baselineSkinKey = 'baseline_skin_analysis';
  static const _lastSkinKey = 'last_skin_analysis';
  static const _dailyKey = 'beauty_daily_snapshots';

  static Future<void> addHistory(Map<String, dynamic> item) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_historyKey) ?? [];
    list.add(jsonEncode(item));
    await sp.setStringList(_historyKey, list);
  }

  static Future<List<Map<String, dynamic>>> getHistory() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_historyKey) ?? [];
    return list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  static Future<int> addPoint(int delta) async {
    final sp = await SharedPreferences.getInstance();
    final p = sp.getInt(_pointKey) ?? 0;
    final next = p + delta;
    await sp.setInt(_pointKey, next);
    return next;
  }

  static Future<int> getPoint() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_pointKey) ?? 0;
  }

  /// 1日1回限定のポイント付与
  /// 戻り値: 付与したポイント数（既に付与済みの場合は0）
  static Future<int> addDailyPoint(int pointAmount) async {
    final sp = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final lastDate = sp.getString(_dailyPointKey);

    // 今日既に付与済みかチェック
    if (lastDate == todayStr) {
      return 0; // 既に付与済み
    }

    // ポイントを付与
    final current = sp.getInt(_pointKey) ?? 0;
    final next = current + pointAmount;
    await sp.setInt(_pointKey, next);
    await sp.setString(_dailyPointKey, todayStr); // 付与日付を記録

    return pointAmount;
  }

  /// 今日の日次ポイント付与済みか確認
  static Future<bool> hasReceivedDailyPoint() async {
    final sp = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final lastDate = sp.getString(_dailyPointKey);
    return lastDate == todayStr;
  }

  // Baseline画像（真顔・笑顔）を保存
  static Future<void> saveBaselineImage(String type, String imagePath, FaceFeatures? features) async {
    final sp = await SharedPreferences.getInstance();
    final key = type == 'neutral' ? _baselineNeutralKey : _baselineSmilingKey;
    final featuresKey = type == 'neutral' ? _baselineNeutralFeaturesKey : _baselineSmilingFeaturesKey;
    await sp.setString(key, imagePath);
    if (features != null) {
      await sp.setString(
          featuresKey,
          jsonEncode({
            'smile': features.smile,
            'eyeOpen': features.eyeOpen,
            'gloss': features.gloss,
            'straightness': features.straightness,
            'claim': features.claim,
          }));
    }
  }

  // Baseline画像のパスを取得
  static Future<String?> getBaselineImagePath(String type) async {
    final sp = await SharedPreferences.getInstance();
    final key = type == 'neutral' ? _baselineNeutralKey : _baselineSmilingKey;
    return sp.getString(key);
  }

  // Baseline特徴を取得
  static Future<FaceFeatures?> getBaselineFeatures(String type) async {
    final sp = await SharedPreferences.getInstance();
    final featuresKey = type == 'neutral' ? _baselineNeutralFeaturesKey : _baselineSmilingFeaturesKey;
    final jsonStr = sp.getString(featuresKey);
    if (jsonStr == null) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return FaceFeatures(
        (map['smile'] as num).toDouble(),
        (map['eyeOpen'] as num).toDouble(),
        (map['gloss'] as num).toDouble(),
        (map['straightness'] as num).toDouble(),
        (map['claim'] as num).toDouble(),
      );
    } catch (e) {
      print('[Storage] Error parsing baseline features: $e');
      return null;
    }
  }

  // Baseline画像が保存されているか確認
  static Future<bool> hasBaselineImages() async {
    final neutral = await getBaselineImagePath('neutral');
    final smiling = await getBaselineImagePath('smiling');
    return neutral != null && smiling != null && File(neutral).existsSync() && File(smiling).existsSync();
  }

  // 肌分析結果（簡易Map）の保存/取得
  static Future<void> saveBaselineSkin(Map<String, dynamic> skin) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_baselineSkinKey, jsonEncode(skin));
  }

  static Future<Map<String, dynamic>?> getBaselineSkin() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_baselineSkinKey);
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLastSkin(Map<String, dynamic> skin) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_lastSkinKey, jsonEncode(skin));
  }

  static Future<Map<String, dynamic>?> getLastSkin() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_lastSkinKey);
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // 日次スナップ保存（beauty_score.json 相当をSPに蓄積）
  static Future<void> saveDailySnapshot(Map<String, dynamic> snap) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_dailyKey) ?? [];
    list.add(jsonEncode(snap));
    await sp.setStringList(_dailyKey, list);
  }

  static Future<List<Map<String, dynamic>>> getDailySnapshots() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_dailyKey) ?? [];
    return list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  // チュートリアル結果（選ばれた神のID）を保存
  static const _tutorialDeityKey = 'tutorial_deity_id';
  static Future<void> saveTutorialDeity(String deityId) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_tutorialDeityKey, deityId);
  }

  static Future<String?> getTutorialDeity() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_tutorialDeityKey);
  }
}
