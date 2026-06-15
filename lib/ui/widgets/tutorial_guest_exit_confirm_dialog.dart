import 'package:flutter/material.dart';
import 'package:kami_face_oracle/ui/widgets/tutorial_guest_exit_actions.dart';

/// チュートリアル結果画面でログインせず終了するときの確認。
enum TutorialGuestExitChoice {
  login,
  exit,
}

class TutorialGuestExitConfirmDialog {
  TutorialGuestExitConfirmDialog._();

  static const String message =
      'チュートリアルがログインされずに終わった場合は、性格診断ができるのは一度きりです、'
      'ログインせずに終了すると他の機能が使えなくなります。。\n\n'
      '本当にログインせず終了してよろしいですか？';

  /// ユーザー操作（戻るボタン等）から呼ぶ。即時にダイアログを表示する。
  static Future<TutorialGuestExitChoice?> show(BuildContext context) async {
    if (!context.mounted) {
      // ignore: avoid_print
      print('[GuestExit] dialog skip: unmounted');
      return null;
    }
    try {
      // ignore: avoid_print
      print('[GuestExit] dialog show');
      final choice = await showDialog<TutorialGuestExitChoice>(
        context: context,
        routeSettings: const RouteSettings(name: TutorialGuestExitActions.exitDialogRouteName),
        useRootNavigator: true,
        barrierDismissible: false,
        barrierColor: const Color(0xCC000000),
        builder: (ctx) {
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              // ignore: avoid_print
              print('[GuestExit] dialog back → dismiss');
              Navigator.of(ctx).pop();
            },
            child: AlertDialog(
              backgroundColor: const Color(0xFF1A1F3A),
              title: const Text(
                'ログインせずに終了しますか？',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: const SingleChildScrollView(
                child: Text(
                  message,
                  style: TextStyle(color: Colors.white70, height: 1.45),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, TutorialGuestExitChoice.exit),
                  child: const Text('終了する'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, TutorialGuestExitChoice.login),
                  child: const Text('ログインする'),
                ),
              ],
            ),
          );
        },
      );
      // ignore: avoid_print
      print('[GuestExit] dialog closed choice=$choice');
      return choice;
    } catch (e, st) {
      // ignore: avoid_print
      print('[GuestExit] dialog error: $e\n$st');
      return null;
    }
  }
}
