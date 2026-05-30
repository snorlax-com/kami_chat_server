import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 消耗型相談券の種別。
enum ConsultationTicketProductType { normal, urgent }

/// Google Play 消耗型相談券（通常 / 至急）。
class ConsultationTicketPack {
  const ConsultationTicketPack({
    required this.id,
    required this.name,
    required this.tickets,
    required this.description,
    required this.ticketType,
    this.referencePriceYen,
  });

  final String id;
  final String name;
  final int tickets;
  final String description;
  final ConsultationTicketProductType ticketType;
  final int? referencePriceYen;

  bool get isUrgent => ticketType == ConsultationTicketProductType.urgent;
}

class ConsultationTicketPacksService {
  ConsultationTicketPacksService._();

  static const _assetPath = 'assets/data/consultation_ticket_products.json';
  static List<ConsultationTicketPack>? _loaded;

  static const List<ConsultationTicketPack> _fallbackPacks = [
    ConsultationTicketPack(
      id: 'normal_ticket_600',
      name: '通常質問券 1枚',
      tickets: 1,
      description: '通常の占い相談を1回分',
      ticketType: ConsultationTicketProductType.normal,
      referencePriceYen: 600,
    ),
    ConsultationTicketPack(
      id: 'urgent_ticket_10000',
      name: '至急質問券 1枚',
      tickets: 1,
      description: '至急の占い相談を1回分',
      ticketType: ConsultationTicketProductType.urgent,
      referencePriceYen: 10000,
    ),
  ];

  static List<ConsultationTicketPack> get packs => _loaded ?? _fallbackPacks;

  static ConsultationTicketPack? get normalTicketProduct {
    for (final p in packs) {
      if (p.ticketType == ConsultationTicketProductType.normal) return p;
    }
    return null;
  }

  static ConsultationTicketPack? get urgentTicketProduct {
    for (final p in packs) {
      if (p.ticketType == ConsultationTicketProductType.urgent) return p;
    }
    return null;
  }

  static Future<void> ensureLoaded() async {
    if (_loaded != null) return;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final list = json['products'] as List<dynamic>? ?? const [];
      final parsed = <ConsultationTicketPack>[];
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        final typeRaw = item['ticketType']?.toString() ?? 'normal';
        parsed.add(
          ConsultationTicketPack(
            id: id,
            name: item['name']?.toString() ?? id,
            tickets: (item['tickets'] as num?)?.toInt() ?? 1,
            description: item['description']?.toString() ?? '',
            ticketType: typeRaw == 'urgent'
                ? ConsultationTicketProductType.urgent
                : ConsultationTicketProductType.normal,
            referencePriceYen: (item['priceYen'] as num?)?.toInt(),
          ),
        );
      }
      if (parsed.isNotEmpty) {
        _loaded = parsed;
        return;
      }
    } catch (e, st) {
      debugPrint('[ConsultationTicketPacksService] load failed: $e\n$st');
    }
    _loaded = List<ConsultationTicketPack>.from(_fallbackPacks);
  }

  static ConsultationTicketPack? getPackById(String id) {
    for (final p in packs) {
      if (p.id == id) return p;
    }
    return null;
  }

  static bool isConsumableProduct(String id) => getPackById(id) != null;
}
