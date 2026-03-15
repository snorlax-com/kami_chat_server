import 'package:flutter/material.dart';
import '../../skin_analysis.dart';
import '../../features/skin_progress/ui/skin_daily_progress_page.dart';

/// 肌診断結果を表示する新しいUIページ
class SkinDiagnosisResultPage extends StatelessWidget {
  final SkinAnalysisResult skinResult;
  final DateTime diagnosisDate;

  const SkinDiagnosisResultPage({
    super.key,
    required this.skinResult,
    required this.diagnosisDate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '肌診断結果',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 診断日時
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, color: Color(0xFF4E6CF0)),
                    const SizedBox(width: 12),
                    Text(
                      '診断日: ${_formatDate(diagnosisDate)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 8項目のグリッド表示
            _build8MetricsGrid(skinResult),
            const SizedBox(height: 24),

            // 詳細スコア表示（8項目）
            _buildDetailed8Scores(skinResult),
            const SizedBox(height: 24),

            // 診断結果の説明
            _buildRecommendationCard(skinResult),
            const SizedBox(height: 16),

            // Daily Progressへのリンク
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SkinDailyProgressPage(),
                  ),
                );
              },
              icon: const Icon(Icons.trending_up),
              label: const Text('日次記録を確認'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4E6CF0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 8項目のグリッド表示
  Widget _build8MetricsGrid(SkinAnalysisResult skin) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: [
        _buildMetricCard(
          title: '皮脂量',
          value: ((skin.oiliness * 100).clamp(0.0, 100.0)).toInt(),
          icon: Icons.water_drop,
          color: const Color(0xFF4E6CF0),
          description: '皮脂の分泌量',
        ),
        _buildMetricCard(
          title: '乾燥',
          value: (skin.dryness ?? 50.0).clamp(0.0, 100.0).toInt(),
          icon: Icons.ac_unit,
          color: const Color(0xFFF59E0B),
          description: '肌の乾燥度',
        ),
        _buildMetricCard(
          title: 'キメ',
          value: (skin.texture ?? 50.0).clamp(0.0, 100.0).toInt(),
          icon: Icons.texture,
          color: const Color(0xFF8B5CF6),
          description: '肌のきめ細かさ',
        ),
        _buildMetricCard(
          title: '透明感',
          value: (skin.evenness ?? 50.0).clamp(0.0, 100.0).toInt(),
          icon: Icons.brightness_6,
          color: const Color(0xFF06B6D4),
          description: '透明感のある肌',
        ),
        _buildMetricCard(
          title: '毛穴',
          value: ((skin.poreSize ?? 0.0) * 100).clamp(0.0, 100.0).toInt(),
          icon: Icons.circle,
          color: const Color(0xFF10B981),
          description: '毛穴の目立ち',
        ),
        _buildMetricCard(
          title: '赤み',
          value: (skin.redness ?? 50.0).clamp(0.0, 100.0).toInt(),
          icon: Icons.favorite,
          color: const Color(0xFFEF4444),
          description: '肌の赤み',
        ),
        _buildMetricCard(
          title: 'ハリ',
          value: (skin.firmness ?? 50.0).clamp(0.0, 100.0).toInt(),
          icon: Icons.auto_awesome,
          color: const Color(0xFFFF6B6B),
          description: '肌のハリ・弾力',
        ),
        _buildMetricCard(
          title: 'ニキビ',
          value: (skin.acne ?? 50.0).clamp(0.0, 100.0).toInt(),
          icon: Icons.warning,
          color: const Color(0xFFF97316),
          description: 'ニキビ・炎症',
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required int value,
    required IconData icon,
    required Color color,
    required String description,
  }) {
    final percentage = value.clamp(0, 100).toDouble();
    final progress = percentage / 100.0;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: color.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 8項目の詳細スコア表示
  Widget _buildDetailed8Scores(SkinAnalysisResult skin) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '詳細スコア（8項目）',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            _buildScoreRow('皮脂量', ((skin.oiliness * 100).clamp(0.0, 100.0)).toInt(), const Color(0xFF4E6CF0)),
            const SizedBox(height: 12),
            _buildScoreRow('乾燥', (skin.dryness ?? 50.0).clamp(0.0, 100.0).toInt(), const Color(0xFFF59E0B)),
            const SizedBox(height: 12),
            _buildScoreRow('キメ', (skin.texture ?? 50.0).clamp(0.0, 100.0).toInt(), const Color(0xFF8B5CF6)),
            const SizedBox(height: 12),
            _buildScoreRow('透明感', (skin.evenness ?? 50.0).clamp(0.0, 100.0).toInt(), const Color(0xFF06B6D4)),
            const SizedBox(height: 12),
            _buildScoreRow('毛穴', ((skin.poreSize ?? 0.0) * 100).clamp(0.0, 100.0).toInt(), const Color(0xFF10B981)),
            const SizedBox(height: 12),
            _buildScoreRow('赤み', (skin.redness ?? 50.0).clamp(0.0, 100.0).toInt(), const Color(0xFFEF4444)),
            const SizedBox(height: 12),
            _buildScoreRow('ハリ', (skin.firmness ?? 50.0).clamp(0.0, 100.0).toInt(), const Color(0xFFFF6B6B)),
            const SizedBox(height: 12),
            _buildScoreRow('ニキビ', (skin.acne ?? 50.0).clamp(0.0, 100.0).toInt(), const Color(0xFFF97316)),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreRow(String label, int value, Color color) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value / 100.0,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationCard(SkinAnalysisResult skin) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb, color: Color(0xFF4E6CF0)),
                SizedBox(width: 8),
                Text(
                  '診断結果',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (skin.recommendation.isNotEmpty)
              Text(
                skin.recommendation,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  height: 1.6,
                ),
              )
            else
              const Text(
                '肌の状態を確認しました。日々のケアを続けて、美しい肌を保ちましょう。',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  height: 1.6,
                ),
              ),
            if (skin.skinIssues.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                '注意事項',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              ...skin.skinIssues.map((issue) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            issue,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
