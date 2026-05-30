import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:kami_face_oracle/config/consultation_subscription_config.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/billing_log.dart';
import 'package:kami_face_oracle/services/iap_purchase_ack_store.dart';
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
  Future<void>? _readyFuture;

  void Function(int ticketsGranted, String productId, {bool isUrgent})? onTicketsGranted;
  void Function(String productId)? onPurchaseCanceled;
  void Function(String productId, String? message)? onPurchaseFailed;
  void Function(bool isActive, {int bonusTickets})? onSubscriptionUpdated;

  bool get isAvailable => _isAvailable;
  String? get lastLoadError => _lastLoadError;
  List<String> get notFoundProductIds => List.unmodifiable(_notFoundProductIds);

  /// Play の queryPastPurchases / 購入完了で確認できたサブスク状態。
  bool get hasVerifiedPlaySubscription => _playSubscriptionVerified;

  /// 課金 UI を起動できる（Billing 利用可 + 商品取得済み）。
  bool get isPlayBillingReady => _isAvailable && hasPlayCatalog;

  static Set<String> get allProductIds => {
        ...ConsultationTicketPacksService.packs.map((p) => p.id),
        ConsultationSubscriptionConfig.productId,
      };

  Future<void> init() async => ensureReady();

  Future<void> ensureReady() async {
    _readyFuture ??= _ensureReadyImpl();
    await _readyFuture;
  }

  /// ストア再読み込み用（初期化済み前提で商品だけ再取得）。
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
        BillingLog.info('billing not available');
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
      _lastLoadError = response.error!.message;
      BillingLog.error('queryProductDetails', response.error);
    }
    if (response.notFoundIDs.isNotEmpty) {
      _notFoundProductIds = response.notFoundIDs;
      BillingLog.info('notFoundIDs=${response.notFoundIDs}');
    } else {
      _notFoundProductIds = [];
    }

    _products = response.productDetails;
    BillingLog.info(
      'catalog loaded: ${_products.length} products [${_products.map((p) => p.id).join(", ")}]',
    );
  }

  Future<void> _invalidateUnverifiedSubscriptionIfNeeded() async {
    if (!StoreBillingConfig.requirePlayVerifiedAccess) return;
    if (!_isAvailable || !hasPlayCatalog) {
      _playSubscriptionVerified = false;
      if (await SideloadBillingService.isSideloadTestSubscriptionValid()) {
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

  ProductDetails? get subscriptionProduct => productById(ConsultationSubscriptionConfig.productId);

  bool get hasPlayCatalog => _products.isNotEmpty;

  bool canPurchaseViaPlay(ConsultationTicketPack pack) =>
      _isAvailable && productById(pack.id) != null;

  bool get canSubscribeViaPlay => _isAvailable && subscriptionProduct != null;

  Future<StorePurchaseOutcome> purchaseConsumable(ConsultationTicketPack pack) async {
    final product = productById(pack.id);
    if (product == null || !_isAvailable) return const StorePurchaseUnavailable();
    final started = await _buyConsumable(product);
    BillingLog.info('buyConsumable ${pack.id} started=$started');
    return started
        ? StorePurchasePlayLaunched(pack.id)
        : StorePurchasePlayLaunchFailed(pack.id);
  }

  Future<StorePurchaseOutcome> subscribeViaPlay() async {
    final product = subscriptionProduct;
    if (product == null || !_isAvailable) return const StorePurchaseUnavailable();
    final started = await _buySubscription(product);
    BillingLog.info('buySubscription ${ConsultationSubscriptionConfig.productId} started=$started offerToken=${product is GooglePlayProductDetails ? product.offerToken : null}');
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
      return _iap.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: product,
          offerToken: product.offerToken,
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
    if (!_isAvailable) return;
    await _iap.restorePurchases();
    await syncSubscriptionStatusFromPlay();
  }

  Future<void> syncSubscriptionStatusFromPlay() async {
    if (!_isAvailable) {
      if (StoreBillingConfig.requirePlayVerifiedAccess) {
        _playSubscriptionVerified = false;
        final wasActive = await ConsultationSubscriptionService.isActive();
        await ConsultationSubscriptionService.setActive(false);
        if (wasActive) {
          onSubscriptionUpdated?.call(false, bonusTickets: 0);
        }
      }
      return;
    }

    var active = false;
    if (Platform.isAndroid) {
      final android = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await android.queryPastPurchases();
      if (response.error == null) {
        for (final purchase in response.pastPurchases) {
          if (!ConsultationSubscriptionConfig.isSubscriptionProduct(purchase.productID)) continue;
          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            active = true;
            break;
          }
        }
      }
    } else {
      active = await ConsultationSubscriptionService.isActive();
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
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final productId = purchase.productID;

      if (purchase.status == PurchaseStatus.pending) continue;

      if (purchase.status == PurchaseStatus.error) {
        BillingLog.error('purchase error product=$productId', purchase.error?.message);
        onPurchaseFailed?.call(productId, purchase.error?.message);
        if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        onPurchaseCanceled?.call(productId);
        if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final result = await _grantBenefitIfNew(purchase);
        if (purchase.pendingCompletePurchase) await _iap.completePurchase(purchase);

        if (ConsultationSubscriptionConfig.isSubscriptionProduct(productId)) {
          await ConsultationSubscriptionService.setActive(true);
          _playSubscriptionVerified = true;
          onSubscriptionUpdated?.call(true, bonusTickets: result.bonusTickets);
        }
        if (result.ticketsGranted > 0) {
          onTicketsGranted?.call(
            result.ticketsGranted,
            productId,
            isUrgent: result.isUrgent,
          );
        }
      }
    }
  }

  Future<({int ticketsGranted, int bonusTickets, bool isUrgent})> _grantBenefitIfNew(
    PurchaseDetails purchase,
  ) async {
    final purchaseId = purchase.purchaseID ?? '${purchase.productID}_${purchase.transactionDate}';
    final isNew = await IapPurchaseAckStore.markProcessedIfNew(purchaseId);
    if (!isNew) return (ticketsGranted: 0, bonusTickets: 0, isUrgent: false);

    if (ConsultationSubscriptionConfig.isSubscriptionProduct(purchase.productID)) {
      final bonus = await SubscriptionBonusService.grantFirstBonusIfEligible();
      BillingLog.info('subscription active, first bonus=$bonus');
      return (ticketsGranted: bonus, bonusTickets: bonus, isUrgent: false);
    }

    final pack = ConsultationTicketPacksService.getPackById(purchase.productID);
    if (pack == null || pack.tickets <= 0) {
      return (ticketsGranted: 0, bonusTickets: 0, isUrgent: false);
    }

    if (pack.isUrgent) {
      await ConsultationTicketService.addPriorityTickets(pack.tickets);
      BillingLog.info('granted urgent ${pack.tickets}');
      return (ticketsGranted: pack.tickets, bonusTickets: 0, isUrgent: true);
    }

    await ConsultationTicketService.addNormalTickets(pack.tickets);
    BillingLog.info('granted normal ${pack.tickets}');
    return (ticketsGranted: pack.tickets, bonusTickets: 0, isUrgent: false);
  }

  void _handleError(Object error) {
    BillingLog.error('purchase stream error', error);
  }

  void dispose() {
    _subscription?.cancel();
    onTicketsGranted = null;
    onPurchaseCanceled = null;
    onPurchaseFailed = null;
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
