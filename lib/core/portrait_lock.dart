import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// アプリ全体を縦画面（portraitUp）に固定する。
Future<void> lockPortraitOrientation() {
  return SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
}

/// ライフサイクル復帰時も縦固定を維持するラッパー。
class PortraitLockScope extends StatefulWidget {
  const PortraitLockScope({super.key, required this.child});

  final Widget child;

  @override
  State<PortraitLockScope> createState() => _PortraitLockScopeState();
}

class _PortraitLockScopeState extends State<PortraitLockScope> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(lockPortraitOrientation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(lockPortraitOrientation());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
