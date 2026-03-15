/// Single consent event for compliance logging (GDPR/BIPA etc.).
class ConsentRecord {
  ConsentRecord({
    required this.timestampUtc,
    required this.regionCountry,
    required this.policyVersions,
    required this.consents,
    required this.source,
    this.userId,
    this.sessionId,
    this.ipHash,
  });

  final DateTime timestampUtc;
  final String regionCountry;
  final PolicyVersions policyVersions;
  final ConsentFlags consents;
  final String source;
  final String? userId;
  final String? sessionId;
  final String? ipHash;

  Map<String, dynamic> toJson() => {
        'timestamp_utc': timestampUtc.toIso8601String(),
        'region_country': regionCountry,
        'policy_versions': policyVersions.toJson(),
        'consents': consents.toJson(),
        'source': source,
        if (userId != null) 'user_id': userId,
        if (sessionId != null) 'session_id': sessionId,
        if (ipHash != null) 'ip_hash': ipHash,
      };

  static ConsentRecord? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final pv = json['policy_versions'] as Map<String, dynamic>?;
    final cf = json['consents'] as Map<String, dynamic>?;
    return ConsentRecord(
      timestampUtc: DateTime.tryParse(json['timestamp_utc'] as String? ?? '') ?? DateTime.now().toUtc(),
      regionCountry: json['region_country'] as String? ?? 'unknown',
      policyVersions: PolicyVersions.fromJson(pv),
      consents: ConsentFlags.fromJson(cf),
      source: json['source'] as String? ?? 'unknown',
      userId: json['user_id'] as String?,
      sessionId: json['session_id'] as String?,
      ipHash: json['ip_hash'] as String?,
    );
  }
}

class PolicyVersions {
  const PolicyVersions({
    required this.termsVersion,
    required this.privacyVersion,
    required this.biometricVersion,
    required this.aiNoticeVersion,
    required this.cookieVersion,
  });

  final String termsVersion;
  final String privacyVersion;
  final String biometricVersion;
  final String aiNoticeVersion;
  final String cookieVersion;

  Map<String, dynamic> toJson() => {
        'terms_version': termsVersion,
        'privacy_version': privacyVersion,
        'biometric_version': biometricVersion,
        'ai_notice_version': aiNoticeVersion,
        'cookie_version': cookieVersion,
      };

  static PolicyVersions fromJson(Map<String, dynamic>? json) {
    if (json == null)
      return const PolicyVersions(
        termsVersion: '',
        privacyVersion: '',
        biometricVersion: '',
        aiNoticeVersion: '',
        cookieVersion: '',
      );
    return PolicyVersions(
      termsVersion: json['terms_version'] as String? ?? '',
      privacyVersion: json['privacy_version'] as String? ?? '',
      biometricVersion: json['biometric_version'] as String? ?? '',
      aiNoticeVersion: json['ai_notice_version'] as String? ?? '',
      cookieVersion: json['cookie_version'] as String? ?? '',
    );
  }

  /// True if every version matches current (used for re-consent when any policy changes).
  bool matches(PolicyVersions current) {
    return termsVersion == current.termsVersion &&
        privacyVersion == current.privacyVersion &&
        biometricVersion == current.biometricVersion &&
        aiNoticeVersion == current.aiNoticeVersion &&
        cookieVersion == current.cookieVersion;
  }
}

class ConsentFlags {
  const ConsentFlags({
    required this.biometricExplicit,
    required this.ageConfirmed,
    this.cookiePreferences,
  });

  final bool biometricExplicit;
  final bool ageConfirmed;
  final Map<String, dynamic>? cookiePreferences;

  Map<String, dynamic> toJson() => {
        'biometric_explicit': biometricExplicit,
        'age_confirmed': ageConfirmed,
        if (cookiePreferences != null) 'cookie_preferences': cookiePreferences,
      };

  static ConsentFlags fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ConsentFlags(biometricExplicit: false, ageConfirmed: false);
    return ConsentFlags(
      biometricExplicit: json['biometric_explicit'] as bool? ?? false,
      ageConfirmed: json['age_confirmed'] as bool? ?? false,
      cookiePreferences: json['cookie_preferences'] as Map<String, dynamic>?,
    );
  }
}
