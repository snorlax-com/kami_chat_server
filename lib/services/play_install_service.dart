import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kami_face_oracle/core/integration_test_flags.dart';

/// Android のインストール元（Play 経由か ADB 直インストールか）。
class PlayInstallService {
  PlayInstallService._();

  static const _channel = MethodChannel('com.auraface.kami_face_oracle/billing');

  static String? _installerPackage;
  static bool? _installedFromPlayStore;

  static Future<void> ensureLoaded() async {
    if (_installerPackage != null) return;
    if (IntegrationTestFlags.forcePlayBilling) {
      _installerPackage = 'com.android.vending';
      _installedFromPlayStore = true;
      debugPrint('[PlayInstallService] integration test: pretend Play install');
      return;
    }
    if (!Platform.isAndroid) {
      _installerPackage = 'non_android';
      _installedFromPlayStore = false;
      return;
    }
    try {
      final raw = await _channel.invokeMethod<String>('getInstallerPackageName');
      _installerPackage = raw;
      _installedFromPlayStore = raw == 'com.android.vending';
      debugPrint('[PlayInstallService] installer=$raw fromPlay=$_installedFromPlayStore');
    } catch (e) {
      debugPrint('[PlayInstallService] installer lookup failed: $e');
      _installerPackage = 'unknown';
      _installedFromPlayStore = false;
    }
  }

  static String? get installerPackage => _installerPackage;

  static bool get isInstalledFromPlayStore => _installedFromPlayStore ?? false;

  /// ADB / PC ツール等による sideload（Play ストア経由でないインストール）。
  static bool get isSideloadInstall {
    if (IntegrationTestFlags.forcePlayBilling) return false;
    if (!Platform.isAndroid) return false;
    return !isInstalledFromPlayStore;
  }

  static void debugReset() {
    assert(kDebugMode);
    _installerPackage = null;
    _installedFromPlayStore = null;
  }
}
