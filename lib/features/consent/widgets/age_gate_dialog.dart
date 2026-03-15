import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/features/consent/consent_service.dart';
import 'package:kami_face_oracle/features/consent/widgets/cookie_consent_banner.dart';

/// Age gate: "I confirm I am 18+". Must be shown before using the app (first launch).
class AgeGateDialog extends StatelessWidget {
  const AgeGateDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AgeGateDialog(),
    );
  }

  static const double _minButtonHeight = 56.0; // 押しやすい最小タップ領域

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '年齢確認。18歳以上であることを確認してください。',
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: const Text('Age confirmation'),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: const Text(
              'You must be at least 18 years old to use AuraFace. '
              'If you are under 18, you may use the Service only with verified parental or legal guardian consent. '
              'We do not knowingly allow children under 13 to use the Service.\n\n'
              'By continuing, you confirm that you are at least 18 years of age (or have the required consent).',
            ),
          ),
        ),
        actionsPadding: EdgeInsets.zero,
        actions: [
          // 縦並びで下部にメイン操作を配置（親指で押しやすい）
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: true,
                  label: '18歳未満です。アプリは利用できません。',
                  child: SizedBox(
                    height: _minButtonHeight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('I am under 18'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  button: true,
                  label: '18歳以上です。続行する',
                  child: SizedBox(
                    height: _minButtonHeight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('I am 18 or older'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wrapper that shows age gate on first launch and navigates to child or exit.
class AgeGateWrapper extends StatefulWidget {
  const AgeGateWrapper({super.key, required this.child});

  final Widget child;

  @override
  State<AgeGateWrapper> createState() => _AgeGateWrapperState();
}

class _AgeGateWrapperState extends State<AgeGateWrapper> {
  bool _checked = false;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _maybeShowCookieBanner() async {
    final need = await CookieConsentBanner.needToShow();
    if (!need || !mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: CookieConsentBanner(
          regionGroup: 'EU',
          onComplete: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _check() async {
    if (E2E.isEnabled) {
      if (!mounted) return;
      setState(() {
        _checked = true;
        _allowed = true;
      });
      // 統合テストでは先にホームを表示し、保存は非同期で試行（実機で SharedPreferences が遅い場合の対策）
      ConsentService.instance.setAgeConfirmed(true).catchError((e) {
        debugPrint('AgeGate (E2E): setAgeConfirmed failed $e');
      });
      return;
    }
    final need = await ConsentService.instance.needAgeGate();
    if (!mounted) return;
    if (!need) {
      setState(() {
        _checked = true;
        _allowed = true;
      });
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeShowCookieBanner();
      });
      return;
    }
    final result = await AgeGateDialog.show(context);
    if (!mounted) return;
    if (result == true) {
      try {
        await ConsentService.instance.setAgeConfirmed(true);
      } catch (e, st) {
        debugPrint('AgeGate: setAgeConfirmed failed $e');
        debugPrint(st.toString().split('\n').take(5).join('\n'));
      }
      if (!mounted) return;
      setState(() {
        _checked = true;
        _allowed = true;
      });
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeShowCookieBanner();
      });
    } else {
      setState(() {
        _checked = true;
        _allowed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_allowed) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'You must be 18 or older to use this app.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: () => _check(),
                      child: const Text('Try again'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
