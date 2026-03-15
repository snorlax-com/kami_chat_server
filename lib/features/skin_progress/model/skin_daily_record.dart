import 'package:intl/intl.dart';

class SkinDailyRecord {
  final DateTime date; // day unit
  final int glow; // ツヤ 0-100
  final int tone; // 血色 0-100
  final int dullness; // くすみ(低いほど良い、UIでは反転して表示してもOK) 0-100
  final int texture; // キメ 0-100
  final int dryness; // 乾燥傾向(低いほど良い) 0-100

  SkinDailyRecord({
    required this.date,
    required this.glow,
    required this.tone,
    required this.dullness,
    required this.texture,
    required this.dryness,
  });

  String get dayKey => DateFormat('yyyy-MM-dd').format(date);

  Map<String, dynamic> toMap() => {
        'date': date.toIso8601String(),
        'glow': glow,
        'tone': tone,
        'dullness': dullness,
        'texture': texture,
        'dryness': dryness,
      };

  static SkinDailyRecord fromMap(Map m) {
    return SkinDailyRecord(
      date: DateTime.parse(m['date'] as String),
      glow: (m['glow'] as num).toInt(),
      tone: (m['tone'] as num).toInt(),
      dullness: (m['dullness'] as num).toInt(),
      texture: (m['texture'] as num).toInt(),
      dryness: (m['dryness'] as num).toInt(),
    );
  }

  SkinDailyRecord copyWith({
    DateTime? date,
    int? glow,
    int? tone,
    int? dullness,
    int? texture,
    int? dryness,
  }) {
    return SkinDailyRecord(
      date: date ?? this.date,
      glow: glow ?? this.glow,
      tone: tone ?? this.tone,
      dullness: dullness ?? this.dullness,
      texture: texture ?? this.texture,
      dryness: dryness ?? this.dryness,
    );
  }
}
