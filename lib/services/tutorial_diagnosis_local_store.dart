import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:kami_face_oracle/core/personality_tree_classifier.dart';

/// 端末内の最終チュートリアル診断（ホームから再表示用）
class TutorialDiagnosisLocalStore {
  TutorialDiagnosisLocalStore._();

  static const kResultJson = 'tutorial_diagnosis_result_json';
  static const kUnlocked = 'tutorial_diagnosis_unlocked';

  static Future<void> saveResultJson(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kResultJson, json);
  }

  static Future<void> setUnlocked(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kUnlocked, v);
  }

  static Future<bool> isUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kUnlocked) ?? false;
  }

  static Future<PersonalityTreeDiagnosisResult?> loadResult() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kResultJson);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PersonalityTreeDiagnosisResult.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasStoredResult() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kResultJson);
    return raw != null && raw.isNotEmpty;
  }
}
