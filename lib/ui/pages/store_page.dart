import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/services/local_ticket_store_service.dart';
import 'package:kami_face_oracle/services/store_catalog_service.dart';
import 'package:kami_face_oracle/services/play_install_service.dart';
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:kami_face_oracle/services/store_ui_helper.dart';
import 'package:kami_face_oracle/services/store_access_service.dart';
import 'package:kami_face_oracle/services/store_subscription_flow.dart';
import 'package:kami_face_oracle/services/subscription_management_service.dart';
import 'package:kami_face_oracle/ui/pages/store_locked_page.dart';

class StorePage extends StatefulWidget {
  const StorePage({super.key, this.embedInShell = false});

  final bool embedInShell;

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  final IAPService _iap = IAPService.instance;
  bool _isLoading = true;
  int _normalTickets = 0;
  int _urgentTickets = 0;
  bool _isSubscribed = false;
  bool _storeAccessAllowed = false;
  bool _canPurchaseTickets = false;
  bool _isSideloadInstall = false;
  String? _purchasingId;
  VoidCallback? _refreshListener;

  @override
  void initState() {
    super.initState();
    _iap.onTicketsGranted = _onTicketsGranted;
    _iap.onPurchaseCanceled = _onPurchaseCanceled;
    _iap.onPurchaseFailed = _onPurchaseFailed;
    _iap.onSubscriptionUpdated = _onSubscriptionUpdated;
    _refreshListener = () => unawaited(_load());
    AppNavigation.refreshStoreTab.addListener(_refreshListener!);
    _load();
  }

  @override
  void dispose() {
    AppNavigation.refreshStoreTab.removeListener(_refreshListener!);
    if (_iap.onTicketsGranted == _onTicketsGranted) _iap.onTicketsGranted = null;
    if (_iap.onPurchaseCanceled == _onPurchaseCanceled) _iap.onPurchaseCanceled = null;
    if (_iap.onPurchaseFailed == _onPurchaseFailed) _iap.onPurchaseFailed = null;
    if (_iap.onSubscriptionUpdated == _onSubscriptionUpdated) _iap.onSubscriptionUpdated = null;
    super.dispose();
  }

  void _onTicketsGranted(int tickets, String productId, {bool isUrgent = false}) {
    if (!mounted) return;
    _clearPurchasing(productId);
    final label = ConsultationTicketPacksService.getPackById(productId)?.name ?? '相談券';
    final kind = isUrgent ? '至急券' : '通常券';
    StoreUiHelper.showSnack('$label を購入しました（+$tickets $kind）', backgroundColor: Colors.green);
    unawaited(_load(refreshBalanceOnly: true));
  }

  void _onSubscriptionUpdated(bool active, {int bonusTickets = 0}) {
    if (!mounted) return;
    _clearPurchasing(StoreCatalogService.subscription.productId);
    setState(() => _isSubscribed = active);
    if (bonusTickets > 0) {
      StoreUiHelper.showSnack('サブスク加入しました。初回特典 +$bonusTickets 通常券', backgroundColor: Colors.green);
    } else if (active) {
      StoreUiHelper.showSnack('サブスクに加入しました', backgroundColor: Colors.green);
    }
    unawaited(_load(refreshBalanceOnly: true));
  }

  void _onPurchaseCanceled(String productId) {
    if (!mounted) return;
    _clearPurchasing(productId);
    StoreUiHelper.showSnack('購入をキャンセルしました');
  }

  void _onPurchaseFailed(String productId, String? message) {
    if (!mounted) return;
    _clearPurchasing(productId);
    if (StoreBillingConfig.allowAppStoreWhenPlayMissing) {
      unawaited(_fallbackAppStore(productId));
      return;
    }
    StoreUiHelper.showSnack(
      message ?? 'Google Play 課金に失敗しました。Play ストアからインストールしたビルドか確認してください。',
      backgroundColor: Colors.orange.shade800,
    );
  }

  Future<void> _fallbackAppStore(String productId) async {
    if (productId == StoreCatalogService.subscription.productId) {
      await _purchaseSubscriptionAppStore(silent: true);
      return;
    }
    final pack = ConsultationTicketPacksService.getPackById(productId);
    if (pack != null) await _purchasePackAppStore(pack, silent: true);
  }

  void _clearPurchasing(String id) {
    if (_purchasingId == id) setState(() => _purchasingId = null);
  }

  bool get _canUseSideloadTest =>
      StoreBillingConfig.allowSideloadTestPurchases && _isSideloadInstall;

  Future<void> _load({bool refreshBalanceOnly = false}) async {
    if (!refreshBalanceOnly) {
      if (mounted) setState(() => _isLoading = true);
      await StoreCatalogService.ensureLoaded();
      await PlayInstallService.ensureLoaded();
      if (mounted) setState(() => _isSideloadInstall = PlayInstallService.isSideloadInstall);
      await _iap.refreshCatalog();
    }
    final normal = await ConsultationTicketService.normalTickets();
    final urgent = await ConsultationTicketService.priorityTickets();
    final allowed = await StoreAccessService.canOpenStore();
    final canBuyTickets = await StoreAccessService.canPurchaseConsultationTickets();
    var sub = allowed;
    if (!allowed) {
      sub = false;
    } else {
      sub = await ConsultationSubscriptionService.isActive();
      if (StoreBillingConfig.requirePlayVerifiedAccess) {
        final sideloadOk = await SideloadBillingService.isSideloadTestSubscriptionValid();
        sub = sub && (_iap.hasVerifiedPlaySubscription || sideloadOk);
      }
    }
    if (!mounted) return;
    setState(() {
      _normalTickets = normal;
      _urgentTickets = urgent;
      _isSubscribed = sub;
      _storeAccessAllowed = allowed;
      _canPurchaseTickets = canBuyTickets;
      _isLoading = false;
    });
  }

  void _showPlayUnavailableMessage() {
    final parts = <String>[
      'Google Play 課金を開始できません。',
      if (_isSideloadInstall)
        '現在 ADB 直インストールです。Play Console の内部テスト経由でインストールすると本番課金が使えます。',
      if (!_iap.isAvailable) '端末の Play ストア / 課金サービスを確認してください。',
      if (_iap.isAvailable && !_iap.hasPlayCatalog)
        'Play Console に商品が未登録、または反映待ちの可能性があります。',
      if (_iap.notFoundProductIds.isNotEmpty)
        '未取得の商品ID: ${_iap.notFoundProductIds.join(", ")}',
      if (_canUseSideloadTest) 'テスト購入ボタンからフロー確認できます（実課金なし）。',
    ];
    StoreUiHelper.showSnack(parts.join('\n'), backgroundColor: Colors.orange.shade800);
  }

  Future<void> _purchasePackSideloadTest(ConsultationTicketPack pack) async {
    final price = pack.referencePriceYen != null ? '¥${pack.referencePriceYen}' : '';
    final ok = await StoreUiHelper.confirm(
      title: 'テスト購入',
      body:
          'ADB 直インストールのため Google Play 課金は使えません。\n\n'
          '${pack.name}${price.isNotEmpty ? '（$price相当）' : ''}\n'
          '${pack.description}\n\n'
          '※本番は Play 内部テスト版で課金されます。',
      confirmLabel: 'テスト購入',
      fallbackContext: context,
    );
    if (!ok || !mounted) return;
    setState(() => _purchasingId = pack.id);
    try {
      final n = await LocalTicketStoreService.purchasePack(pack);
      if (mounted) {
        StoreUiHelper.showSnack('${pack.name} テスト購入（+$n枚）', backgroundColor: Colors.green);
      }
    } finally {
      if (mounted) {
        setState(() => _purchasingId = null);
        await _load(refreshBalanceOnly: true);
      }
    }
  }

  Future<void> _purchaseSubscription() async {
    await StoreSubscriptionFlow.purchase(
      context,
      onPurchasingChanged: (id) {
        if (mounted) setState(() => _purchasingId = id);
      },
    );
    if (mounted) await _load(refreshBalanceOnly: true);
  }

  Future<void> _purchaseSubscriptionAppStore({bool silent = false}) async {
    final plan = StoreCatalogService.subscription;
    if (!silent) {
      final ok = await StoreUiHelper.confirm(
        title: plan.name,
        body: '${plan.description}\n\n月額 ¥${plan.priceYen}\n初回特典: 通常質問券${plan.firstBonusNormalTickets}枚',
        confirmLabel: '加入',
        fallbackContext: context,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _purchasingId = plan.productId);
    try {
      final bonus = await LocalTicketStoreService.purchaseSubscription();
      if (mounted) {
        setState(() => _isSubscribed = true);
        StoreUiHelper.showSnack('サブスク加入（初回特典 +$bonus 通常券）', backgroundColor: Colors.green);
      }
    } finally {
      if (mounted) {
        setState(() => _purchasingId = null);
        await _load(refreshBalanceOnly: true);
      }
    }
  }

  Future<void> _purchasePack(ConsultationTicketPack pack) async {
    if (!await StoreAccessService.guardTicketPurchase(context)) return;
    if (!mounted) return;
    if (_iap.canPurchaseViaPlay(pack)) {
      final product = _iap.productById(pack.id)!;
      final ok = await StoreUiHelper.confirm(
        title: pack.name,
        body: '${pack.description}\n価格: ${product.price}\n\nGoogle Play の購入画面が開きます。',
        confirmLabel: 'Google Play で購入',
        fallbackContext: context,
      );
      if (!ok || !mounted) return;
      setState(() => _purchasingId = pack.id);
      final outcome = await _iap.purchaseConsumable(pack);
      if (!mounted) return;
      switch (outcome) {
        case StorePurchasePlayLaunched():
          return;
        case StorePurchasePlayLaunchFailed():
          setState(() => _purchasingId = null);
          if (StoreBillingConfig.allowAppStoreWhenPlayMissing) {
            await _purchasePackAppStore(pack);
          } else if (_canUseSideloadTest) {
            await _purchasePackSideloadTest(pack);
          } else {
            _showPlayUnavailableMessage();
          }
        case StorePurchaseUnavailable():
          setState(() => _purchasingId = null);
          if (StoreBillingConfig.allowAppStoreWhenPlayMissing) {
            await _purchasePackAppStore(pack);
          } else if (_canUseSideloadTest) {
            await _purchasePackSideloadTest(pack);
          } else {
            _showPlayUnavailableMessage();
          }
      }
      return;
    }

    if (StoreBillingConfig.allowAppStoreWhenPlayMissing) {
      await _purchasePackAppStore(pack);
      return;
    }
    if (_canUseSideloadTest) {
      await _purchasePackSideloadTest(pack);
      return;
    }
    _showPlayUnavailableMessage();
  }

  Future<void> _purchasePackAppStore(ConsultationTicketPack pack, {bool silent = false}) async {
    if (!silent) {
      final price = pack.referencePriceYen != null ? '¥${pack.referencePriceYen}' : '';
      final ok = await StoreUiHelper.confirm(
        title: pack.name,
        body: '${pack.description}\n${price.isNotEmpty ? '価格: $price\n' : ''}購入します。',
        confirmLabel: '購入',
        fallbackContext: context,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _purchasingId = pack.id);
    try {
      final n = await LocalTicketStoreService.purchasePack(pack);
      if (mounted) {
        StoreUiHelper.showSnack('${pack.name}（+$n枚）', backgroundColor: Colors.green);
      }
    } finally {
      if (mounted) {
        setState(() => _purchasingId = null);
        await _load(refreshBalanceOnly: true);
      }
    }
  }

  Future<void> _openPlaySubscriptionManagement() async {
    final ok = await SubscriptionManagementService.openStoreSubscriptionManagement();
    if (!ok) {
      StoreUiHelper.showSnack('Google Play のサブスク管理を開けませんでした');
    }
  }

  String _billingStatusText() {
    if (_iap.isPlayBillingReady) return 'Google Play 課金: 利用可能';
    if (_isSideloadInstall && !_iap.hasPlayCatalog) {
      return 'ADB 直インストール: Play 商品未取得（テスト購入または内部テスト版を利用）';
    }
    if (!_iap.isAvailable) return 'Google Play 課金: 利用不可（Play ストアを確認）';
    if (!_iap.hasPlayCatalog) {
      return 'Google Play 課金: 商品未取得（Play Console 登録を確認）';
    }
    return 'Google Play 課金: 準備中';
  }

  Widget _buildBillingBanner() {
    final ready = _iap.isPlayBillingReady;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: ready ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.2),
      child: Text(
        _billingStatusText(),
        style: TextStyle(
          fontSize: 12,
          color: ready ? Colors.lightGreenAccent : Colors.orange.shade100,
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    final plan = StoreCatalogService.subscription;
    final isBuying = _purchasingId == plan.productId;
    final product = _iap.subscriptionProduct;
    final price = product?.price ?? '¥${plan.priceYen}';

    return Card(
      color: const Color(0xFF1A2340),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(plan.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (_isSubscribed)
                  const Chip(label: Text('加入中', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 8),
            Text(plan.description, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('$price / ${plan.billingPeriodLabel}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.purple.shade200)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isBuying
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _isSubscribed
                      ? (_iap.canSubscribeViaPlay
                          ? FilledButton(
                              onPressed: () => unawaited(_openPlaySubscriptionManagement()),
                              child: const Text('Google Play で管理'),
                            )
                          : OutlinedButton(
                              onPressed: null,
                              child: Text(_canUseSideloadTest ? 'テスト加入済み' : '加入済み'),
                            ))
                      : FilledButton(
                          onPressed: () => unawaited(_purchaseSubscription()),
                          child: Text(_canUseSideloadTest ? 'テスト加入' : 'サブスクに加入'),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackCard(ConsultationTicketPack pack) {
    final isBuying = _purchasingId == pack.id;
    final product = _iap.productById(pack.id);
    final price = product?.price ?? (pack.referencePriceYen != null ? '¥${pack.referencePriceYen}' : '');
    final purchaseEnabled = _canPurchaseTickets;

    return Card(
      color: const Color(0xFF141A2E),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              pack.isUrgent ? Icons.bolt : Icons.confirmation_number,
              color: pack.isUrgent ? Colors.redAccent : Colors.amberAccent,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(pack.description, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(price, style: TextStyle(color: Colors.amber.shade300, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            isBuying
                ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                : FilledButton(
                    onPressed: purchaseEnabled ? () => unawaited(_purchasePack(pack)) : null,
                    child: Text(_canUseSideloadTest ? 'テスト購入' : '購入'),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && !_storeAccessAllowed) {
      return StoreLockedPage(embedInShell: widget.embedInShell);
    }

    final packs = StoreCatalogService.consumables;

    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.black.withValues(alpha: 0.3),
                child: Column(
                  children: [
                    Text(
                      _isSubscribed ? 'サブスク: 加入中' : 'サブスク: 未加入',
                      style: TextStyle(color: _isSubscribed ? Colors.lightGreenAccent : Colors.orange.shade200),
                    ),
                    const SizedBox(height: 4),
                    Text('通常券: $_normalTickets 枚 / 至急券: $_urgentTickets 枚', style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              _buildBillingBanner(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _buildSubscriptionCard(),
                      if (!_canPurchaseTickets) ...[
                        const SizedBox(height: 8),
                        Card(
                          color: const Color(0xFF2A2030),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              '初回相談はサブスク特典の通常券をご利用ください。\n'
                              '2回目以降、ここで通常券・至急券を購入できます。',
                              style: TextStyle(color: Colors.amber.shade100, fontSize: 13, height: 1.35),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      ...packs.map(_buildPackCard),
                      if (kDebugMode && _iap.lastLoadError != null)
                        Text('Play debug: ${_iap.lastLoadError}', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                      if (kDebugMode && _iap.notFoundProductIds.isNotEmpty)
                        Text('not found: ${_iap.notFoundProductIds}', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton(onPressed: _isLoading ? null : () => unawaited(_load()), child: const Text('再読み込み')),
              ),
            ],
          );

    if (widget.embedInShell) return body;
    return Scaffold(appBar: AppBar(title: const Text('ストア')), body: body);
  }
}
