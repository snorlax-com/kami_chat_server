/// 性格診断 API（Vultr / 将来 api.auraface.jp）のベース URL。
class DiagnosisServerConfig {
  DiagnosisServerConfig._();

  static const String _fromEnv = String.fromEnvironment(
    'DIAGNOSIS_SERVER_URL',
    defaultValue: '',
  );

  /// TLS + カスタムドメイン（Nginx 設定後）。
  static const String productionHttps = 'https://api.auraface.jp';

  /// 現行 Vultr（移行中はこちらをデフォルト）。
  static const String legacyVultrHttp = 'http://45.77.26.42:8000';

  static String get baseUrl {
    final env = _fromEnv.trim();
    if (env.isNotEmpty) {
      return env.endsWith('/') ? env.substring(0, env.length - 1) : env;
    }
    return legacyVultrHttp;
  }
}
