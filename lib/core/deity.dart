class Deity {
  final String id; // "amatera"
  final String nameJa; // "Amatera"
  final String nameEn; // "Solar Goddess"
  final String role; // "太陽の女神"
  final String colorHex; // 主要カラー
  final String symbolAsset; // assets/symbols/amatera.png
  // タイプ4軸: 表情 明/静, 肌 潤/乾, 骨格 直/丸, 主張 強/柔 → 0 or 1で表現
  final int expr; // expression: 1=明,0=静
  final int skin; // skin: 1=潤,0=乾
  final int shape; // shape: 1=直,0=丸
  final int claim; // claim: 1=強,0=柔
  final String shortMessage;

  const Deity({
    required this.id,
    required this.nameJa,
    required this.nameEn,
    required this.role,
    required this.colorHex,
    required this.symbolAsset,
    required this.expr,
    required this.skin,
    required this.shape,
    required this.claim,
    required this.shortMessage,
  });
}
