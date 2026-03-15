import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:kami_face_oracle/services/currency_service.dart';

/// IAP (In-App Purchase) サービス
/// Google Play Billing / Apple App Store IAP統合
class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  static IAPService get instance => _instance;

  IAPService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _isAvailable = false;
  List<ProductDetails> _products = [];

  /// IAPサービスの初期化
  Future<void> init() async {
    _isAvailable = await _iap.isAvailable();
    if (!_isAvailable) return;

    // 購入ストリームの監視
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) => _handleError(error),
    );

    // 未処理の購入を復元
    await _restorePurchases();
  }

  /// 利用可能な商品IDのリスト（gem_packsから取得）
  static const List<String> _productIds = [
    'gem_pack_small', // 10ジェム (100円相当)
    'gem_pack_medium', // 50ジェム (450円相当)
    'gem_pack_large', // 100ジェム (800円相当)
    'gem_pack_xlarge', // 200ジェム (1500円相当)
  ];

  /// 商品詳細を取得
  Future<void> loadProducts() async {
    if (!_isAvailable) return;

    final Set<String> productIds = _productIds.toSet();
    final ProductDetailsResponse response = await _iap.queryProductDetails(productIds);

    if (response.notFoundIDs.isNotEmpty) {
      // 一部の商品が見つからない場合でも続行
    }

    _products = response.productDetails;
  }

  /// 商品一覧を取得
  List<ProductDetails> get products => _products;

  /// 商品を購入
  Future<bool> buyProduct(ProductDetails product) async {
    if (!_isAvailable) return false;

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);

    if (Platform.isIOS) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
          _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await iosPlatformAddition.showPriceConsentIfNeeded();
    }

    return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// 購入履歴を復元
  Future<void> restorePurchases() async {
    await _restorePurchases();
  }

  /// 購入更新のハンドラー
  void _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        // 購入保留中（承認待ちなど）
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        // エラー処理
        _handlePurchaseError(purchase);
        await _iap.completePurchase(purchase);
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
        // 購入成功：ジェムを付与
        await _grantGems(purchase);
        await _iap.completePurchase(purchase);
      }

      if (purchase.status == PurchaseStatus.canceled) {
        // キャンセル
        await _iap.completePurchase(purchase);
      }
    }
  }

  /// ジェム付与ロジック
  Future<void> _grantGems(PurchaseDetails purchase) async {
    final productId = purchase.productID;
    int gems = 0;

    // 商品IDに応じてジェム数を決定
    switch (productId) {
      case 'gem_pack_small':
        gems = 10;
        break;
      case 'gem_pack_medium':
        gems = 50;
        break;
      case 'gem_pack_large':
        gems = 100;
        break;
      case 'gem_pack_xlarge':
        gems = 200;
        break;
      default:
        // 未知の商品ID
        return;
    }

    // ジェムを付与
    await CurrencyService.addGems(gems);
  }

  /// 購入の復元
  Future<void> _restorePurchases() async {
    if (!_isAvailable) return;

    await _iap.restorePurchases();
  }

  /// エラーハンドリング
  void _handleError(dynamic error) {
    // エラーログ（実際のアプリではFirebase Crashlyticsなどに送信）
  }

  void _handlePurchaseError(PurchaseDetails purchase) {
    // 購入エラーの処理（実際のアプリではユーザーに通知）
  }

  /// リソースのクリーンアップ
  void dispose() {
    _subscription?.cancel();
  }
}
