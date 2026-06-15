import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// 肌記録用 Hive ボックス。起動時ではなく初回アクセス時に開く。
class SkinDailyRecordsBox {
  SkinDailyRecordsBox._();

  static Future<Box<Map>?>? _openFuture;

  static Future<Box<Map>?> ensureOpen() {
    return _openFuture ??= _open();
  }

  static Future<Box<Map>?> _open() async {
    try {
      if (Hive.isBoxOpen('skin_daily_records')) {
        return Hive.box<Map>('skin_daily_records');
      }
      await Hive.openBox<Map>('skin_daily_records').timeout(const Duration(seconds: 5));
      debugPrint('[SkinDailyRecordsBox] ready');
      return Hive.box<Map>('skin_daily_records');
    } catch (e, st) {
      debugPrint('[SkinDailyRecordsBox] open failed: $e\n$st');
      return null;
    }
  }
}
