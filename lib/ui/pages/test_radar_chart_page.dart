import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/skin_analysis.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';
import 'package:kami_face_oracle/ui/pages/radar_chart_page.dart';

/// テスト用：画像分析に基づいた診断結果とチャートを表示
class TestRadarChartPage extends StatelessWidget {
  const TestRadarChartPage({super.key});

  /// 画像分析に基づいて診断値を計算
  SkinAnalysisResult _createTestSkinResult() {
    // 画像分析に基づいた値（0.0-1.0の範囲）
    // 1. ニキビ・吹き出物: 軽度から中程度 → 0.35
    final acne = 0.35;

    // 2. 赤み: 軽度の赤み → 0.25
    final redness = 0.25;

    // 3. シワ: 非常に少ない → 0.10
    final wrinkle = 0.10;

    // 4. クマ: 軽度のクマ → 0.30
    final darkCircle = 0.30;

    // 5. 肌トラブルなし: 中程度から良好 → 0.65
    final normal = 0.65;

    // 6. 毛穴の開き: 中程度（Tゾーンと頬） → 0.45
    final pore = 0.45;

    // SkinAnalysisResultを作成
    return SkinAnalysisResult(
      skinType: '混合肌',
      oiliness: 0.55, // 額と鼻に光沢あり
      smoothness: 0.70, // 全体的に滑らか
      uniformity: 0.65, // 軽度のトラブルあり
      poreSize: pore,
      brightness: 0.60, // やや明るい
      skinIssues: [
        '軽度のニキビ',
        '毛穴の開き',
        '軽度のクマ',
      ],
      regionAnalysis: {},
      recommendation: '保湿と毛穴ケアを心がけましょう',
      acneActivity: acne,
      wrinkleDensity: wrinkle,
      darkCircle: darkCircle,
      spotDensity: 0.20, // 軽度のシミ
      dullnessIndex: 0.30, // 軽度のくすみ
      aiClassification: {
        'acne': acne,
        'darkcircle': darkCircle,
        'wrinkle': wrinkle,
        'swelling': redness,
        'normal': normal,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // テスト用の神を選択（既存の神から選択）
    final testGod = deities.first; // Amateraを使用

    // テスト用の顔特徴
    final testFeatures = FaceFeatures(
      0.7, // smile
      0.8, // eyeOpen
      0.6, // gloss
      0.5, // straightness
      0.5, // claim
    );

    final skinResult = _createTestSkinResult();

    return RadarChartPage(
      skin: skinResult,
      god: testGod,
      features: testFeatures,
      beautyScore: 0.65,
      praise: '軽度のトラブルはありますが、全体的に健康的な肌です✨',
    );
  }
}
