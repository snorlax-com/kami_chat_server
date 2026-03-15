/// Global legal/compliance configuration for AuraFace.
/// Replace placeholders before production; final review by legal counsel recommended.
class LegalConfig {
  LegalConfig._();

  static const String companyLegalName = '[Company Legal Name]';
  static const String registeredAddress = '[Registered Address]';
  static const String domain = '[your-domain]';

  static const String lastUpdated = '2026-02-12';

  /// Policy versions — bump and require re-consent when content changes.
  static const String termsVersion = '1.0';
  static const String privacyVersion = '1.0';
  static const String biometricVersion = '1.0';
  static const String aiNoticeVersion = '1.0';
  static const String cookieVersion = '1.0';

  static String get legalEmail => 'legal@$domain';
  static String get privacyEmail => 'privacy@$domain';
  static String get supportEmail => 'support@$domain';
  static String get aiEmail => 'ai@$domain';
}
