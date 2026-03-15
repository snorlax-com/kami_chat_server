import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:kami_face_oracle/core/legal_config.dart';
import 'package:kami_face_oracle/features/consent/models/consent_record.dart';
import 'package:kami_face_oracle/features/consent/region_info.dart';
import 'package:kami_face_oracle/services/server_personality_service.dart';

/// Manages consent state, policy versioning, and consent logging (GDPR/BIPA-ready).
class ConsentService {
  ConsentService._();
  static final ConsentService instance = ConsentService._();

  static const _keyAgeConfirmed = 'consent_age_confirmed';
  static const _keyBiometricConsent = 'consent_biometric';
  static const _keyConsentPolicyVersions = 'consent_policy_versions';
  static const _keyConsentAt = 'consent_at_utc';
  static const _keyCookiePrefs = 'consent_cookie_preferences';
  static const _keyConsentLog = 'consent_log_entries';
  static const _keySessionId = 'consent_session_id';
  static const _keyCookieBannerShown = 'consent_cookie_banner_shown';
  static const _maxLogEntries = 500;

  /// Current required policy versions (bump to force re-consent).
  PolicyVersions get currentPolicyVersions => PolicyVersions(
        termsVersion: LegalConfig.termsVersion,
        privacyVersion: LegalConfig.privacyVersion,
        biometricVersion: LegalConfig.biometricVersion,
        aiNoticeVersion: LegalConfig.aiNoticeVersion,
        cookieVersion: LegalConfig.cookieVersion,
      );

  /// True if user has confirmed 18+ (or equivalent).
  Future<bool> isAgeConfirmed() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_keyAgeConfirmed) ?? false;
  }

  /// Set age confirmed and optionally log.
  Future<void> setAgeConfirmed(bool value, {String? region, String? sessionId}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyAgeConfirmed, value);
    if (value) {
      await _appendLog(ConsentRecord(
        timestampUtc: DateTime.now().toUtc(),
        regionCountry: region ?? 'unknown',
        policyVersions: currentPolicyVersions,
        consents: ConsentFlags(
            biometricExplicit: await isBiometricConsentGiven(),
            ageConfirmed: true,
            cookiePreferences: await getCookiePreferences()),
        source: 'app',
        sessionId: sessionId,
      ));
    }
  }

  /// Stored accepted policy versions (null if never consented).
  Future<PolicyVersions?> getStoredAcceptedVersions() async {
    final sp = await SharedPreferences.getInstance();
    final stored = sp.getString(_keyConsentPolicyVersions);
    if (stored == null) return null;
    try {
      final map = jsonDecode(stored) as Map<String, dynamic>;
      return PolicyVersions.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// True if explicit biometric consent has been given AND all accepted versions match current (re-consent when any policy changes).
  Future<bool> isBiometricConsentGiven() async {
    final sp = await SharedPreferences.getInstance();
    if (!(sp.getBool(_keyBiometricConsent) ?? false)) return false;
    final stored = await getStoredAcceptedVersions();
    if (stored == null) return false;
    return stored.matches(currentPolicyVersions);
  }

  /// Whether we need to show the age gate (first launch or never confirmed).
  Future<bool> needAgeGate() async {
    return !(await isAgeConfirmed());
  }

  /// Show biometric consent only when: no prior consent, or any policy version changed, or user withdrew.
  Future<bool> needBiometricConsent() async {
    return !(await isBiometricConsentGiven());
  }

  /// Can the user proceed to upload/capture face? (age + biometric consent, all versions match)
  Future<bool> canUseBiometricFeatures() async {
    final ageOk = await isAgeConfirmed();
    final bioOk = await isBiometricConsentGiven();
    return ageOk && bioOk;
  }

  /// Persistent session ID for server-side consent verification (audit-grade).
  Future<String> getOrCreateSessionId() async {
    final sp = await SharedPreferences.getInstance();
    var sid = sp.getString(_keySessionId);
    if (sid == null || sid.isEmpty) {
      sid = '${DateTime.now().millisecondsSinceEpoch}_${_randomString(12)}';
      await sp.setString(_keySessionId, sid);
    }
    return sid;
  }

  static String _randomString(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(len, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  /// Save biometric consent and persist policy versions + log. Uses getOrCreateSessionId() if sessionId not provided.
  Future<void> setBiometricConsent({
    required bool consent,
    required bool ageConfirmedInModal,
    required bool imageIsSelfOrPermission,
    required bool understandNotAdvice,
    String? region,
    String? sessionId,
  }) async {
    final sid = sessionId ?? await getOrCreateSessionId();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyBiometricConsent, consent);
    if (ageConfirmedInModal) await sp.setBool(_keyAgeConfirmed, true);
    await sp.setString(_keyConsentPolicyVersions, jsonEncode(currentPolicyVersions.toJson()));
    await sp.setString(_keyConsentAt, DateTime.now().toUtc().toIso8601String());

    final regionCountry = region ?? 'unknown';
    await _appendLog(ConsentRecord(
      timestampUtc: DateTime.now().toUtc(),
      regionCountry: regionCountry,
      policyVersions: currentPolicyVersions,
      consents: ConsentFlags(
          biometricExplicit: consent,
          ageConfirmed: ageConfirmedInModal || await isAgeConfirmed(),
          cookiePreferences: await getCookiePreferences()),
      source: 'app',
      sessionId: sid,
    ));
    await _syncConsentToServer(sid, regionCountry, consent);
  }

  /// Register consent on server so /predict and /analyze can verify (403 if missing).
  Future<void> _syncConsentToServer(String sessionId, String country, bool biometricExplicit) async {
    try {
      final uri = Uri.parse('${ServerPersonalityService.serverUrl}/consents/accept');
      final body = jsonEncode({
        'session_id': sessionId,
        'country': country,
        'region_group': regionGroupFromCountry(country),
        'accepted_terms_version': LegalConfig.termsVersion,
        'accepted_privacy_version': LegalConfig.privacyVersion,
        'accepted_biometric_version': LegalConfig.biometricVersion,
        'accepted_ai_version': LegalConfig.aiNoticeVersion,
        'accepted_cookie_version': LegalConfig.cookieVersion,
        'biometric_explicit': biometricExplicit,
      });
      final r = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        // 同期成功
      } else if (r.statusCode == 404 && kDebugMode) {
        // サーバーが同意APIを未実装の場合は静かに続行（本番サーバー更新前の互換）
        debugPrint('ConsentService: 同意API未実装のためスキップ');
      } else if (r.statusCode != 200 && kDebugMode) {
        print('ConsentService: sync to server failed ${r.statusCode} ${r.body}');
      }
    } catch (e) {
      if (kDebugMode) print('ConsentService: sync to server error $e');
    }
  }

  /// Whether cookie banner has been shown/completed (EU/UK strict).
  Future<bool> hasCookieBannerBeenShown() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_keyCookieBannerShown) ?? false;
  }

  Future<void> setCookieBannerShown() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyCookieBannerShown, true);
  }

  /// Cookie/tracking preferences (for web or future use).
  Future<Map<String, dynamic>?> getCookiePreferences() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_keyCookiePrefs);
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<void> setCookiePreferences(Map<String, dynamic>? prefs) async {
    final sp = await SharedPreferences.getInstance();
    if (prefs == null) {
      await sp.remove(_keyCookiePrefs);
    } else {
      await sp.setString(_keyCookiePrefs, jsonEncode(prefs));
    }
  }

  /// Append one consent log entry (keep last _maxLogEntries).
  Future<void> _appendLog(ConsentRecord record) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(_keyConsentLog) ?? [];
      list.add(jsonEncode(record.toJson()));
      if (list.length > _maxLogEntries) {
        list.removeRange(0, list.length - _maxLogEntries);
      }
      await sp.setStringList(_keyConsentLog, list);
    } catch (e) {
      if (kDebugMode) {
        print('ConsentService: failed to append log: $e');
      }
    }
  }

  /// Export consent log for compliance (e.g. audit). Returns list of records.
  Future<List<ConsentRecord>> getConsentLog() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_keyConsentLog) ?? [];
    final out = <ConsentRecord>[];
    for (final s in list) {
      try {
        final r = ConsentRecord.fromJson(jsonDecode(s) as Map<String, dynamic>?);
        if (r != null) out.add(r);
      } catch (_) {}
    }
    return out;
  }

  /// Clear biometric consent (withdraw). Call when user withdraws. Notifies server so 403 is returned for that session.
  Future<void> withdrawBiometricConsent() async {
    final sessionId = await getOrCreateSessionId();
    try {
      final uri = Uri.parse(
          '${ServerPersonalityService.serverUrl}/consents/withdraw?session_id=${Uri.encodeComponent(sessionId)}');
      await http.post(uri).timeout(const Duration(seconds: 5));
    } catch (_) {}
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyBiometricConsent);
    await sp.remove(_keyConsentPolicyVersions);
    await sp.remove(_keyConsentAt);
  }
}
