import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../skin_analysis.dart';
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
        final glow = rnd.nextInt(41) + 50;
        final tone = rnd.nextInt(41) + 50;
        final dullness = rnd.nextInt(41) + 30;
        final texture = rnd.nextInt(41) + 45;
        final dryness = rnd.nextInt(41) + 30;
        final avg = (glow + tone + dryness) / 300.0;
        final grade = skinConditionGradeFromAverage(avg);
        return SkinDailyRecord(
          date: today,
          glow: glow,
          tone: tone,
          dullness: dullness,
          texture: texture,
          dryness: dryness,
          conditionGrade: grade,
          glossPct: glow,
          moisturePct: dryness,
          bloodPct: tone,
        );
      }
      int jitter(int base) => clamp(base + (rnd.nextInt(11) - 5));
      final glow = jitter(latest.glow);
      final tone = jitter(latest.tone);
      final dullness = jitter(latest.dullness);
      final texture = jitter(latest.texture);
      final dryness = jitter(latest.dryness);
      final avg = (glow + tone + dryness) / 300.0;
      final grade = skinConditionGradeFromAverage(avg);
      return SkinDailyRecord(
        date: today,
        glow: glow,
        tone: tone,
        dullness: dullness,
        texture: texture,
        dryness: dryness,
        conditionGrade: grade,
        glossPct: glow,
        moisturePct: dryness,
        bloodPct: tone,
      );
    }

    await repo.upsert(make());
    ref.invalidate(skinProgressProvider);
  }
}
