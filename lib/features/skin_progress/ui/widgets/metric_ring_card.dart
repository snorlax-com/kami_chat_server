import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class MetricRingCard extends StatelessWidget {
  final String title;
  final int value; // 0-100
  final int goal; // target
  final int? delta;
  final String subtitle;
  final IconData icon;

  const MetricRingCard({
    super.key,
    required this.title,
    required this.value,
    required this.goal,
    required this.delta,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0, 100).toDouble();
    final rest = (100 - v).clamp(0, 100).toDouble();
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                children: [
                  PieChart(
                    PieChartData(
                      startDegreeOffset: -90,
                      sectionsSpace: 0,
                      centerSpaceRadius: 22,
                      sections: [
                        PieChartSectionData(
                          value: v,
                          showTitle: false,
                          radius: 10,
                          color: const Color(0xFF4E6CF0),
                        ),
                        PieChartSectionData(
                          value: rest,
                          showTitle: false,
                          radius: 10,
                          color: Colors.grey.shade200,
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: Text(
                      '${value.clamp(0, 100)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18),
                      const SizedBox(width: 6),
                      Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      if (delta != null)
                        Text(
                          delta! >= 0 ? '+$delta' : '$delta',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
                  const SizedBox(height: 6),
                  Text('Goal $goal', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
