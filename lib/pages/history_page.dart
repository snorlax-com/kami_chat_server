import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:kami_face_oracle/services/storage_service.dart';
import 'package:kami_face_oracle/services/fortune_logic.dart';
import 'package:kami_face_oracle/models/face_data_model.dart';
import 'package:kami_face_oracle/core/deity.dart';

/// 履歴・グラフ表示ページ
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<FortuneResult> _history = [];
  bool _isLoading = true;
  String _viewMode = 'week'; // 'week' or 'month'

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final history = await StorageService.getHistory();
      setState(() {
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      print('[HistoryPage] Error loading history: $e');
      setState(() => _isLoading = false);
    }
  }

  List<FortuneResult> get _displayData {
    if (_viewMode == 'week') {
      return _history.length > 7 ? _history.sublist(0, 7) : _history;
    } else {
      return _history.length > 30 ? _history.sublist(0, 30) : _history;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('運勢履歴'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(
                  child: Text('まだ履歴がありません'),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 期間切り替え
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'week',
                            label: Text('週次'),
                          ),
                          ButtonSegment(
                            value: 'month',
                            label: Text('月次'),
                          ),
                        ],
                        selected: {_viewMode},
                        onSelectionChanged: (Set<String> newSelection) {
                          setState(() {
                            _viewMode = newSelection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                      // グラフ
                      Container(
                        height: 300,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.1),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: _buildChart(),
                      ),
                      const SizedBox(height: 24),
                      // 降臨履歴
                      const Text(
                        '降臨履歴',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._displayData.reversed.map((result) {
                        final deity = FortuneLogic.getDeityById(result.deity);
                        return _buildHistoryCard(result, deity);
                      }).toList(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildChart() {
    if (_displayData.isEmpty) {
      return const Center(child: Text('データがありません'));
    }

    final spots = _displayData.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(),
        entry.value.total,
      );
    }).toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < _displayData.length) {
                  final date = _displayData[index].date;
                  return Text(
                    DateFormat('M/d').format(date),
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const Text('');
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.deepPurple,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.deepPurple.withValues(alpha: 0.1),
            ),
          ),
        ],
        minY: 0,
        maxY: 1,
      ),
    );
  }

  Widget _buildHistoryCard(FortuneResult result, Deity deity) {
    final dateFormat = DateFormat('yyyy年M月d日');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(
            int.parse(deity.colorHex.replaceFirst('#', '0xFF')),
          ),
          child: const Icon(Icons.star, color: Colors.white),
        ),
        title: Text(deity.nameJa),
        subtitle: Text(
          '${dateFormat.format(result.date)} - 総合運勢: ${(result.total * 100).toStringAsFixed(0)}%',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          _showDetailDialog(result, deity);
        },
      ),
    );
  }

  void _showDetailDialog(FortuneResult result, Deity deity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${deity.nameJa} - ${deity.role}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('日付: ${DateFormat('yyyy年M月d日').format(result.date)}'),
            const SizedBox(height: 12),
            _buildDetailScoreRow('精神運', result.mental),
            _buildDetailScoreRow('感情運', result.emotional),
            _buildDetailScoreRow('健康運', result.physical),
            _buildDetailScoreRow('対人運', result.social),
            _buildDetailScoreRow('安定運', result.stability),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailScoreRow(String label, double score) {
    final stars = FortuneLogic.scoreToStars(score);
    final starString = '★' * stars + '☆' * (5 - stars);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '$starString ${(score * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: Colors.amber.shade700),
          ),
        ],
      ),
    );
  }
}
