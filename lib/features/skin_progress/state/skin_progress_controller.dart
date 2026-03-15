import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../data/skin_record_repository.dart';
import '../data/skin_record_repository_hive.dart';
import '../model/skin_daily_record.dart';

final skinRecordRepositoryProvider = Provider<SkinRecordRepository>((ref) {
  final box = Hive.box<Map>('skin_daily_records');
  return SkinRecordRepositoryHive(box);
});

final skinProgressProvider = FutureProvider<List<SkinDailyRecord>>((ref) async {
  final repo = ref.read(skinRecordRepositoryProvider);
  return await repo.getAll();
});

final skinProgressControllerProvider = Provider<SkinProgressController>((ref) {
  final repo = ref.read(skinRecordRepositoryProvider);
  return SkinProgressController(repo, ref);
});

class SkinProgressController {
  final SkinRecordRepository repo;
  final Ref ref;

  SkinProgressController(this.repo, this.ref);

  Future<void> addDummyToday() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rnd = Random();

    int clamp(int v) => v.clamp(0, 100);

    // 既存の直近値を少し揺らす方が「日次記録」っぽい
    final current = await repo.getAll();
    final latest = current.isNotEmpty ? current.last : null;
    SkinDailyRecord make() {
      if (latest == null) {
        return SkinDailyRecord(
          date: today,
          glow: rnd.nextInt(41) + 50,
          tone: rnd.nextInt(41) + 50,
          dullness: rnd.nextInt(41) + 30,
          texture: rnd.nextInt(41) + 45,
          dryness: rnd.nextInt(41) + 30,
        );
      }
      int jitter(int base) => clamp(base + (rnd.nextInt(11) - 5));
      return SkinDailyRecord(
        date: today,
        glow: jitter(latest.glow),
        tone: jitter(latest.tone),
        dullness: jitter(latest.dullness),
        texture: jitter(latest.texture),
        dryness: jitter(latest.dryness),
      );
    }

    await repo.upsert(make());
    ref.invalidate(skinProgressProvider);
  }
}
