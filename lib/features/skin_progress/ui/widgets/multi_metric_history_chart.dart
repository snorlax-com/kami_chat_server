import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../model/skin_daily_record.dart';

class MultiMetricHistoryChart extends StatelessWidget {
  final List<SkinDailyRecord> records;
  final int days;

  const MultiMetricHistoryChart({super.key, required this.records, required this.days});

  @override
  Widget build(BuildContext context) {
    final last = records.length > days ? records.sublist(records.length - days) : records;
    if (last.isEmpty) return const SizedBox(height: 160, child: Center(child: Text('No data')));

    // "提示UIの縦バー群"に寄せる：各日を「5本の細いバー」を横に並べる
    // BarChartGroupDataで x=dayIndex、barRodsを5本
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < last.length; i++) {
      final r = last[i];
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 2,
          barRods: [
            _rod(r.glow, index: 0),
            _rod(r.tone, index: 1),
            _rod(r.dullness, index: 2),
            _rod(r.texture, index: 3),
            _rod(r.dryness, index: 4),
          ],
        ),
      );
    }

    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          maxY: 100,
          minY: 0,
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: groups,
        ),
      ),
    );
  }

  BarChartRodData _rod(int v, {int index = 0}) {
    final colors = [
      const Color(0xFF4E6CF0), // Glow - 青
      const Color(0xFFF59E0B), // Tone - オレンジ
      const Color(0xFF8B5CF6), // Dullness - 紫
      const Color(0xFF06B6D4), // Texture - シアン
      const Color(0xFFEF4444), // Dryness - 赤
    ];
    return BarChartRodData(
      toY: v.clamp(0, 100).toDouble(),
      width: 4,
      borderRadius: BorderRadius.circular(2),
      color: colors[index % colors.length],
    );
  }
}
