import '../../../skin_analysis.dart';
import '../model/skin_daily_record.dart';

/// SkinAnalysisResultからSkinDailyRecordへの変換ユーティリティ
class SkinResultConverter {
  /// SkinAnalysisResultをSkinDailyRecordに変換
  ///
  /// マッピング:
  /// - glow (ツヤ): shineScore * 100 または brightness * 100
  /// - tone (血色): evenness または toneScore * 100
  /// - dullness (くすみ): dullnessIndex * 100（低いほど良いので反転）
  /// - texture (キメ): texture（既に0-100）
  /// - dryness (乾燥): dryness（既に0-100）
  static SkinDailyRecord convertToDailyRecord(
    SkinAnalysisResult skinResult,
    DateTime date,
  ) {
    // glow (ツヤ): shineScore優先、なければbrightness
    final glow = (skinResult.shineScore != null
            ? (skinResult.shineScore! * 100).clamp(0.0, 100.0)
            : (skinResult.brightness * 100).clamp(0.0, 100.0))
        .toInt();

    // tone (血色): evenness優先、なければtoneScore、それもなければrednessの逆
    final tone = (skinResult.evenness != null
            ? skinResult.evenness!.clamp(0.0, 100.0)
            : (skinResult.toneScore != null
                ? (skinResult.toneScore! * 100).clamp(0.0, 100.0)
                : (skinResult.redness != null ? (100.0 - skinResult.redness!).clamp(0.0, 100.0) : 50.0)))
        .toInt();

    // dullness (くすみ・透明感): dullnessIndex * 100（低いほど良いので反転）
    final dullness =
        (skinResult.dullnessIndex != null ? ((1.0 - skinResult.dullnessIndex!) * 100).clamp(0.0, 100.0) : 50.0).toInt();

    // texture (キメ): texture（既に0-100）
    final texture = (skinResult.texture != null
            ? skinResult.texture!.clamp(0.0, 100.0)
            : (skinResult.textureFineness != null ? (skinResult.textureFineness! * 100).clamp(0.0, 100.0) : 50.0))
        .toInt();

    // dryness (乾燥傾向): dryness（既に0-100、低いほど良いので反転）
    final dryness = (skinResult.dryness != null ? (100.0 - skinResult.dryness!).clamp(0.0, 100.0) : 50.0).toInt();

    // デバッグログ
    print('[SkinResultConverter] 診断結果変換:');
    print('  shineScore: ${skinResult.shineScore}, brightness: ${skinResult.brightness} → glow: $glow');
    print(
        '  evenness: ${skinResult.evenness}, toneScore: ${skinResult.toneScore}, redness: ${skinResult.redness} → tone: $tone');
    print('  dullnessIndex: ${skinResult.dullnessIndex} → dullness: $dullness');
    print('  texture: ${skinResult.texture}, textureFineness: ${skinResult.textureFineness} → texture: $texture');
    print('  dryness: ${skinResult.dryness} → dryness: $dryness');

    return SkinDailyRecord(
      date: date,
      glow: glow,
      tone: tone,
      dullness: dullness,
      texture: texture,
      dryness: dryness,
    );
  }
}
