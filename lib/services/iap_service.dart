import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/config/consultation_subscription_config.dart';
import 'package:kami_face_oracle/config/play_billing_products.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/billing_log.dart';
import 'package:kami_face_oracle/services/billing_server_sync_service.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/iap_purchase_ack_store.dart';
import 'package:kami_face_oracle/services/play_billing_error_mapper.dart';
import 'package:kami_face_oracle/services/play_install_service.dart';
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:kami_face_oracle/services/subscription_bonus_service.dart';

/// Google Play Billing — 月額サブスク + 消耗型相談券。
class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  static IAPService get instance => _instance;

  IAPService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _isAvailable = false;
  bool _playSubscriptionVerified = false;
  List<ProductDetails> _products = [];
  String? _lastLoadError;
  List<String> _notFoundProductIds = [];
  final Set<String> _pendingProductIds = {};
  Future<void>? _readyFuture;

  void Function(int ticketsGranted, String productId, {bool isUrgent})? onTicketsGranted;
  void Function(String productId)? onPurchaseCanceled;
  void Function(String productId, String? message)? onPurchaseFailed;
  void Function(String productId)? onPurchasePending;
  void Function(bool isActive, {int bonusTickets})? onSubscriptionUpdated;

  bool get isAvailable => _isAvailable;
  String? get lastLoadError => _lastLoadError;
  List<String> get notFoundProductIds => List.unmodifiable(_notFoundProductIds);
  Set<String> get pendingProductIds => Set.unmodifiable(_pendingProductIds);

  bool isProductPending(String productId) => _pendingProductIds.contains(productId);

  bool get hasVerifiedPlaySubscription => _playSubscriptionVerified;
  bool get isPlayBillingReady => _isAvailable && hasPlayCatalog;

  static Set<String> get allProductIds => {
        ...PlayBillingProducts.allQueryProductIds,
        ConsultationSubscriptionConfig.productId,
        ...ConsultationTicketPacksService.packs.map((p) => p.id),
      };

  Future<void> init() async => ensureReady();

  Future<void> ensureReady() async {
    _readyFuture ??= _ensureReadyImpl();
    await _readyFuture;
  }

  Future<void> refreshCatalog() async {
    await ensureReady();
    await loadProducts();
    await syncSubscriptionStatusFromPlay();
    await _invalidateUnverifiedSubscriptionIfNeeded();
  }

  Future<void> _ensureReadyImpl() async {
    await ConsultationTicketPacksService.ensureLoaded();
    await ConsultationSubscriptionConfig.ensureLoaded();

    try {
      _isAvailable = await _iap.isAvailable();
      BillingLog.info('isAvailable=$_isAvailable productIds=$allProductIds');
      if (!_isAvailable) {
        BillingLog.warn('billing not available — Play Store ログイン・内部テスト参加を確認');
        return;
      }

      _subscription ??= _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: _handleError,
      );

      await loadProducts();
      await syncSubscriptionStatusFromPlay();
      await _invalidateUnverifiedSubscriptionIfNeeded();
    } catch (e, st) {
      _isAvailable = false;
      BillingLog.error('init failed', e, st);
    }
  }

  Future<void> loadProducts() async {
    await ConsultationTicketPacksService.ensureLoaded();
    await ConsultationSubscriptionConfig.ensureLoaded();
    _lastLoadError = null;
    if (!_isAvailable) return;

    final response = await _iap.queryProductDetails(allProductIds);
    if (response.error != null) {
      _lastLoadError = PlayBillingErrorMapper.userMessage(response.error);
      BillingLog.error('queryProductDetails', response.error);
    }
    if (response.notFoundIDs.isNotEmpty) {
      _notFoundProductIds = response.notFoundIDs;
      BillingLog.warn('notFoundIDs=${response.notFoundIDs} — Play Console ID・反映待ちを確認');
    } else {
      _notFoundProductIds = [];
    }

    _products = response.productDetails;
    BillingLog.info(
      'catalog loaded: ${_products.length} [${_products.map((p) => p.id).join(", ")}]',
    );
    final sub = subscriptionProduct;
    if (sub != null) {
      BillingLog.info('subscription ready id=${sub.id} price=${sub.price}');
    } else {
      BillingLog.warn(
        'subscription NOT in catalog (canonical=${ConsultationSubscriptionConfig.productId})',
      );
    }
  }

  Future<void> _invalidateUnverifiedSubscriptionIfNeeded() async {
    if (!StoreBillingConfig.requirePlayVerifiedAccess) return;
    if (!_isAvailable || !hasSubscriptionInCatalog) {
      _playSubscriptionVerified = false;
      if (await _preserveSideloadTestSubscription()) {
        BillingLog.info('keeping sideload test subscription');
        return;
      }
      await ConsultationSubscriptionService.setActive(false);
      BillingLog.info('cleared unverified local subscription (Play not ready)');
    }
  }

  ProductDetails? productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  ProductDetails? productForPack(ConsultationTicketPack pack) {
    final direct = productById(pack.id);
    if (direct != null) return direct;
    final legacy = pack.isUrgent
        ? PlayBillingProducts.legacyTicketUrgent10000
        : PlayBillingProducts.legacyTicketNormal600;
    return productById(legacy);
  }

  ProductDetails? get subscriptionProduct {
    final canonical = ConsultationSubscriptionConfig.productId;
    return productById(canonical) ??
        productById(PlayBillingProducts.legacySubscriptionMonthly500);
  }

  bool get hasSubscriptionInCatalog => subscriptionProduct != null;
  bool get hasPlayCatalog => _products.isNotEmpty;

  bool canPurchaseViaPlay(ConsultationTicketPack pack) =>
      _isAvailable && productForPack(pack) != null;

  bool get canSubscribeViaPlay => _isAvailable && subscriptionProduct != null;

  Future<StorePurchaseOutcome> purchaseConsumable(ConsultationTicketPack pack) async {
    final product = productForPack(pack);
    if (product == null || !_isAvailable) return const StorePurchaseUnavailable();
    final started = await _buyConsumable(product);
    BillingLog.purchase('buyConsumable ${pack.id} started=$started');
    return started
        ? StorePurchasePlayLaunched(pack.id)
        : StorePurchasePlayLaunchFailed(pack.id);
  }

  Future<StorePurchaseOutcome> subscribeViaPlay() async {
    final product = subscriptionProduct;
    if (product == null || !_isAvailable) return const StorePurchaseUnavailable();
    final started = await _buySubscription(product);
    BillingLog.purchase(
      'buySubscription ${ConsultationSubscriptionConfig.productId} started=$started',
    );
    return started
        ? StorePurchasePlayLaunched(ConsultationSubscriptionConfig.productId)
        : StorePurchasePlayLaunchFailed(ConsultationSubscriptionConfig.productId);
  }

  Future<bool> _buyConsumable(ProductDetails product) async {
    if (!_isAvailable) return false;
    await _preparePlatformPurchase();
    if (Platform.isAndroid && product is GooglePlayProductDetails) {
      return _iap.buyConsumable(
        purchaseParam: GooglePlayPurchaseParam(productDetails: product),
        autoConsume: true,
      );
    }
    return _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
      autoConsume: true,
    );
  }

  Future<bool> _buySubscription(ProductDetails product) async {
    if (!_isAvailable) return false;
    await _preparePlatformPurchase();
    if (Platform.isAndroid && product is GooglePlayProductDetails) {
      var token = product.offerToken;
      if (token == null || token.isEmpty) {
        BillingLog.warn('buySubscription missing offerToken id=${product.id} — reload catalog');
        await loadProducts();
        final refreshed = subscriptionProduct;
        if (refreshed is GooglePlayProductDetails) {
          token = refreshed.offerToken;
        }
      }
      if (token == null || token.isEmpty) {
        BillingLog.error('buySubscription still missing offerToken', product.id);
        return false;
      }
      return _iap.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: product,
          offerToken: token,
        ),
      );
    }
    return _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
  }

  Future<void> _preparePlatformPurchase() async {
    if (Platform.isIOS) {
      final ios = _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await ios.showPriceConsentIfNeeded();
    }
  }

  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      BillingLog.warn('restorePurchases skipped: billing unavailable');
      return;
    }
    BillingLog.info('restorePurchases start');
    await _iap.restorePurchases();
    await syncSubscriptionStatusFromPlay();
    BillingLog.info('restorePurchases done');
  }

  static Future<bool> _preserveSideloadTestSubscription() async {
    await PlayInstallService.ensureLoaded();
    if (!PlayInstallService.isSideloadInstall) return false;
    return SideloadBillingService.hasSideloadTestPurchase();
  }

  Future<void> syncSubscriptionStatusFromPlay() async {
    if (!_isAvailable) {
      if (StoreBillingConfig.requirePlayVerifiedAccess) {
        _playSubscriptionVerified = false;
        if (await _preserveSideloadTestSubscription()) {
          BillingLog.info('syncSubscription: keep sideload test (billing unavailable)');
          return;
        }
        final wasActive = await ConsultationSubscriptionService.isActive();
        await ConsultationSubscriptionService.setActive(false);
        if (wasActive) onSubscriptionUpdated?.call(false, bonusTickets: 0);
      }
      return;
    }

    var active = false;
    if (Platform.isAndroid) {
      final android = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await android.queryPastPurchases();
      if (response.error != null) {
        BillingLog.error('queryPastPurchases', response.error);
      } else {
        for (final purchase in response.pastPurchases) {
          if (!PlayBillingProducts.isSubscriptionProduct(purchase.productID)) continue;
          if (_isActivePurchaseStatus(purchase.status)) {
            active = true;
            await _acknowledgeIfNeeded(purchase, fromRestore: true);
          }
        }
      }
    } else {
      active = await ConsultationSubscriptionService.isActive();
    }

    if (!active && await _preserveSideloadTestSubscription()) {
      active = true;
      BillingLog.info('syncSubscription: sideload test preserved');
    }

    _playSubscriptionVerified = active;
    BillingLog.info('syncSubscription active=$active verified=$_playSubscriptionVerified');

    final wasActive = await ConsultationSubscriptionService.isActive();
    await ConsultationSubscriptionService.setActive(active);
    if (!wasActive && active) {
      final bonus = await SubscriptionBonusService.grantFirstBonusIfEligible();
      onSubscriptionUpdated?.call(true, bonusTickets: bonus);
    } else if (wasActive != active) {
      onSubscriptionUpdated?.call(active, bonusTickets: 0);
      AppNavigation.notifyStoreAccessChanged();
    }
  }

  static bool _isActivePurchaseStatus(PurchaseStatus status) =>
      status == PurchaseStatus.purchased || status == PurchaseStatus.restored;

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final productId = purchase.productID;
      final canonicalId = PlayBillingProducts.resolveCanonicalProductId(productId);

      if (purchase.status == PurchaseStatus.pending) {
        _pendingProductIds.add(canonicalId);
        BillingLog.purchase('pending product=$productId');
        onPurchasePending?.call(canonicalId);
        continue;
      }

      _pendingProductIds.remove(canonicalId);

      if (purchase.status == PurchaseStatus.error) {
        final msg = PlayBillingErrorMapper.userMessage(purchase.error, productId: productId);
        BillingLog.error('purchase error product=$productId', purchase.error?.message);
        onPurchaseFailed?.call(canonicalId, msg);
        await _acknowledgeIfNeeded(purchase);
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        BillingLog.purchase('canceled product=$productId');
        onPurchaseCanceled?.call(canonicalId);
        await _acknowledgeIfNeeded(purchase);
        continue;
      }

      if (_isActivePurchaseStatus(purchase.status)) {
        BillingLog.purchase(
          'success product=$productId status=${purchase.status} pendingComplete=${purchase.pendingCompletePurchase}',
        );
        final result = await _grantBenefitIfNew(purchase);
        await _acknowledgeIfNeeded(purchase);

        if (PlayBillingProducts.isSubscriptionProduct(productId)) {
          await ConsultationSubscriptionService.setActive(true);
          _playSubscriptionVerified = true;
          onSubscriptionUpdated?.call(true, bonusTickets: result.bonusTickets);
        }
        if (result.ticketsGranted > 0) {
          onTicketsGranted?.call(
            result.ticketsGranted,
            canonicalId,
            isUrgent: result.isUrgent,
          );
          BillingLog.info('iap ticketsGranted backup return');
          unawaited(AppNavigation.completeTicketPackPurchaseFromStore());
        }
      }
    }
  }

  /// Android: acknowledgePurchase / completePurchase（消耗型は autoConsume）。
  Future<void> _acknowledgeIfNeeded(PurchaseDetails purchase, {bool fromRestore = false}) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(purchase);
      BillingLog.purchase(
        'acknowledged product=${purchase.productID} restore=$fromRestore',
      );
    } catch (e, st) {
      BillingLog.error('completePurchase failed', e, st);
    }
  }

  Future<({int ticketsGranted, int bonusTickets, bool isUrgent})> _grantBenefitIfNew(
    PurchaseDetails purchase,
  ) async {
    final productId = purchase.productID;
    final purchaseId = purchase.purchaseID ?? '${productId}_${purchase.transactionDate}';
    final isNew = await IapPurchaseAckStore.markProcessedIfNew(purchaseId);
    if (!isNew) {
      BillingLog.info('skip duplicate purchaseId=$purchaseId');
      return (ticketsGranted: 0, bonusTickets: 0, isUrgent: false);
    }

    final token = _extractPurchaseToken(purchase);
    final orderId = _extractOrderId(purchase);
    final timeMs = _extractPurchaseTimeMs(purchase);
    final isSub = PlayBillingProducts.isSubscriptionProduct(productId);

    unawaited(
      BillingServerSyncService.syncPurchase(
        productId: productId,
        purchaseId: purchaseId,
        purchaseToken: token,
        orderId: orderId,
        purchaseTimeMs: timeMs,
        isSubscription: isSub,
        isRestore: purchase.status == PurchaseStatus.restored,
      ),
    );

    if (isSub) {
      final bonus = await SubscriptionBonusService.grantFirstBonusIfEligible();
      BillingLog.purchase('subscription active firstBonus=$bonus');
      return (ticketsGranted: bonus, bonusTickets: bonus, isUrgent: false);
    }

    final pack = ConsultationTicketPacksService.getPackById(productId);
    if (pack == null || pack.tickets <= 0) {
      BillingLog.warn('unknown consumable product=$productId');
      return (ticketsGranted: 0, bonusTickets: 0, isUrgent: false);
    }

    if (pack.isUrgent) {
      await ConsultationTicketService.addPriorityTickets(pack.tickets);
      BillingLog.purchase('granted urgent ${pack.tickets}');
      return (ticketsGranted: pack.tickets, bonusTickets: 0, isUrgent: true);
    }

    await ConsultationTicketService.addNormalTickets(pack.tickets);
    BillingLog.purchase('granted normal ${pack.tickets}');
    return (ticketsGranted: pack.tickets, bonusTickets: 0, isUrgent: false);
  }

  static String? _extractPurchaseToken(PurchaseDetails purchase) {
    if (Platform.isAndroid && purchase is GooglePlayPurchaseDetails) {
      return purchase.billingClientPurchase.purchaseToken;
    }
    return null;
  }

  static String? _extractOrderId(PurchaseDetails purchase) {
    if (Platform.isAndroid && purchase is GooglePlayPurchaseDetails) {
      return purchase.billingClientPurchase.orderId;
    }
    return purchase.purchaseID;
  }

  static int? _extractPurchaseTimeMs(PurchaseDetails purchase) {
    if (Platform.isAndroid && purchase is GooglePlayPurchaseDetails) {
      return purchase.billingClientPurchase.purchaseTime;
    }
    final raw = purchase.transactionDate;
    if (raw == null) return null;
    final parsed = int.tryParse(raw);
    return parsed;
  }

  void _handleError(Object error) {
    BillingLog.error('purchase stream error', error);
    onPurchaseFailed?.call('', PlayBillingErrorMapper.userMessage(error));
  }

  void dispose() {
    _subscription?.cancel();
    onTicketsGranted = null;
    onPurchaseCanceled = null;
    onPurchaseFailed = null;
    onPurchasePending = null;
    onSubscriptionUpdated = null;
  }
}

sealed class StorePurchaseOutcome {
  const StorePurchaseOutcome();
}

final class StorePurchasePlayLaunched extends StorePurchaseOutcome {
  const StorePurchasePlayLaunched(this.productId);
  final String productId;
}

final class StorePurchasePlayLaunchFailed extends StorePurchaseOutcome {
  const StorePurchasePlayLaunchFailed(this.productId);
  final String productId;
}

final class StorePurchaseUnavailable extends StorePurchaseOutcome {
  const StorePurchaseUnavailable();
}
