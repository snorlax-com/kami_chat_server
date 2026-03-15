import 'package:hive/hive.dart';
import '../model/skin_daily_record.dart';
import 'skin_record_repository.dart';

class SkinRecordRepositoryHive implements SkinRecordRepository {
  final Box<Map> box;

  SkinRecordRepositoryHive(this.box);

  @override
  Future<List<SkinDailyRecord>> getAll() async {
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
    await box.put(record.dayKey, record.toMap());
  }

  @override
  Future<void> deleteByDayKey(String dayKey) async {
    await box.delete(dayKey);
  }
}
