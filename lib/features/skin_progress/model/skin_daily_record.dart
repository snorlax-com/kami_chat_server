import 'package:intl/intl.dart';

class SkinDailyRecord {
  final DateTime date; // day unit
  final int glow; // ツヤ 0-100
  final int tone; // 血色 0-100
  final int dullness; // くすみ(低いほど良い、UIでは反転して表示してもOK) 0-100
  final int texture; // キメ 0-100
  final int dryness; // 乾燥傾向(低いほど良い) 0-100
  /// その日の肌の調子 S / A / B / C（艶・潤い・血色から算出）
  final String conditionGrade;
  /// 艶・潤い・血色（各 0–100、診断時点の正規化スコア）
  final int glossPct;
  final int moisturePct;
  final int bloodPct;

  SkinDailyRecord({
    required this.date,
    required this.glow,
    required this.tone,
    required this.dullness,
    required this.texture,
    required this.dryness,
    required this.conditionGrade,
    required this.glossPct,
    required this.moisturePct,
    required this.bloodPct,
  });

  String get dayKey => DateFormat('yyyy-MM-dd').format(date);

  Map<String, dynamic> toMap() => {
        'date': date.toIso8601String(),
        'glow': glow,
        'tone': tone,
        'dullness': dullness,
        'texture': texture,
        'dryness': dryness,
        'conditionGrade': conditionGrade,
        'glossPct': glossPct,
        'moisturePct': moisturePct,
        'bloodPct': bloodPct,
      };

  static SkinDailyRecord fromMap(Map m) {
    final glow = (m['glow'] as num).toInt();
    final tone = (m['tone'] as num).toInt();
    final dullness = (m['dullness'] as num).toInt();
    final texture = (m['texture'] as num).toInt();
    final dryness = (m['dryness'] as num).toInt();
    final glossPct = (m['glossPct'] as num?)?.toInt() ?? glow;
    final moisturePct = (m['moisturePct'] as num?)?.toInt() ?? dryness;
    final bloodPct = (m['bloodPct'] as num?)?.toInt() ?? tone;
    final legacyAvg = ((glow + tone + dryness) / 300.0).clamp(0.0, 1.0);
    final rawG = m['conditionGrade'] as String?;
    final conditionGrade = (rawG != null && rawG.trim().isNotEmpty)
        ? _normalizeGrade(rawG.trim())
        : _gradeFromAvg(legacyAvg);
    return SkinDailyRecord(
      date: DateTime.parse(m['date'] as String),
      glow: glow,
      tone: tone,
      dullness: dullness,
      texture: texture,
      dryness: dryness,
      conditionGrade: conditionGrade,
      glossPct: glossPct,
      moisturePct: moisturePct,
      bloodPct: bloodPct,
    );
  }

  /// 旧データ用（skin_analysis の閾値と揃える）
  static String _gradeFromAvg(double avg01) {
    if (avg01 >= 0.78) return 'S';
    if (avg01 >= 0.62) return 'A';
    if (avg01 >= 0.48) return 'B';
    return 'C';
  }

  static String _normalizeGrade(String g) {
    final u = g.toUpperCase();
    if (u == 'S' || u == 'A' || u == 'B' || u == 'C') return u;
    return 'B';
  }

  SkinDailyRecord copyWith({
    DateTime? date,
    int? glow,
    int? tone,
    int? dullness,
    int? texture,
    int? dryness,
    String? conditionGrade,
    int? glossPct,
    int? moisturePct,
    int? bloodPct,
  }) {
    return SkinDailyRecord(
      date: date ?? this.date,
      glow: glow ?? this.glow,
      tone: tone ?? this.tone,
      dullness: dullness ?? this.dullness,
      texture: texture ?? this.texture,
      dryness: dryness ?? this.dryness,
      conditionGrade: conditionGrade ?? this.conditionGrade,
      glossPct: glossPct ?? this.glossPct,
      moisturePct: moisturePct ?? this.moisturePct,
      bloodPct: bloodPct ?? this.bloodPct,
    );
  }
}
