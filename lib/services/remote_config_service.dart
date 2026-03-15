import 'package:firebase_remote_config/firebase_remote_config.dart';

/// Firebase Remote Config サービスのシングルトン
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  static RemoteConfigService get instance => _instance;

  RemoteConfigService._internal();

  FirebaseRemoteConfig? _remoteConfig;
  bool _initialized = false;

  /// Remote Config の初期化
  Future<void> init() async {
    if (_initialized) return;
    try {
      _remoteConfig = FirebaseRemoteConfig.instance;
      await _remoteConfig!.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1),
      ));

      // デフォルト値の設定
      await _remoteConfig!.setDefaults({
        'enable_tflite': true, // TFLiteモデルを有効化
        'enable_segmentation': false,
        'gacha_daily_limit': 10,
        'consultation_urgent_cost': 50,
        'consultation_normal_cost': 20,
        'meditation_bonus_minutes': 5,
        'skin_analysis_version': '1.0',
      });

      // リモートから取得を試行（失敗してもデフォルト値を使用）
      try {
        await _remoteConfig!.fetchAndActivate();
      } catch (_) {
        // オフライン時やエラー時はデフォルト値を使用
      }

      _initialized = true;
    } catch (_) {
      // Firebase未設定時は無視
      _initialized = false;
    }
  }

  /// ブール値の取得
  bool getBool(String key, {bool defaultValue = false}) {
    if (!_initialized || _remoteConfig == null) return defaultValue;
    try {
      return _remoteConfig!.getBool(key);
    } catch (_) {
      return defaultValue;
    }
  }

  /// 文字列の取得
  String getString(String key, {String defaultValue = ''}) {
    if (!_initialized || _remoteConfig == null) return defaultValue;
    try {
      return _remoteConfig!.getString(key);
    } catch (_) {
      return defaultValue;
    }
  }

  /// 数値の取得
  int getInt(String key, {int defaultValue = 0}) {
    if (!_initialized || _remoteConfig == null) return defaultValue;
    try {
      return _remoteConfig!.getInt(key);
    } catch (_) {
      return defaultValue;
    }
  }

  /// 実数値の取得
  double getDouble(String key, {double defaultValue = 0.0}) {
    if (!_initialized || _remoteConfig == null) return defaultValue;
    try {
      return _remoteConfig!.getDouble(key);
    } catch (_) {
      return defaultValue;
    }
  }

  /// 設定の再取得（手動更新）
  Future<void> fetchAndActivate() async {
    if (!_initialized || _remoteConfig == null) return;
    try {
      await _remoteConfig!.fetchAndActivate();
    } catch (_) {
      // エラーは無視
    }
  }
}
