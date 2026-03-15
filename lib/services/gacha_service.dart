import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:kami_face_oracle/services/currency_service.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';

/// ガチャサービスの結果
class GachaResult {
  final String rewardType; // 'coins', 'gems', 'fragments', 'meditation_card', 'boost'
  final int amount;
  final String? deityId; // 降臨した神のID（オプション）

  GachaResult({
    required this.rewardType,
    required this.amount,
    this.deityId,
  });
}

/// ガチャシステム
class GachaService {
  // ガチャのコスト（コイン）
  static const int costPerPlay = 10;

  // 1日の上限（デフォルト10回）
  static const int dailyLimit = 10;

  /// ガチャを引く
  /// 戻り値: 報酬情報。失敗時はnull
  static Future<GachaResult?> play() async {
    // 日次制限チェック
    if (!await canPlayToday()) {
      return null; // 今日の上限に達している
    }

    // コイン残高チェック
    final wallet = await CurrencyService.load();
    if (wallet['coins']! < costPerPlay) {
      return null; // コイン不足
    }

    // コスト支払い
    await CurrencyService.useCoins(costPerPlay);

    // プレイ記録を保存
    await _recordPlay();

    // 報酬抽選
    final r = math.Random(DateTime.now().millisecondsSinceEpoch);
    final roll = r.nextDouble();

    String rewardType;
    int amount;

    // 報酬確率: コイン20%, 瞑想カード70%, ジェム（激レア）8%, ブースト2%
    // コイン20%、それ以外は瞑想カード（宝石とブーストを除く）
    if (roll < 0.20) {
      // コイン 20%
      rewardType = 'coins';
      amount = 5 + r.nextInt(11); // 5-15コイン
      await CurrencyService.addCoins(amount);
    } else if (roll < 0.90) {
      // 瞑想カード 70%（0.20 ～ 0.90）
      rewardType = 'meditation_card';
      amount = 1;
      // カードに神を紐付け（ランダム選択）
      final cardDeityId = _deityIds[r.nextInt(_deityIds.length)];
      await CloudService.addInventoryItem('meditation_card', {
        'source': 'gacha',
        'minutes': 5 + r.nextInt(11), // 5-15分
        'deityId': cardDeityId, // 神のIDを保存
      });
    } else if (roll < 0.98) {
      // ジェム（激レア）8% - 確率を維持
      rewardType = 'gems';
      amount = 5 + r.nextInt(11); // 5-15ジェム（激レアなので多めに）
      await CurrencyService.addGems(amount);
    } else {
      // ブースト（超激レア）2%
      rewardType = 'boost';
      amount = 1;
      // Firestoreにブースト記録を保存
      await CloudService.saveDailyRecord({
        'boost': {
          'type': 'gacha_boost',
          'duration': 24, // 24時間
          'createdAt': DateTime.now().toIso8601String(),
        },
      });
    }

    // 降臨した神を抽選（視覚効果用）
    final deityRoll = r.nextInt(18); // 18柱の神
    final deityId = _deityIds[deityRoll];

    return GachaResult(
      rewardType: rewardType,
      amount: amount,
      deityId: deityId,
    );
  }

  /// 1日の残り回数を取得
  static Future<bool> canPlayToday() async {
    final remaining = await getRemainingPlays();
    return remaining > 0;
  }

  /// 残り回数を取得
  static Future<int> getRemainingPlays() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      // 今日の記録を取得
      final records = await CloudService.getDailyRecords(date: today);
      int todayCount = 0;
      if (records.isNotEmpty && records.first['gacha'] != null) {
        todayCount = (records.first['gacha'] as num?)?.toInt() ?? 0;
      }
      return (dailyLimit - todayCount).clamp(0, dailyLimit);
    } catch (e) {
      // エラー時は制限なしとして扱う
      return dailyLimit;
    }
  }

  /// ガチャ実行記録を保存
  static Future<void> _recordPlay() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      // 今日の記録を取得
      final records = await CloudService.getDailyRecords(date: today);
      int todayCount = 0;
      if (records.isNotEmpty && records.first['gacha'] != null) {
        todayCount = (records.first['gacha'] as num?)?.toInt() ?? 0;
      }
      todayCount++;
      // 今日の記録を更新
      await CloudService.saveDailyRecord({
        'date': today,
        'gacha': todayCount,
      });
    } catch (e) {
      // エラーは無視（記録できなくてもガチャは動作）
    }
  }

  static const List<String> _deityIds = [
    'amatera',
    'yatael',
    'skura',
    'delphos',
    'amanoira',
    'noirune',
    'ragias',
    'verdatsu',
    'osiria',
    'fatemis',
    'kanonis',
    'sylna',
    'tenkora',
    'yorusi',
    'shisaru',
    'mimika',
    'tenmira',
    'shiran',
  ];
}
