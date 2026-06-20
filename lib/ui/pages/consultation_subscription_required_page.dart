import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/services/local_ticket_store_service.dart';
import 'package:kami_face_oracle/services/play_install_service.dart';
import 'package:kami_face_oracle/services/store_catalog_service.dart';
import 'package:kami_face_oracle/services/store_subscription_flow.dart';
import 'package:kami_face_oracle/ui/widgets/play_internal_test_install_banner.dart';

/// 占い相談の送信時に、サブスク未加入ユーザーへ説明する画面。
class ConsultationSubscriptionRequiredPage extends StatefulWidget {
  const ConsultationSubscriptionRequiredPage({super.key});

  @override
  State<ConsultationSubscriptionRequiredPage> createState() =>
      _ConsultationSubscriptionRequiredPageState();
}

class _ConsultationSubscriptionRequiredPageState extends State<ConsultationSubscriptionRequiredPage> {
  bool _busy = false;
  bool _showSideloadTestSubscribe = false;
  bool _showPlayInternalTestPrompt = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await StoreCatalogService.ensureLoaded();
    await PlayInstallService.ensureLoaded();
    final iap = IAPService.instance;
    await iap.ensureReady();
    if (mounted) {
      setState(() {
        _showSideloadTestSubscribe = StoreBillingConfig.shouldUseSideloadTestPurchase(
          isSideloadInstall: PlayInstallService.isSideloadInstall,
          billingAvailable: iap.isAvailable,
        );
        _showPlayInternalTestPrompt = StoreBillingConfig.shouldShowPlayInternalTestInstallPrompt(
          isSideloadInstall: PlayInstallService.isSideloadInstall,
          billingReady: iap.isPlayBillingReady,
        );
      });
    }
  }

  Future<void> _popWithSubscriptionResult() async {
    if (!mounted) return;
    final ok = await StoreSubscriptionFlow.refreshSubscribed();
    if (!mounted) return;
    Navigator.pop(context, ok);
  }

  Future<void> _subscribe() async {
    setState(() => _busy = true);
    try {
      await StoreSubscriptionFlow.purchase(context);
      if (!mounted) return;
      await _popWithSubscriptionResult();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ADB インストール版向け: Play 課金なしでテスト加入（初回券付与）→ 送信へ戻る。
  Future<void> _testSubscribe() async {
    setState(() => _busy = true);
    try {
      await PlayInstallService.ensureLoaded();
      if (!PlayInstallService.isSideloadInstall) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('テスト加入は ADB 直インストール版でのみ利用できます。'),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
        return;
      }
      await LocalTicketStoreService.purchaseSubscription(sideloadTest: true);
      AppNavigation.notifyStoreAccessChanged();
      if (!mounted) return;
      await _popWithSubscriptionResult();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = StoreCatalogService.subscription;

    return Scaffold(
      appBar: AppBar(
        title: const Text('サブスクについて'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.card_membership, size: 56, color: Colors.purple.shade200),
              const SizedBox(height: 16),
              Text(
                '質問を送信するには\nサブスクへの加入が必要です',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),
              Card(
                color: const Color(0xFF1A2340),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        plan.description,
                        style: const TextStyle(color: Colors.white70, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '月額 ¥${plan.priceYen}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade200,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _bullet('初回加入特典: 通常質問券${plan.firstBonusNormalTickets}枚プレゼント'),
              _bullet('送信のたびに通常券または至急券を1枚消費します'),
              _bullet('2回目以降はストアで追加の券を購入できます'),
              const SizedBox(height: 28),
              if (_showPlayInternalTestPrompt) ...[
                const PlayInternalTestInstallBanner(compact: true),
                const SizedBox(height: 16),
              ],
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (_showSideloadTestSubscribe) ...[
                  FilledButton.icon(
                    onPressed: _testSubscribe,
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('テスト加入（実機・ADB版）'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '本番のサブスク加入と同じ状態（加入中・初回券付与）で動作します。'
                    '戻ると自動で送信し、占い相談のメッセージ画面へ移ります。',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  onPressed: _subscribe,
                  icon: const Icon(Icons.card_membership),
                  label: Text(_showSideloadTestSubscribe ? 'Google Play で加入' : 'サブスクに加入'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('あとで'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: Colors.lightGreenAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.4))),
        ],
      ),
    );
  }
}
