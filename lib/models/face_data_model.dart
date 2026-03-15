import 'dart:convert';

class FaceData {
  final double smile;
  final double eyeOpen;
  final double gloss;
  final double straightness;
  final double claim;
  // 旧ロジック互換用フィールド
  final double foreheadBrightness;
  final double browAngle;
  final double noseHeight;
  final double mouthCorner;
  final double jawSharpness;
  final double jawContour;
  final double skinBrightness;
  final double skinGloss;
  final double noseShine;
  final double cheekColor;
  final double lipMoisture;
  final double foreheadReflection;

  FaceData({
    required this.smile,
    required this.eyeOpen,
    required this.gloss,
    required this.straightness,
    required this.claim,
    this.foreheadBrightness = 0.5,
    this.browAngle = 0.0,
    this.noseHeight = 0.5,
    this.mouthCorner = 0.0,
    this.jawSharpness = 0.5,
    this.jawContour = 0.5,
    this.skinBrightness = 0.5,
    this.skinGloss = 0.5,
    this.noseShine = 0.5,
    this.cheekColor = 0.5,
    this.lipMoisture = 0.5,
    this.foreheadReflection = 0.5,
  });

  String toJsonString() => jsonEncode(toJson());
  Map<String, dynamic> toJson() => {
        'smile': smile,
        'eyeOpen': eyeOpen,
        'gloss': gloss,
        'straightness': straightness,
        'claim': claim,
        'foreheadBrightness': foreheadBrightness,
        'browAngle': browAngle,
        'noseHeight': noseHeight,
        'mouthCorner': mouthCorner,
        'jawSharpness': jawSharpness,
        'jawContour': jawContour,
        'skinBrightness': skinBrightness,
        'skinGloss': skinGloss,
        'noseShine': noseShine,
        'cheekColor': cheekColor,
        'lipMoisture': lipMoisture,
        'foreheadReflection': foreheadReflection,
      };

  static FaceData fromJsonString(String s) => fromJson(jsonDecode(s));
  static FaceData fromJson(Map<String, dynamic> m) => FaceData(
        smile: (m['smile'] ?? 0.5).toDouble(),
        eyeOpen: (m['eyeOpen'] ?? 0.5).toDouble(),
        gloss: (m['gloss'] ?? 0.5).toDouble(),
        straightness: (m['straightness'] ?? 0.5).toDouble(),
        claim: (m['claim'] ?? 0.5).toDouble(),
        foreheadBrightness: (m['foreheadBrightness'] ?? 0.5).toDouble(),
        browAngle: (m['browAngle'] ?? 0.0).toDouble(),
        noseHeight: (m['noseHeight'] ?? 0.5).toDouble(),
        mouthCorner: (m['mouthCorner'] ?? 0.0).toDouble(),
        jawSharpness: (m['jawSharpness'] ?? 0.5).toDouble(),
        jawContour: (m['jawContour'] ?? 0.5).toDouble(),
        skinBrightness: (m['skinBrightness'] ?? 0.5).toDouble(),
        skinGloss: (m['skinGloss'] ?? 0.5).toDouble(),
        noseShine: (m['noseShine'] ?? 0.5).toDouble(),
        cheekColor: (m['cheekColor'] ?? 0.5).toDouble(),
        lipMoisture: (m['lipMoisture'] ?? 0.5).toDouble(),
        foreheadReflection: (m['foreheadReflection'] ?? 0.5).toDouble(),
      );
}

class FortuneResult {
  final DateTime date;
  final double mental;
  final double emotional;
  final double physical;
  final double social;
  final double stability;
  final double total;
  final String deity;

  FortuneResult({
    required this.date,
    required this.mental,
    required this.emotional,
    required this.physical,
    required this.social,
    required this.stability,
    required this.total,
    required this.deity,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'mental': mental,
        'emotional': emotional,
        'physical': physical,
        'social': social,
        'stability': stability,
        'total': total,
        'deity': deity,
      };

  static FortuneResult fromJson(Map<String, dynamic> m) => FortuneResult(
        date: DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime.now(),
        mental: (m['mental'] ?? 0.0).toDouble(),
        emotional: (m['emotional'] ?? 0.0).toDouble(),
        physical: (m['physical'] ?? 0.0).toDouble(),
        social: (m['social'] ?? 0.0).toDouble(),
        stability: (m['stability'] ?? 0.0).toDouble(),
        total: (m['total'] ?? 0.0).toDouble(),
        deity: (m['deity'] ?? '').toString(),
      );
}
