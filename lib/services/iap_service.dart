import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/iap_purchase_ack_store.dart';

/// IAP (In-App Purchase) — Google Play / App Store の相談券パック購入。
class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  static IAPService get instance => _instance;

  IAPService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _isAvailable = false;
  List<ProductDetails> _products = [];
  String? _lastLoadError;

  /// 購入成功で相談券を付与したとき（UI 更新用）。
  void Function(int ticketsGranted, String productId)? onTicketsGranted;

  bool get isAvailable => _isAvailable;
  String? get lastLoadError => _lastLoadError;

  static List<String> get productIds =>
      ConsultationTicketPacksService.packs.map((p) => p.id).toList();

  /// IAP 初期化（アプリ起動時に1回）。
  Future<void> init() async {
    try {
      _isAvailable = await _iap.isAvailable();
      if (!_isAvailable) {
        debugPrint('[IAPService] billing not available on this device');
        return;
      }

      _subscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: _handleError,
      );

      await loadProducts();
    } catch (e, st) {
      _isAvailable = false;
      debugPrint('[IAPService] init failed: $e\n$st');
    }
  }

  /// Play / App Store から商品情報を取得。
  Future<void> loadProducts() async {
    _lastLoadError = null;
    if (!_isAvailable) return;

    final productIds = IAPService.productIds.toSet();
    final response = await _iap.queryProductDetails(productIds);

    if (response.error != null) {
      _lastLoadError = response.error!.message;
      debugPrint('[IAPService] queryProductDetails error: ${response.error}');
    }
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('[IAPService] not found on store: ${response.notFoundIDs}');
    }

    _products = response.productDetails
      ..sort((a, b) {
        final ta = ConsultationTicketPacksService.getPackById(a.id)?.tickets ?? 0;
        final tb = ConsultationTicketPacksService.getPackById(b.id)?.tickets ?? 0;
        return ta.compareTo(tb);
      });
  }

  ProductDetails? productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<ProductDetails> get products => List.unmodifiable(_products);

  /// 相談券パックを購入（消耗型）。
  Future<bool> buyProduct(ProductDetails product) async {
    if (!_isAvailable) return false;

    final purchaseParam = PurchaseParam(productDetails: product);

    if (Platform.isIOS) {
      final ios = _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await ios.showPriceConsentIfNeeded();
    }

    return _iap.buyConsumable(purchaseParam: purchaseParam, autoConsume: true);
  }

  Future<void> restorePurchases() async {
    if (!_isAvailable) return;
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) continue;

      if (purchase.status == PurchaseStatus.error) {
        _handlePurchaseError(purchase);
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final granted = await _grantConsultationTicketsIfNew(purchase);
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        if (granted != null && granted > 0) {
          onTicketsGranted?.call(granted, purchase.productID);
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      }
    }
  }

  /// 購入1件につき1回だけ相談券を付与。戻り値は付与枚数（スキップ時は null）。
  Future<int?> _grantConsultationTicketsIfNew(PurchaseDetails purchase) async {
    final purchaseId = purchase.purchaseID ?? '${purchase.productID}_${purchase.transactionDate}';
    final isNew = await IapPurchaseAckStore.markProcessedIfNew(purchaseId);
    if (!isNew) {
      debugPrint('[IAPService] skip duplicate purchase $purchaseId');
      return null;
    }

    final pack = ConsultationTicketPacksService.getPackById(purchase.productID);
    if (pack == null || pack.tickets <= 0) return null;

    await ConsultationTicketService.addNormalTickets(pack.tickets);
    debugPrint('[IAPService] granted ${pack.tickets} ticket(s) for ${purchase.productID}');
    return pack.tickets;
  }

  void _handleError(Object error) {
    debugPrint('[IAPService] purchase stream error: $error');
  }

  void _handlePurchaseError(PurchaseDetails purchase) {
    debugPrint('[IAPService] purchase error: ${purchase.error}');
  }

  void dispose() {
    _subscription?.cancel();
    onTicketsGranted = null;
  }
}
