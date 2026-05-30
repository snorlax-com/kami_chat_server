import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';

class StorePage extends StatefulWidget {
  const StorePage({super.key, this.embedInShell = false});

  final bool embedInShell;

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  final IAPService _iap = IAPService.instance;
  bool _isLoading = true;
  int _consultationTickets = 0;
  String? _purchasingProductId;

  @override
  void initState() {
    super.initState();
    _iap.onTicketsGranted = _onTicketsGranted;
    _load();
  }

  @override
  void dispose() {
    if (_iap.onTicketsGranted == _onTicketsGranted) {
      _iap.onTicketsGranted = null;
    }
    super.dispose();
  }

  void _onTicketsGranted(int tickets, String productId) {
    if (!mounted) return;
    final pack = ConsultationTicketPacksService.getPackById(productId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${pack?.name ?? '相談券'}を購入しました（+$tickets枚）'),
      ),
    );
    unawaited(_load(refreshBalanceOnly: true));
  }

  Future<void> _load({bool refreshBalanceOnly = false}) async {
    if (!refreshBalanceOnly) {
      setState(() => _isLoading = true);
      await _iap.loadProducts();
    }
    final tickets = await ConsultationTicketService.normalTickets();
    if (!mounted) return;
    setState(() {
      _consultationTickets = tickets;
      _isLoading = false;
      _purchasingProductId = null;
    });
  }

  Future<void> _buyPack(ConsultationTicketPack pack) async {
    final product = _iap.productById(pack.id);
    if (product == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('この商品はまだストアに登録されていません。しばらくしてから再読み込みしてください。'),
        ),
      );
      return;
    }

    setState(() => _purchasingProductId = pack.id);
    try {
      final started = await _iap.buyProduct(product);
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('購入を開始できませんでした')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _purchasingProductId = null);
        await _load(refreshBalanceOnly: true);
      }
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      await _iap.restorePurchases();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('購入履歴を確認しました')),
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

  String _priceLabel(ConsultationTicketPack pack) {
    final product = _iap.productById(pack.id);
    if (product != null) return product.price;
    if (pack.referencePriceYen != null) {
      return '参考 ¥${pack.referencePriceYen}（ストア価格未連携）';
    }
    return '価格はストアで確認';
  }

  Widget _buildStatusBanner() {
    if (_iap.isAvailable) {
      final missing = ConsultationTicketPacksService.packs
          .where((p) => _iap.productById(p.id) == null)
          .map((p) => p.id)
          .toList();
      if (missing.isEmpty) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.orange.withValues(alpha: 0.15),
        child: Text(
          '一部の商品が Play/App Store に未登録です（${missing.length}件）。登録後「再読み込み」してください。',
          style: TextStyle(color: Colors.amber.shade200, fontSize: 12),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.red.withValues(alpha: 0.12),
      child: const Text(
        '課金機能を利用できません。Google Play ストアにログインした端末でお試しください。',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }

  Widget _buildPackTile(ConsultationTicketPack pack) {
    final product = _iap.productById(pack.id);
    final canBuy = product != null && _iap.isAvailable;
    final isBuying = _purchasingProductId == pack.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF141A2E),
      child: ListTile(
        leading: const Icon(Icons.confirmation_number, color: Colors.amberAccent, size: 32),
        title: Text(
          pack.name,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(pack.description, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Text(
              _priceLabel(pack),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: canBuy ? Colors.amber.shade300 : Colors.white38,
              ),
            ),
            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '商品ID: ${pack.id}',
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ),
          ],
        ),
        trailing: isBuying
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ElevatedButton(
                onPressed: canBuy ? () => _buyPack(pack) : null,
                child: const Text('購入'),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  border: const Border(bottom: BorderSide(color: Colors.white12)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.confirmation_number_outlined, color: Colors.amberAccent),
                        const SizedBox(width: 8),
                        Text(
                          '相談券: $_consultationTickets 枚',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '1枚で占い相談を1回送信できます',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13),
                    ),
                  ],
                ),
              ),
              _buildStatusBanner(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const Text(
                        '相談券パック',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...ConsultationTicketPacksService.packs.map(_buildPackTile),
                      const SizedBox(height: 8),
                      Text(
                        '購入は Google Play / App Store 経由で処理されます。相談券は端末に保存され、送信のたびに1枚消費されます。',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                      ),
                      if (_iap.lastLoadError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          '読み込み: ${_iap.lastLoadError}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _load,
                        child: const Text('再読み込み'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: _isLoading ? null : _restorePurchases,
                        child: const Text('購入を復元'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

    if (widget.embedInShell) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ストア'),
        actions: [
          IconButton(
            tooltip: '再読み込み',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }
}
