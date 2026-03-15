import '../model/skin_daily_record.dart';

abstract class SkinRecordRepository {
  Future<List<SkinDailyRecord>> getAll();
  Future<void> upsert(SkinDailyRecord record);
  Future<void> deleteByDayKey(String dayKey);
}
