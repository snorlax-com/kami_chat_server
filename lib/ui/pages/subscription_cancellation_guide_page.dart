import 'package:flutter/material.dart';

import 'package:kami_face_oracle/app_navigation.dart';

/// Google Play のサブスク解約手順（Android のみ想定）。
class SubscriptionCancellationGuidePage extends StatelessWidget {
  const SubscriptionCancellationGuidePage({super.key});

  static const assetPath = 'assets/guides/google_play_cancel_guide.png';

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final imageWidth = width * 0.88;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        title: const Text(
          '解約手順について',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionHeading('解約について'),
                  const SizedBox(height: 8),
                  const _BodyText(
                    '月額サブスク（定期購入）の解約は、Google Play から行います。'
                    '本アプリ内では解約のお手続きはできません。',
                  ),
                  const SizedBox(height: 20),
                  const _SectionHeading('解約の手順'),
                  const SizedBox(height: 12),
                  const _BodyText(
                    'Google Play の「お支払いと定期購入」を開き、「定期購入」を選択します。'
                    '対象の定期購入を開き、「定期購入を解約」を選ぶと解約できます。',
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: imageWidth,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          assetPath,
                          width: imageWidth,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '解約画面の参考画像を読み込めませんでした。',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Material(
            elevation: 8,
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _goHome(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'ホームに戻る',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _goHome(BuildContext context) {
    AppNavigation.switchMainTab(0);
    final root = appNavigatorKey.currentState;
    if (root != null) {
      root.popUntil((route) => route.isFirst);
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
        height: 1.3,
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  const _BodyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        height: 1.55,
        color: Colors.black87,
      ),
    );
  }
}
