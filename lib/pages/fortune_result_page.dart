import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/models/face_data_model.dart';

/// 運勢結果ページ
class FortuneResultPage extends StatelessWidget {
  final Deity deity;
  final FaceData faceData;
  final FortuneResult? fortuneResult;
  final bool isBaseline;
  final bool isConsecutive;

  const FortuneResultPage({
    super.key,
    required this.deity,
    required this.faceData,
    this.fortuneResult,
    this.isBaseline = false,
    this.isConsecutive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isBaseline ? '基礎神判定' : '今日の運勢'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 神の情報
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      deity.nameJa,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      deity.role,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 運勢結果（存在する場合）
            if (fortuneResult != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '運勢スコア',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      _buildScoreRow('精神', fortuneResult!.mental),
                      _buildScoreRow('感情', fortuneResult!.emotional),
                      _buildScoreRow('身体', fortuneResult!.physical),
                      _buildScoreRow('社交', fortuneResult!.social),
                      _buildScoreRow('安定', fortuneResult!.stability),
                      const Divider(),
                      _buildScoreRow('総合', fortuneResult!.total, isTotal: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 連続降臨メッセージ
            if (isConsecutive)
              Card(
                color: Colors.amber.withValues(alpha: 0.2),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('連続降臨中！'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreRow(String label, double score, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${(score * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 18 : 16,
            ),
          ),
        ],
      ),
    );
  }
}
