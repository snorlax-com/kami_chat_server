import 'package:shared_preferences/shared_preferences.dart';

/// 同一購入トランザクションへの二重付与を防ぐ（復元・再起動時）。
class IapPurchaseAckStore {
  IapPurchaseAckStore._();

  static const _kKey = 'iap_processed_purchase_ids_v1';
  static const _kMaxIds = 300;

  /// 未処理なら記録して `true`。既に処理済みなら `false`。
  static Future<bool> markProcessedIfNew(String purchaseId) async {
    final id = purchaseId.trim();
    if (id.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final list = List<String>.from(prefs.getStringList(_kKey) ?? const []);
    if (list.contains(id)) return false;

    list.add(id);
    final trimmed = list.length > _kMaxIds ? list.sublist(list.length - _kMaxIds) : list;
    await prefs.setStringList(_kKey, trimmed);
    return true;
  }
}
