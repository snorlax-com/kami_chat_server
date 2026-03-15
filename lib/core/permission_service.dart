import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 権限状態の確認と設定画面への誘導を1箇所に集約する。
/// カメラ・フォトライブラリ等、権限拒否時に「設定を開く」で復帰できるようにする。
class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  /// カメラ権限の現在の状態（プラットフォームによる）
  Future<PermissionStatus> get cameraStatus async {
    if (kIsWeb) return PermissionStatus.denied;
    return await Permission.camera.status;
  }

  /// カメラ権限をリクエスト（ダイアログ表示）
  Future<PermissionStatus> requestCamera() async {
    if (kIsWeb) return PermissionStatus.denied;
    return await Permission.camera.request();
  }

  /// フォトライブラリ（メディア）権限
  Future<PermissionStatus> get photosStatus async {
    if (kIsWeb) return PermissionStatus.denied;
    if (await Permission.photos.isRestricted) return PermissionStatus.denied;
    return await Permission.photos.status;
  }

  /// このアプリの設定画面を開く（権限変更後ユーザーが戻ってこられる）
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// 権限が拒否されたときに「設定を開く」を案内するダイアログを表示する。
  /// カメラ初期化失敗時などに呼ぶ。
  static Future<void> showOpenSettingsDialog(
    BuildContext context, {
    String title = 'カメラの許可が必要です',
    String message = '設定から「Kami Face Oracle」のカメラを許可してください。',
    String openLabel = '設定を開く',
    String laterLabel = 'あとで',
  }) async {
    if (!context.mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(laterLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(openLabel),
          ),
        ],
      ),
    );
    if (result == true) await instance.openSettings();
  }
}
