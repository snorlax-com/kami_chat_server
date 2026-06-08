import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:kami_face_oracle/core/personality_tree_classifier.dart';

/// 端末内の最終チュートリアル診断（ホームから再表示用）
class TutorialDiagnosisLocalStore {
  TutorialDiagnosisLocalStore._();

  static const kResultJson = 'tutorial_diagnosis_result_json';
  static const kUnlocked = 'tutorial_diagnosis_unlocked';
  static const kGuestExitedWithoutLogin = 'tutorial_guest_exited_without_login_v1';
  /// チュートリアル性格診断を1回消費した（ログイン有無・サーバー保存成否に関わらず）。
  static const kConsumed = 'tutorial_diagnosis_consumed_v1';

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

  /// 初回チュートリアル自動起動をスキップすべきか（診断済み・ログインせず終了・消費済み）。
  static Future<bool> shouldSkipAutoTutorialLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(kConsumed) == true) return true;
    if (prefs.getBool(kGuestExitedWithoutLogin) == true) return true;
    final raw = prefs.getString(kResultJson);
    return raw != null && raw.isNotEmpty;
  }

  /// チュートリアル結果を端末に保存し、再診断不可にする。
  static Future<void> persistTutorialResult(PersonalityTreeDiagnosisResult result) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kResultJson, jsonEncode(result.toJson()));
    await prefs.setBool(kConsumed, true);
  }

  static Future<void> markTutorialConsumed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kConsumed, true);
  }

  /// ログインせずチュートリアル結果画面を終了した（性格診断は一度きりの扱い）。
  static Future<void> markGuestExitedWithoutLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kGuestExitedWithoutLogin, true);
    await prefs.setBool(kConsumed, true);
  }

  static Future<bool> didGuestExitWithoutLogin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kGuestExitedWithoutLogin) ?? false;
  }

  static Future<void> clearGuestExitedWithoutLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kGuestExitedWithoutLogin);
  }

  /// サブスク加入後の性格診断やり直し用に、前回の端末保存結果をクリアする。
  static Future<void> prepareForRetakeDiagnosis() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kResultJson);
    await prefs.setBool(kUnlocked, false);
    await prefs.remove(kConsumed);
    await clearGuestExitedWithoutLogin();
  }
}
