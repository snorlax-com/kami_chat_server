/// ジェムパックの定義（価格は実際のIAP商品と一致させる必要がある）
class GemPack {
  final String id;
  final String name;
  final int gems;
  final String description;

  GemPack({
    required this.id,
    required this.name,
    required this.gems,
    required this.description,
  });
}

class GemPacksService {
  static final List<GemPack> packs = [
    GemPack(
      id: 'gem_pack_small',
      name: '小さなジェムパック',
      gems: 10,
      description: '10ジェム（通常価格の100円相当）',
    ),
    GemPack(
      id: 'gem_pack_medium',
      name: '中サイズジェムパック',
      gems: 50,
      description: '50ジェム（通常価格の450円相当・10%オフ）',
    ),
    GemPack(
      id: 'gem_pack_large',
      name: '大きなジェムパック',
      gems: 100,
      description: '100ジェム（通常価格の800円相当・20%オフ）',
    ),
    GemPack(
      id: 'gem_pack_xlarge',
      name: '特大ジェムパック',
      gems: 200,
      description: '200ジェム（通常価格の1500円相当・25%オフ）',
    ),
  ];

  static GemPack? getPackById(String id) {
    try {
      return packs.firstWhere((pack) => pack.id == id);
    } catch (_) {
      return null;
    }
  }
}
