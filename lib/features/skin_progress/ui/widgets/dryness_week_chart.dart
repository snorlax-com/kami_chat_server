import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../model/skin_daily_record.dart';

class DrynessWeekChart extends StatelessWidget {
  final List<SkinDailyRecord> records;
  final int days;

  const DrynessWeekChart({super.key, required this.records, required this.days});

  @override
  Widget build(BuildContext context) {
    final last = records.length > days ? records.sublist(records.length - days) : records;
    if (last.isEmpty) return const SizedBox(height: 140, child: Center(child: Text('No data')));

    final spots = <FlSpot>[];
    for (int i = 0; i < last.length; i++) {
      spots.add(FlSpot(i.toDouble(), last[i].dryness.clamp(0, 100).toDouble()));
    }

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              color: const Color(0xFFEF4444),
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}
