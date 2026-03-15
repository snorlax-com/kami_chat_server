import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/skin_analysis.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';
import 'package:kami_face_oracle/ui/pages/result_page.dart';
import 'package:kami_face_oracle/services/skin_analysis_ai_service.dart';

/// 6角形レーダーチャートで肌トラブルを表示するページ
class RadarChartPage extends StatelessWidget {
  final SkinAnalysisResult skin;
  final Deity god;
  final FaceFeatures features;
  final double? beautyScore;
  final String? praise;
  final SkinAIDiagnosisResult? aiDiagnosisResult;

  const RadarChartPage({
    super.key,
    required this.skin,
    required this.god,
    required this.features,
    this.beautyScore,
    this.praise,
    this.aiDiagnosisResult,
  });

  /// 6項目の値を計算（0.0-1.0の範囲）
  /// proUniデータセットの分類に基づいて計算
  Map<String, double> _calculateRadarValues() {
    // 1. ニキビ・吹き出物 (acneActivity)
    // AI分類のacne値があれば優先、なければacneActivityを使用
    double acne = (skin.acneActivity ?? 0.0).clamp(0.0, 1.0);
    if (skin.aiClassification != null && skin.aiClassification!['acne'] != null) {
      acne = (acne * 0.5 + skin.aiClassification!['acne']! * 0.5).clamp(0.0, 1.0);
    }

    // 2. 赤み (redness) - acneActivity、spotDensity、AI分類から計算
    double redness = ((skin.acneActivity ?? 0.0) * 0.5 + (skin.spotDensity ?? 0.0) * 0.5).clamp(0.0, 1.0);
    // AI分類のswelling（むくみ・赤み）も考慮
    if (skin.aiClassification != null && skin.aiClassification!['swelling'] != null) {
      redness = (redness * 0.7 + skin.aiClassification!['swelling']! * 0.3).clamp(0.0, 1.0);
    }

    // 3. シワ (wrinkleDensity)
    // AI分類のwrinkle値があれば優先、なければwrinkleDensityを使用
    double wrinkle = (skin.wrinkleDensity ?? 0.0).clamp(0.0, 1.0);
    if (skin.aiClassification != null && skin.aiClassification!['wrinkle'] != null) {
      wrinkle = (wrinkle * 0.5 + skin.aiClassification!['wrinkle']! * 0.5).clamp(0.0, 1.0);
    }

    // 4. クマ (darkCircle)
    // AI分類のdarkcircle値があれば優先、なければdarkCircleを使用
    double darkCircle = (skin.darkCircle ?? 0.0).clamp(0.0, 1.0);
    if (skin.aiClassification != null && skin.aiClassification!['darkcircle'] != null) {
      darkCircle = (darkCircle * 0.5 + skin.aiClassification!['darkcircle']! * 0.5).clamp(0.0, 1.0);
    }

    // 5. 肌トラブルなし (normal) - AI分類のnormal値、またはトラブルの逆
    double normal = 0.5; // デフォルト値
    if (skin.aiClassification != null && skin.aiClassification!['normal'] != null) {
      normal = skin.aiClassification!['normal']!.clamp(0.0, 1.0);
    } else {
      // トラブルの逆を計算（低いほどトラブルなし）
      // 各トラブルの重み付け平均の逆
      final troubleScore =
          (acne * 0.25 + wrinkle * 0.25 + darkCircle * 0.2 + redness * 0.15 + (skin.poreSize * 0.15)).clamp(0.0, 1.0);
      normal = (1.0 - troubleScore).clamp(0.0, 1.0);
    }

    // 6. 毛穴の開き (poreSize) - 値が高いほど毛穴が開いている
    final pore = skin.poreSize.clamp(0.0, 1.0);

    return {
      'acne': acne,
      'redness': redness,
      'wrinkle': wrinkle,
      'darkCircle': darkCircle,
      'normal': normal,
      'pore': pore,
    };
  }

  @override
  Widget build(BuildContext context) {
    final values = _calculateRadarValues();
    final color = Color(int.parse(god.colorHex.replaceFirst('#', '0xff')));

    // デバッグ: 値を確認
    print('[RadarChartPage] 計算された値:');
    print('[RadarChartPage]   ニキビ: ${values['acne']}');
    print('[RadarChartPage]   赤み: ${values['redness']}');
    print('[RadarChartPage]   シワ: ${values['wrinkle']}');
    print('[RadarChartPage]   クマ: ${values['darkCircle']}');
    print('[RadarChartPage]   正常: ${values['normal']}');
    print('[RadarChartPage]   毛穴: ${values['pore']}');

    return Scaffold(
      appBar: AppBar(
        title: const Text('肌トラブル診断'),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // タイトル
              const Text(
                '肌状態レーダーチャート',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '6つの項目で肌の状態を可視化',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // カスタムレーダーチャート
              Container(
                height: 350,
                padding: const EdgeInsets.all(16),
                child: CustomPaint(
                  painter: RadarChartPainter(
                    values: [
                      values['acne']!,
                      values['redness']!,
                      values['wrinkle']!,
                      values['darkCircle']!,
                      values['normal']!,
                      values['pore']!,
                    ],
                    labels: [
                      'ニキビ',
                      '赤み',
                      'シワ',
                      'クマ',
                      '正常',
                      '毛穴',
                    ],
                    color: color,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 各項目の詳細表示
              _buildValueCard('ニキビ・吹き出物', values['acne']!, Icons.warning, Colors.red),
              _buildValueCard('赤み', values['redness']!, Icons.favorite, Colors.pink),
              _buildValueCard('シワ', values['wrinkle']!, Icons.linear_scale, Colors.brown),
              _buildValueCard('クマ', values['darkCircle']!, Icons.remove_circle, Colors.purple),
              _buildValueCard('肌トラブルなし', values['normal']!, Icons.check_circle, Colors.green),
              _buildValueCard('毛穴の開き', values['pore']!, Icons.circle, Colors.blue),

              const SizedBox(height: 24),

              // 次へボタン
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResultPage(
                        god: god,
                        features: features,
                        skin: skin,
                        beautyScore: beautyScore,
                        praise: praise,
                        aiDiagnosisResult: aiDiagnosisResult,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  '次へ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValueCard(String title, double value, IconData icon, Color color) {
    final percentage = (value * 100).toStringAsFixed(1);
    final status = value < 0.3
        ? '良好'
        : value < 0.6
            ? '注意'
            : '要改善';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: value,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 6角形レーダーチャートを描画するCustomPainter
class RadarChartPainter extends CustomPainter {
  final List<double> values; // 6つの値（0.0-1.0）
  final List<String> labels; // 6つのラベル
  final Color color;
  static const int sides = 6; // 6角形
  static const int gridLevels = 5; // グリッドのレベル数

  RadarChartPainter({
    required this.values,
    required this.labels,
    required this.color,
  }) : assert(values.length == sides && labels.length == sides);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 60; // ラベル用の余白

    // グリッドを描画
    _drawGrid(canvas, center, radius);

    // データポリゴンを描画
    _drawDataPolygon(canvas, center, radius);

    // 軸線を描画
    _drawAxes(canvas, center, radius);

    // ラベルを描画
    _drawLabels(canvas, center, radius);
  }

  /// グリッド（同心円）を描画
  void _drawGrid(Canvas canvas, Offset center, double radius) {
    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int level = 1; level <= gridLevels; level++) {
      final levelRadius = radius * (level / gridLevels);
      final path = Path();

      // 6角形の各頂点を計算
      for (int i = 0; i < sides; i++) {
        final angle = (i * 2 * math.pi / sides) - (math.pi / 2); // 上から開始
        final x = center.dx + levelRadius * math.cos(angle);
        final y = center.dy + levelRadius * math.sin(angle);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }
  }

  /// データポリゴンを描画
  void _drawDataPolygon(Canvas canvas, Offset center, double radius) {
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();

    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - (math.pi / 2); // 上から開始
      final value = values[i].clamp(0.0, 1.0);
      final valueRadius = radius * value;

      final x = center.dx + valueRadius * math.cos(angle);
      final y = center.dy + valueRadius * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  /// 軸線を描画
  void _drawAxes(Canvas canvas, Offset center, double radius) {
    final axisPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - (math.pi / 2); // 上から開始
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);

      canvas.drawLine(center, Offset(x, y), axisPaint);
    }
  }

  /// ラベルを描画
  void _drawLabels(Canvas canvas, Offset center, double radius) {
    final textStyle = TextStyle(
      color: Colors.black87,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - (math.pi / 2); // 上から開始
      final labelRadius = radius + 30; // グリッドの外側に配置

      final x = center.dx + labelRadius * math.cos(angle);
      final y = center.dy + labelRadius * math.sin(angle);

      textPainter.text = TextSpan(
        text: labels[i],
        style: textStyle,
      );
      textPainter.layout();

      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is RadarChartPainter) {
      return oldDelegate.values != values || oldDelegate.color != color;
    }
    return true;
  }
}
