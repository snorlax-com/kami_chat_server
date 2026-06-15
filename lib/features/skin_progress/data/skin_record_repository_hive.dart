import 'package:hive/hive.dart';
import '../model/skin_daily_record.dart';
import 'skin_daily_records_box.dart';
import 'skin_record_repository.dart';

class SkinRecordRepositoryHive implements SkinRecordRepository {
  Future<Box<Map>?> _box() => SkinDailyRecordsBox.ensureOpen();

  @override
  Future<List<SkinDailyRecord>> getAll() async {
    final box = await _box();
    if (box == null) return [];
    final items = <SkinDailyRecord>[];
    for (final key in box.keys) {
      final data = box.get(key);
      if (data != null) items.add(SkinDailyRecord.fromMap(Map<String, dynamic>.from(data)));
    }
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  @override
  Future<void> upsert(SkinDailyRecord record) async {
    final box = await _box();
    if (box == null) return;
    await box.put(record.dayKey, record.toMap());
  }

  @override
  Future<void> deleteByDayKey(String dayKey) async {
    final box = await _box();
    if (box == null) return;
    await box.delete(dayKey);
  }
}
