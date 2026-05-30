import 'package:flutter/material.dart';
import 'package:kami_face_oracle/app_navigation.dart';

/// IndexedStack 内のストア等から、ルート Navigator / SnackBar を使う。
class StoreUiHelper {
  StoreUiHelper._();

  static BuildContext? get rootContext => appNavigatorKey.currentContext;

  static Future<bool> confirm({
    required String title,
    required String body,
    required String confirmLabel,
    String cancelLabel = 'キャンセル',
    BuildContext? fallbackContext,
  }) async {
    final ctx = rootContext ?? fallbackContext;
    if (ctx == null) return false;

    final ok = await showDialog<bool>(
      context: ctx,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: Text(cancelLabel)),
          FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: Text(confirmLabel)),
        ],
      ),
    );
    return ok == true;
  }

  static void showSnack(String message, {Color? backgroundColor}) {
    final ctx = rootContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }
}
