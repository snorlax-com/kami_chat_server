/// ストアで販売する相談券パック（IAP 商品 ID は [IAPService] と一致させる）。
class ConsultationTicketPack {
  const ConsultationTicketPack({
    required this.id,
    required this.name,
    required this.tickets,
    required this.description,
    this.referencePriceYen,
  });

  final String id;
  final String name;
  final int tickets;
  final String description;

  /// Play 未連携時の参考表示用（実際の課金額はストアの価格が優先）。
  final int? referencePriceYen;
}

class ConsultationTicketPacksService {
  ConsultationTicketPacksService._();

  static const List<ConsultationTicketPack> packs = [
    ConsultationTicketPack(
      id: 'gem_pack_small',
      name: '相談券 1枚',
      tickets: 1,
      description: '占い相談を1回分',
      referencePriceYen: 120,
    ),
    ConsultationTicketPack(
      id: 'gem_pack_medium',
      name: '相談券 5枚',
      tickets: 5,
      description: '占い相談を5回分（お得）',
      referencePriceYen: 480,
    ),
    ConsultationTicketPack(
      id: 'gem_pack_large',
      name: '相談券 10枚',
      tickets: 10,
      description: '占い相談を10回分',
      referencePriceYen: 880,
    ),
    ConsultationTicketPack(
      id: 'gem_pack_xlarge',
      name: '相談券 20枚',
      tickets: 20,
      description: '占い相談を20回分',
      referencePriceYen: 1580,
    ),
  ];

  static ConsultationTicketPack? getPackById(String id) {
    for (final p in packs) {
      if (p.id == id) return p;
    }
    return null;
  }
}
