import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../skin_analysis.dart';
import '../model/skin_daily_record.dart';
import '../state/skin_progress_controller.dart';
import 'widgets/metric_ring_card.dart';
import 'widgets/multi_metric_history_chart.dart';
import 'widgets/dryness_week_chart.dart';

class SkinDailyProgressPage extends ConsumerWidget {
  const SkinDailyProgressPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRecords = ref.watch(skinProgressProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Daily Progress', style: TextStyle(color: Colors.black)),
        actions: [
          TextButton(
            onPressed: () => ref.read(skinProgressControllerProvider).addDummyToday(),
            child: const Text('Add Today', style: TextStyle(color: Color(0xFF4E6CF0))),
          ),
        ],
      ),
      body: asyncRecords.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (records) {
          final today = records.isNotEmpty ? records.last : null;
          final yesterday = records.length >= 2 ? records[records.length - 2] : null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (today != null) ...[
                _TodaySkinConditionCard(record: today),
                const SizedBox(height: 14),
              ],
              // 上段：2カード（提示UIの "Steps / Weight" 風）
              Row(
                children: [
                  Expanded(
                    child: MetricRingCard(
                      title: 'Glow',
                      value: today?.glow ?? 0,
                      goal: 80,
                      delta: (today != null && yesterday != null) ? today.glow - yesterday.glow : null,
                      subtitle: 'Shine / vitality',
                      icon: Icons.auto_awesome,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricRingCard(
                      title: 'Tone',
                      value: today?.tone ?? 0,
                      goal: 75,
                      delta: (today != null && yesterday != null) ? today.tone - yesterday.tone : null,
                      subtitle: 'Complexion',
                      icon: Icons.favorite,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 中段：Health（直近14日×5指標）
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(title: 'Health', trailing: 'Last 14 days'),
                      const SizedBox(height: 10),
                      MultiMetricHistoryChart(records: records, days: 14),
                      const SizedBox(height: 8),
                      const _LegendRow(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // 下段：Sleep（乾燥傾向 直近7日）
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(title: 'Dryness', trailing: 'Last 7 days'),
                      const SizedBox(height: 10),
                      DrynessWeekChart(records: records, days: 7),
                      const SizedBox(height: 6),
                      Text(
                        'Tip: Lower is better. Track trends rather than one-day swings.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // ボタン（提示UIの下部ナビは後で）
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => ref.read(skinProgressControllerProvider).addDummyToday(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add / Scan Today'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// その日の肌の調子（S/A/B/C）と艶・潤い・血色の内訳
class _TodaySkinConditionCard extends StatelessWidget {
  final SkinDailyRecord record;

  const _TodaySkinConditionCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final letter = record.conditionGrade;
    final title = skinConditionGradeTitleJa(letter);
    Color accent;
    switch (letter) {
      case 'S':
        accent = const Color(0xFF7C3AED);
        break;
      case 'A':
        accent = const Color(0xFF4E6CF0);
        break;
      case 'B':
        accent = const Color(0xFFF59E0B);
        break;
      default:
        accent = const Color(0xFF94A3B8);
    }
    final sub = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: accent.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今日の肌の調子',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  letter,
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text('艶・潤い・血色のバランスから算出', style: sub),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricChip('艶', record.glossPct, const Color(0xFF4E6CF0)),
                _metricChip('潤い', record.moisturePct, const Color(0xFF06B6D4)),
                _metricChip('血色', record.bloodPct, const Color(0xFFF472B6)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(String label, int pct, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label ${pct.clamp(0, 100)}%',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: color.withValues(alpha: 1),
          fontSize: 13,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String trailing;
  const _SectionHeader({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const Spacer(),
        Text(trailing, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow();

  @override
  Widget build(BuildContext context) {
    TextStyle s = Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.black54);
    Widget dot(Color color) => Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        );
    final colors = [
      const Color(0xFF4E6CF0), // Glow
      const Color(0xFFF59E0B), // Tone
      const Color(0xFF8B5CF6), // Dullness
      const Color(0xFF06B6D4), // Texture
      const Color(0xFFEF4444), // Dryness
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [dot(colors[0]), Text('Glow', style: s)]),
        Row(mainAxisSize: MainAxisSize.min, children: [dot(colors[1]), Text('Tone', style: s)]),
        Row(mainAxisSize: MainAxisSize.min, children: [dot(colors[2]), Text('Dullness', style: s)]),
        Row(mainAxisSize: MainAxisSize.min, children: [dot(colors[3]), Text('Texture', style: s)]),
        Row(mainAxisSize: MainAxisSize.min, children: [dot(colors[4]), Text('Dryness', style: s)]),
      ],
    );
  }
}
