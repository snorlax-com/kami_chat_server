import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/consultation_access_service.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/services/play_billing_error_mapper.dart';
import 'package:kami_face_oracle/services/local_ticket_store_service.dart';
import 'package:kami_face_oracle/services/store_catalog_service.dart';
import 'package:kami_face_oracle/services/play_install_service.dart';
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:kami_face_oracle/services/store_ui_helper.dart';
import 'package:kami_face_oracle/services/store_access_service.dart';
import 'package:kami_face_oracle/services/store_subscription_flow.dart';
import 'package:kami_face_oracle/services/subscription_management_service.dart';
import 'package:kami_face_oracle/services/billing_log.dart';
import 'package:kami_face_oracle/ui/pages/store_locked_page.dart';

class StorePage extends StatefulWidget {
  const StorePage({
    super.key,
    this.embedInShell = false,
    this.forTicketPurchase = false,
  });

  final bool embedInShell;

  /// 占い相談の券不足から開いたとき（加入済みならロック画面を出さない）。
  final bool forTicketPurchase;

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
  String? _lastBillingError;
  VoidCallback? _refreshListener;
  int _prevNormalTickets = 0;
  int _prevUrgentTickets = 0;

  @override
  void initState() {
    super.initState();
    _iap.onPurchaseCanceled = _onPurchaseCanceled;
    _iap.onPurchaseFailed = _onPurchaseFailed;
    _iap.onSubscriptionUpdated = _onSubscriptionUpdated;
    _iap.onPurchasePending = _onPurchasePending;
    _refreshListener = () => unawaited(_onStoreTabRefreshRequested());
    AppNavigation.refreshStoreTab.addListener(_refreshListener!);
    _load();
  }

  @override
  void dispose() {
    AppNavigation.refreshStoreTab.removeListener(_refreshListener!);
    if (_iap.onPurchaseCanceled == _onPurchaseCanceled) _iap.onPurchaseCanceled = null;
    if (_iap.onPurchaseFailed == _onPurchaseFailed) _iap.onPurchaseFailed = null;
    if (_iap.onSubscriptionUpdated == _onSubscriptionUpdated) _iap.onSubscriptionUpdated = null;
    if (_iap.onPurchasePending == _onPurchasePending) _iap.onPurchasePending = null;
    super.dispose();
  }

  /// 券購入完了後、占い相談タブへ即時復帰（残高更新を待たない）。
  void _completeTicketPurchaseReturn() {
    BillingLog.info(
      'completeTicketPurchaseReturn embed=${widget.embedInShell} '
      'pending=${AppNavigation.shouldReturnToConsultationAfterTicketStorePurchase}',
    );
    if (!widget.embedInShell && mounted) {
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
        unawaited(AppNavigation.restoreConsultationDraftNow());
      }
    }
    unawaited(AppNavigation.completeTicketPackPurchaseFromStore());
  }

  void _onSubscriptionUpdated(bool active, {int bonusTickets = 0}) {
    if (!mounted) return;
    _clearPurchasing(StoreCatalogService.subscription.productId);
    setState(() => _isSubscribed = active);
    if (bonusTickets > 0) {
      StoreUiHelper.showSnack('サブスク加入しました。初回特典 質問券 +$bonusTickets 枚', backgroundColor: Colors.green);
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

  void _onPurchasePending(String productId) {
    if (!mounted) return;
    setState(() => _purchasingId = productId);
    StoreUiHelper.showSnack('購入処理を確認中です（決済保留）');
  }

  void _onPurchaseFailed(String productId, String? message) {
    if (!mounted) return;
    _clearPurchasing(productId);
    final text = message ?? PlayBillingErrorMapper.userMessage(null, productId: productId);
    setState(() => _lastBillingError = text);
    if (StoreBillingConfig.allowAppStoreWhenPlayMissing) {
      unawaited(_fallbackAppStore(productId));
      return;
    }
    StoreUiHelper.showSnack(text, backgroundColor: Colors.orange.shade800);
  }

  Future<void> _restorePurchases() async {
    if (!_iap.isAvailable) {
      _showPlayUnavailableMessage();
      return;
    }
    setState(() {
      _isLoading = true;
      _lastBillingError = null;
    });
    try {
      await _iap.restorePurchases();
      if (mounted) {
        StoreUiHelper.showSnack('購入情報を復元しました', backgroundColor: Colors.green);
      }
    } catch (e) {
      if (mounted) {
        final msg = PlayBillingErrorMapper.userMessage(e);
        setState(() => _lastBillingError = msg);
        StoreUiHelper.showSnack(msg, backgroundColor: Colors.orange.shade800);
      }
    } finally {
      if (mounted) await _load();
    }
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

  Future<void> _onStoreTabRefreshRequested() async {
    await _load(refreshBalanceOnly: true);
    if (!mounted || _purchasingId == null) return;
    if (!_iap.isProductPending(_purchasingId!)) {
      setState(() => _purchasingId = null);
    }
  }

  bool get _canUseSideloadTest =>
      StoreBillingConfig.allowSideloadTestPurchases && _isSideloadInstall;

  /// 占い相談の券不足から開いたストア（IndexedStack では forTicketPurchase が false のためフラグ併用）。
  bool get _fromConsultationTicketFlow =>
      widget.forTicketPurchase ||
      AppNavigation.shouldReturnToConsultationAfterTicketStorePurchase;


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
    final access = await ConsultationAccessService.loadState();
    final allowed = _fromConsultationTicketFlow
        ? access.isSubscribed
        : await StoreAccessService.canOpenStore();
    var canBuyTickets = await StoreAccessService.canPurchaseConsultationTickets();
    if (_fromConsultationTicketFlow && access.isSubscribed && _canUseSideloadTest) {
      canBuyTickets = true;
    }
    var sub = access.isSubscribed;
    if (!_fromConsultationTicketFlow && !allowed) {
      sub = false;
    } else if (!_fromConsultationTicketFlow) {
      sub = await ConsultationSubscriptionService.isActive();
      if (StoreBillingConfig.requirePlayVerifiedAccess) {
        final sideloadOk = await SideloadBillingService.isSideloadTestSubscriptionValid();
        sub = sub && (_iap.hasVerifiedPlaySubscription || sideloadOk);
      }
    }
    if (!mounted) return;
    final balanceIncreased = normal > _prevNormalTickets || urgent > _prevUrgentTickets;
    setState(() {
      _normalTickets = normal;
      _urgentTickets = urgent;
      _isSubscribed = sub;
      _storeAccessAllowed = allowed;
      _canPurchaseTickets = canBuyTickets;
      _isLoading = false;
    });
    _prevNormalTickets = normal;
    _prevUrgentTickets = urgent;
    if (balanceIncreased && (normal > 0 || urgent > 0)) {
      unawaited(_maybeReturnAfterTicketBalanceIncreased());
    }
  }

  Future<void> _maybeReturnAfterTicketBalanceIncreased() async {
    final shouldReturn = await AppNavigation.shouldReturnToConsultationAfterTicketStorePurchaseAsync();
    if (!shouldReturn) return;
    BillingLog.info('storePage: balance increased -> return to consultation');
    _completeTicketPurchaseReturn();
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
      if (n > 0) {
        _completeTicketPurchaseReturn();
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
    if (!_fromConsultationTicketFlow) {
      if (!await StoreAccessService.guardTicketPurchase(context)) return;
    } else if (!_canPurchaseTickets && !_canUseSideloadTest) {
      if (!mounted) return;
      StoreUiHelper.showSnack(
        '初回相談はサブスク特典の通常券をご利用ください。2回目以降、ここで券を購入できます。',
        backgroundColor: Colors.orange.shade800,
      );
      return;
    }
    if (!mounted) return;

    if (_canUseSideloadTest) {
      await _purchasePackSideloadTest(pack);
      return;
    }

    if (_iap.canPurchaseViaPlay(pack)) {
      final product = _iap.productForPack(pack)!;
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
      if (n > 0) {
        _completeTicketPurchaseReturn();
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

  Widget _buildSubscriptionInfoCard() {
    final plan = StoreCatalogService.subscription;
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
                  child: Text(
                    plan.name,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isSubscribed)
                  const Chip(
                    label: Text('加入中', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(plan.description, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(
              '$price / ${plan.billingPeriodLabel}',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.purple.shade200),
            ),
          ],
        ),
      ),
    );
  }

  /// 画面最下部に固定するサブスク加入・管理ボタン。
  Widget _buildSubscriptionBottomAction() {
    final plan = StoreCatalogService.subscription;
    final isBuying = _purchasingId == plan.productId;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: SizedBox(
          width: double.infinity,
          height: 48,
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
      ),
    );
  }

  Widget _buildPackCard(ConsultationTicketPack pack) {
    final isBuying = _purchasingId == pack.id || _iap.isProductPending(pack.id);
    final product = _iap.productForPack(pack);
    final price = product?.price ?? (pack.referencePriceYen != null ? '¥${pack.referencePriceYen}' : '');
    final purchaseEnabled =
        _canPurchaseTickets || (_fromConsultationTicketFlow && _canUseSideloadTest);

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
                    key: Key('store_buy_${pack.id}'),
                    onPressed: purchaseEnabled ? () => unawaited(_purchasePack(pack)) : null,
                    child: Text(
                      _iap.isProductPending(pack.id)
                          ? '確認中'
                          : (_canUseSideloadTest ? 'テスト購入' : '購入'),
                    ),
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
                    Text(
                      '質問券（通常）: $_normalTickets 枚 / 至急券: $_urgentTickets 枚',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              _buildBillingBanner(),
              if (_lastBillingError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.red.withValues(alpha: 0.2),
                  child: Text(
                    _lastBillingError!,
                    style: TextStyle(color: Colors.red.shade200, fontSize: 12),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _buildSubscriptionInfoCard(),
                      if (!_isSubscribed) ...[
                        const SizedBox(height: 12),
                        Card(
                          color: const Color(0xFF2A2030),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              'サブスク加入後に、通常券（¥600）・至急券（¥10,000）を購入できます。',
                              style: TextStyle(color: Colors.amber.shade100, fontSize: 13, height: 1.35),
                            ),
                          ),
                        ),
                      ],
                      if (_isSubscribed) ...[
                        const SizedBox(height: 8),
                        Text(
                          '追加購入',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.bold),
                        ),
                        if (!_canPurchaseTickets) ...[
                          const SizedBox(height: 8),
                          Card(
                            color: const Color(0xFF2A2030),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(
                                '初回相談はサブスク特典の質問券をご利用ください。\n'
                                '2回目以降、ここで通常券・至急券を購入できます。',
                                style: TextStyle(color: Colors.amber.shade100, fontSize: 13, height: 1.35),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        ...packs.map(_buildPackCard),
                      ],
                      if (_iap.lastLoadError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _iap.lastLoadError!,
                            style: TextStyle(color: Colors.orange.shade200, fontSize: 11),
                          ),
                        ),
                      if (_iap.notFoundProductIds.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '未取得 ID: ${_iap.notFoundProductIds.join(", ")}',
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : () => unawaited(_restorePurchases()),
                        child: const Text('購入を復元'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : () => unawaited(_load()),
                        child: const Text('再読み込み'),
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isLoading) _buildSubscriptionBottomAction(),
            ],
          );

    if (widget.embedInShell) return body;
    return Scaffold(appBar: AppBar(title: const Text('ストア')), body: body);
  }
}
