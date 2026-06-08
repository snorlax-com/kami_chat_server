import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kami_face_oracle/ui/widgets/tutorial_guest_exit_actions.dart';

/// チュートリアル未ログイン時の戻る操作を1経路に集約する。
class TutorialGuestExitScope extends StatelessWidget {
  final bool enabled;
  final bool tutorialFlow;
  final Widget child;
  final Future<void> Function()? onLogin;
  final Future<void> Function()? onExitWithoutLogin;
  final VoidCallback? onBackRequested;

  const TutorialGuestExitScope({
    super.key,
    required this.enabled,
    this.tutorialFlow = false,
    required this.child,
    this.onLogin,
    this.onExitWithoutLogin,
    this.onBackRequested,
  });

  void _onBackRequested(BuildContext context) {
    if (!enabled) {
      if (context.mounted) Navigator.of(context).maybePop();
      return;
    }
    if (onBackRequested != null) {
      onBackRequested!();
      return;
    }
    unawaited(
      TutorialGuestExitActions.promptExitIfNeeded(
        context,
        onLogin: onLogin,
        onExitWithoutLogin: onExitWithoutLogin,
        tutorialFlow: tutorialFlow,
        forcePrompt: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    // MaterialApp(Navigator) 構成では Router が無く BackButtonListener がクラッシュするため PopScope のみ使う。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _onBackRequested(context);
      },
      child: child,
    );
  }
}
