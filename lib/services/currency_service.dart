import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';

class CurrencyService {
  static const _kCoins = 'wallet_coins_v1';
  static const _kGems = 'wallet_gems_v1';
  static const _kFragments = 'wallet_fragments_v1';

  static Future<Map<String, int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'coins': prefs.getInt(_kCoins) ?? 0,
      'gems': prefs.getInt(_kGems) ?? 0,
      'fragments': prefs.getInt(_kFragments) ?? 0,
    };
  }

  static Future<void> save(int coins, int gems, int fragments) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCoins, coins);
    await prefs.setInt(_kGems, gems);
    await prefs.setInt(_kFragments, fragments);
    // オンライン時はFirestoreへも反映（失敗は無視）
    try {
      await CloudService.saveDailyRecord({
        'wallet': {'coins': coins, 'gems': gems, 'fragments': fragments},
      });
    } catch (_) {}
  }

  static Future<int> addCoins(int delta) async {
    final w = await load();
    final v = (w['coins']! + delta).clamp(0, 1 << 31);
    await save(v, w['gems']!, w['fragments']!);
    return v;
  }

  static Future<int> addGems(int delta) async {
    final w = await load();
    final v = (w['gems']! + delta).clamp(0, 1 << 31);
    await save(w['coins']!, v, w['fragments']!);
    return v;
  }

  static Future<int> addFragments(int delta) async {
    final w = await load();
    final v = (w['fragments']! + delta).clamp(0, 1 << 31);
    await save(w['coins']!, w['gems']!, v);
    return v;
  }

  static Future<int> useCoins(int amount) async {
    final w = await load();
    final v = (w['coins']! - amount).clamp(0, 1 << 31);
    await save(v, w['gems']!, w['fragments']!);
    return v;
  }

  static Future<int> useGems(int amount) async {
    final w = await load();
    final v = (w['gems']! - amount).clamp(0, 1 << 31);
    await save(w['coins']!, v, w['fragments']!);
    return v;
  }
}
