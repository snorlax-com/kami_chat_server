import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/services/gem_packs_service.dart';
import 'package:kami_face_oracle/services/currency_service.dart';
import 'dart:io';

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  final IAPService _iap = IAPService.instance;
  List<ProductDetails> _products = [];
  bool _isLoading = true;
  int _coins = 0;
  int _gems = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _iap.loadProducts();
    final wallet = await CurrencyService.load();
    setState(() {
      _products = _iap.products;
      _coins = wallet['coins']!;
      _gems = wallet['gems']!;
      _isLoading = false;
    });
  }

  Future<void> _buyProduct(ProductDetails product) async {
    setState(() => _isLoading = true);

    try {
      final success = await _iap.buyProduct(product);
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('購入に失敗しました')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    } finally {
      await _load();
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      await _iap.restorePurchases();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('購入履歴を復元しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('復元エラー: $e')),
        );
      }
    } finally {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ストア'),
        actions: [
          if (!Platform.isIOS)
            TextButton(
              onPressed: _restorePurchases,
              child: const Text('復元'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 残高表示
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    border: Border(
                      bottom: BorderSide(color: Colors.white12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.monetization_on, color: Colors.amberAccent),
                          const SizedBox(width: 4),
                          Text('$_coins', style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.diamond, color: Colors.lightBlueAccent),
                          const SizedBox(width: 4),
                          Text('$_gems', style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ],
                  ),
                ),
                // 商品リスト
                Expanded(
                  child: _products.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.store_mall_directory, size: 64, color: Colors.white38),
                              const SizedBox(height: 16),
                              const Text(
                                '商品が見つかりませんでした',
                                style: TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _load,
                                child: const Text('再読み込み'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            final product = _products[index];
                            final pack = GemPacksService.getPackById(product.id);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: const Icon(Icons.diamond, color: Colors.lightBlueAccent, size: 32),
                                title: Text(
                                  pack?.name ?? product.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(pack?.description ?? product.description),
                                    const SizedBox(height: 4),
                                    Text(
                                      product.price,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () => _buyProduct(product),
                                  child: const Text('購入'),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                if (Platform.isIOS)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextButton(
                      onPressed: _restorePurchases,
                      child: const Text('購入を復元'),
                    ),
                  ),
              ],
            ),
    );
  }
}
