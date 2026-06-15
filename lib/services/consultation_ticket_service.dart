import 'package:shared_preferences/shared_preferences.dart';

/// 占い相談の「通常相談券」「優先券」と、至急の1日枠（日本時間の日付で集計・最大5回/日）
class ConsultationTicketService {
  ConsultationTicketService._();

  static const _kNormal = 'consult_normal_tickets_v1';
  static const _kPriority = 'consult_priority_tickets_v1';
  static const _kInitPrefix = 'consult_tickets_initialized_v1';
  static const _kUrgentDayJst = 'consult_urgent_slots_day_jst_v1';
  static const _kUrgentCount = 'consult_urgent_slots_count_v1';

  static String _accountKey = 'guest';

  static String _normalKey() => '${_kNormal}_$_accountKey';
  static String _priorityKey() => '${_kPriority}_$_accountKey';
  static String _initKey() => '${_kInitPrefix}_$_accountKey';

  static Future<void> bindAccountKey(String accountKey) async {
    _accountKey = accountKey.isNotEmpty ? accountKey : 'guest';
  }

  static Future<void> setBalances({required int normal, required int priority}) async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_normalKey(), normal.clamp(0, 1 << 20));
    await prefs.setInt(_priorityKey(), priority.clamp(0, 1 << 20));
  }

  /// 1回の通常相談で消費する券枚数
  static const int normalCostPerSend = 1;

  /// 1回の至急相談で消費する優先券枚数
  static const int priorityCostPerSend = 1;

  /// 至急は日本時間で1日あたり利用できる回数
  static const int maxUrgentSlotsPerDay = 5;

  /// 日本標準時の「壁時計」用（サマータイムなしの前提で UTC+9）
  static DateTime get nowJstWallClock {
    return DateTime.now().toUtc().add(const Duration(hours: 9));
  }

  static String _dateKeyJst(DateTime jst) {
    final y = jst.year;
    final m = jst.month.toString().padLeft(2, '0');
    final d = jst.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<void> _ensureInitialized() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_initKey()) == true) return;

    const normal = 0;
    const priority = 0;
    await prefs.setInt(_normalKey(), normal);
    await prefs.setInt(_priorityKey(), priority);
    await prefs.setBool(_initKey(), true);
  }

  static Future<int> normalTickets() async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_normalKey()) ?? 0;
  }

  static Future<int> priorityTickets() async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_priorityKey()) ?? 0;
  }

  /// 今日（JST）すでに使った至急枠の回数
  static Future<int> urgentSlotsUsedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKeyJst(nowJstWallClock);
    if (prefs.getString(_kUrgentDayJst) != today) return 0;
    return prefs.getInt(_kUrgentCount) ?? 0;
  }

  static Future<int> urgentSlotsRemainingToday() async {
    final u = await urgentSlotsUsedToday();
    return (maxUrgentSlotsPerDay - u).clamp(0, maxUrgentSlotsPerDay);
  }

  static Future<void> addNormalTickets(int delta) async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final v = ((prefs.getInt(_normalKey()) ?? 0) + delta).clamp(0, 1 << 20);
    await prefs.setInt(_normalKey(), v);
  }

  static Future<void> addPriorityTickets(int delta) async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final v = ((prefs.getInt(_priorityKey()) ?? 0) + delta).clamp(0, 1 << 20);
    await prefs.setInt(_priorityKey(), v);
  }

  /// 至急送信の直前チェック。null なら OK、文字列ならユーザー向けエラー
  static Future<String?> validateUrgentSend() async {
    final left = await urgentSlotsRemainingToday();
    if (left <= 0) {
      return '本日の至急相談枠（5回）を使い切りました。また明日お試しください。';
    }
    final p = await priorityTickets();
    if (p < priorityCostPerSend) {
      return '優先券が不足しています。';
    }
    return null;
  }

  static Future<String?> validateNormalSend() async {
    final n = await normalTickets();
    if (n < normalCostPerSend) {
      return '通常質問券が不足しています。';
    }
    return null;
  }

  /// 至急券（優先券）のみを検証（IAP 至急券用。1日枠は別途）。
  static Future<String?> validateUrgentTicketSend() async {
    final p = await priorityTickets();
    if (p < priorityCostPerSend) {
      return '至急券が不足しています。';
    }
    return null;
  }

  static Future<void> consumeUrgentTicket() async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final v = ((prefs.getInt(_priorityKey()) ?? 0) - priorityCostPerSend).clamp(0, 1 << 20);
    await prefs.setInt(_priorityKey(), v);
  }

  static Future<void> consumeNormalTicket() async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final v = ((prefs.getInt(_normalKey()) ?? 0) - normalCostPerSend).clamp(0, 1 << 20);
    await prefs.setInt(_normalKey(), v);
  }

  static Future<void> consumeUrgentSend() async {
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final pt = ((prefs.getInt(_priorityKey()) ?? 0) - priorityCostPerSend).clamp(0, 1 << 20);
    await prefs.setInt(_priorityKey(), pt);

    final today = _dateKeyJst(nowJstWallClock);
    final storedDay = prefs.getString(_kUrgentDayJst);
    var count = 0;
    if (storedDay == today) {
      count = prefs.getInt(_kUrgentCount) ?? 0;
    }
    await prefs.setString(_kUrgentDayJst, today);
    await prefs.setInt(_kUrgentCount, count + 1);
  }
}
