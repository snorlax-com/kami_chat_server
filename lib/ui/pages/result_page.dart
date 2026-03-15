import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/skin_analysis.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/skin_analysis_ai_service.dart';
import 'package:kami_face_oracle/services/comparative_skin_analysis_service.dart';
import 'package:kami_face_oracle/ui/pages/deity_compatibility_page.dart';
import 'package:fl_chart/fl_chart.dart';

class ResultPage extends StatefulWidget {
  final Deity god;
  final FaceFeatures features;
  final SkinAnalysisResult? skin; // 将来拡張用（未使用でもOK）
  final double? beautyScore;
  final String? praise;
  final SkinAIDiagnosisResult? aiDiagnosisResult; // ✅ AI診断結果

  const ResultPage(
      {super.key,
      required this.god,
      required this.features,
      this.skin,
      this.beautyScore,
      this.praise,
      this.aiDiagnosisResult});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  bool _showDebug = false;
  @override
  void initState() {
    super.initState();
    _save();
  }

  Future<void> _save() async {
    await Storage.addHistory({
      'id': widget.god.id,
      'name': widget.god.nameJa,
      'ts': DateTime.now().toIso8601String(),
    });
    // 1日1回限定のポイント付与（初回占い時のみ）
    final dailyPoint = await Storage.addDailyPoint(1);
    if (dailyPoint > 0) {
      // 今日初めての占いでポイントが付与された
    }
    // Firestoreへ日次記録（匿名Auth前提。未設定時は内部で無視）
    try {
      final beauty = widget.beautyScore ?? (widget.skin?.brightness ?? 0.5);
      final qi = widget.features.gloss;
      final fuku = (widget.features.smile * 0.6 + widget.features.eyeOpen * 0.4);
      final comment = CloudService.generateComment(
        deityId: widget.god.id,
        beauty: beauty,
        qi: qi,
        fuku: fuku,
      );
      await CloudService.saveDailyRecord({
        'date': DateTime.now().toIso8601String().substring(0, 10),
        'deity': widget.god.id,
        'beauty': beauty,
        'qi': qi,
        'fuku': fuku,
        'comment': comment,
        'praise': widget.praise,
        'skin': {
          'brightness': widget.skin?.brightness,
          'dullnessIndex': widget.skin?.dullnessIndex,
          'spotDensity': widget.skin?.spotDensity,
          'acneActivity': widget.skin?.acneActivity,
          'wrinkleDensity': widget.skin?.wrinkleDensity,
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(widget.god.colorHex.replaceFirst('#', '0xff')));
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日の神が降臨'),
        actions: [
          IconButton(
            icon: Icon(_showDebug ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () => setState(() => _showDebug = !_showDebug),
            tooltip: 'デバッグ',
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                  child: Image.asset(
                widget.god.symbolAsset,
                height: 200,
                width: 200,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[400]!),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_not_supported, size: 48, color: Colors.grey[600]),
                        const SizedBox(height: 8),
                        Text(
                          '画像が見つかりません',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              )),
              const SizedBox(height: 8),
              Text('【${widget.god.nameJa}】 ${widget.god.role}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (widget.beautyScore != null)
                Row(
                  children: [
                    const Text('美運スコア: '),
                    Text(((widget.beautyScore! * 100).clamp(0, 100)).toStringAsFixed(0) + '%',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              const SizedBox(height: 8),
              Text(widget.god.shortMessage),
              if (widget.praise != null) ...[
                const SizedBox(height: 8),
                Text(widget.praise!),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withOpacity(.08), borderRadius: BorderRadius.circular(12)),
                child: Text(_reasonText(widget.features)),
              ),
              const SizedBox(height: 16),
              // 相性診断ボタン
              OutlinedButton.icon(
                icon: Icon(Icons.favorite, color: color),
                label: const Text('相性を見る'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withOpacity(0.6), width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeityCompatibilityPage(
                        currentDeity: widget.god,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildSkinCard(widget.skin),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ホームへ'),
          ),
        ),
      ),
    );
  }

  String _reasonText(FaceFeatures f) {
    String e = (f.smile * 0.6 + f.eyeOpen * 0.4) >= 0.55 ? '明るい表情' : '落ち着いた表情';
    String s = f.gloss >= 0.50 ? '潤いのある肌質' : 'ややマットな肌質';
    String sh = f.straightness >= 0.55 ? '直線的な輪郭傾向' : '丸みのある輪郭傾向';
    String c = f.claim >= 0.55 ? '目や眉・唇の主張が強め' : 'やわらかい印象';
    return '判定根拠：$e／$s／$sh／$c';
  }

  Widget _buildSkinCard(SkinAnalysisResult? s) {
    if (s == null) return const SizedBox.shrink();

    List<Widget> rows = [];

    // 0-100スコア用の行ウィジェット
    Widget row100(String label, double? value) {
      final v = (value ?? 0.0).clamp(0.0, 100.0);
      final normalized = v / 100.0; // 0-1に正規化
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 14))),
            Expanded(
              child: LinearProgressIndicator(
                value: normalized.clamp(0.0, 0.98),
                minHeight: 10,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  normalized > 0.7 ? Colors.orange : Colors.blue,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 50,
              child: Text(
                '${v.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    // 0-1スコア用の行ウィジェット
    Widget row01(String label, double? value, {bool inverse = false}) {
      final v = (value ?? 0.0).clamp(0.0, 1.0);
      final disp = inverse ? (1.0 - v) : v;
      final percentage = (disp * 100).clamp(0.0, 100.0);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 14))),
            Expanded(
              child: LinearProgressIndicator(
                value: disp.clamp(0.0, 0.98),
                minHeight: 10,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  disp > 0.7 ? Colors.orange : Colors.blue,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 50,
              child: Text(
                '${percentage.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    // 指定された指標のみを表示（0-100スコア）
    rows.add(row100('皮脂量', (s.oiliness * 100))); // 0-1を0-100に変換
    rows.add(row100('乾燥', s.dryness));
    rows.add(row100('キメ', s.texture));
    rows.add(row100('透明感', s.evenness));
    rows.add(row100('毛穴', (s.poreSize * 100))); // 0-1を0-100に変換
    rows.add(row100('赤み', s.redness));
    rows.add(row100('ハリ', s.firmness));
    rows.add(row100('ニキビ', s.acne));

    // 指定された指標のみを表示（0-1スコア）
    // くすみ: 高いほどくすみが少ない（逆表示）
    rows.add(row01('くすみ', s.dullnessIndex, inverse: true));
    rows.add(row01('シミ', s.spotDensity));
    rows.add(row01('しわ', s.wrinkleDensity));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '肌分析',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...rows,
        ],
      ),
    );
  }

  Future<Widget> _buildDeltaCardAsync() async {
    final cur = widget.skin;
    if (cur == null) return const SizedBox.shrink();

    // baseline / previous を取得
    SkinAnalysisResult? baseline;
    SkinAnalysisResult? previous;
    try {
      final bMap = await Storage.getBaselineSkin();
      if (bMap != null) {
        baseline = SkinAnalysisResult(
          skinType: 'baseline',
          oiliness: (bMap['oiliness'] ?? 0.5).toDouble(),
          smoothness: (bMap['smoothness'] ?? 0.5).toDouble(),
          uniformity: (bMap['uniformity'] ?? 0.5).toDouble(),
          poreSize: (bMap['poreSize'] ?? 0.3).toDouble(),
          brightness: (bMap['brightness'] ?? 0.7).toDouble(),
          skinIssues: const [],
          regionAnalysis: const {},
          recommendation: '',
          dullnessIndex: (bMap['dullnessIndex'] ?? 0.0).toDouble(),
          spotDensity: (bMap['spotDensity'] ?? 0.0).toDouble(),
          acneActivity: (bMap['acneActivity'] ?? 0.0).toDouble(),
          wrinkleDensity: (bMap['wrinkleDensity'] ?? 0.0).toDouble(),
        );
      }
      final pMap = await Storage.getLastSkin();
      if (pMap != null) {
        previous = SkinAnalysisResult(
          skinType: 'previous',
          oiliness: (pMap['oiliness'] ?? 0.5).toDouble(),
          smoothness: (pMap['smoothness'] ?? 0.5).toDouble(),
          uniformity: (pMap['uniformity'] ?? 0.5).toDouble(),
          poreSize: (pMap['poreSize'] ?? 0.3).toDouble(),
          brightness: (pMap['brightness'] ?? 0.7).toDouble(),
          skinIssues: const [],
          regionAnalysis: const {},
          recommendation: '',
          dullnessIndex: (pMap['dullnessIndex'] ?? 0.0).toDouble(),
          spotDensity: (pMap['spotDensity'] ?? 0.0).toDouble(),
          acneActivity: (pMap['acneActivity'] ?? 0.0).toDouble(),
          wrinkleDensity: (pMap['wrinkleDensity'] ?? 0.0).toDouble(),
        );
      }
    } catch (_) {}

    final delta = SkinAnalyzerDelta.computeDelta(
      baseline: baseline,
      previous: previous,
      current: cur,
    );

    Widget row(String label, double v) {
      final arrow = v >= 0 ? '↑' : '↓';
      final pct = (v.abs() * 100).clamp(0, 100).toStringAsFixed(0);
      final color = v >= 0 ? Colors.redAccent : Colors.blueAccent;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 90, child: Text(label)),
            Text('$arrow$pct%', style: TextStyle(color: color)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('比較（基礎/前日比）', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          row('くすみ', delta.dullnessDelta),
          row('シミ', delta.spotDelta),
          row('ニキビ', delta.acneDelta),
          row('しわ', delta.wrinkleDelta),
        ],
      ),
    );
  }

  /// 詳細な比較結果表示UI（EnhancedSkinAnalysisResult使用）
  Future<Widget> _buildEnhancedComparisonCard() async {
    final cur = widget.skin;
    if (cur == null) return const SizedBox.shrink();

    try {
      // ComparativeSkinAnalysisServiceを使用して詳細な比較結果を取得
      // 注意: 実際の実装では、現在の画像ファイルとFaceオブジェクトが必要
      // ここでは既存のデータから比較結果を構築

      final baseline = await Storage.getBaselineSkin();
      final previous = await Storage.getLastSkin();

      if (baseline == null && previous == null) {
        return const SizedBox.shrink();
      }

      // 改善項目と悪化項目を計算
      final improvements = <String, double>{};
      final deteriorations = <String, double>{};
      final comparisonType = previous != null ? '前日比' : '基礎相比';

      // 比較データを取得（前日優先、なければ基礎相）
      final comparisonData = previous ?? baseline;

      if (comparisonData != null) {
        // 前日または基礎相との比較
        final dullnessDelta = (comparisonData['dullnessIndex'] ?? 0.0) - (cur.dullnessIndex ?? 0.0);
        final spotDelta = (comparisonData['spotDensity'] ?? 0.0) - (cur.spotDensity ?? 0.0);
        final acneDelta = (comparisonData['acneActivity'] ?? 0.0) - (cur.acneActivity ?? 0.0);
        final wrinkleDelta = (comparisonData['wrinkleDensity'] ?? 0.0) - (cur.wrinkleDensity ?? 0.0);
        final brightnessDelta = cur.brightness - (comparisonData['brightness'] ?? 0.5);
        final threshold = 0.05; // 5%以上の変化を検出

        if (dullnessDelta < -threshold)
          improvements['くすみ'] = dullnessDelta.abs();
        else if (dullnessDelta > threshold) deteriorations['くすみ'] = dullnessDelta;

        if (spotDelta < -threshold)
          improvements['シミ'] = spotDelta.abs();
        else if (spotDelta > threshold) deteriorations['シミ'] = spotDelta;

        if (acneDelta < -threshold)
          improvements['ニキビ'] = acneDelta.abs();
        else if (acneDelta > threshold) deteriorations['ニキビ'] = acneDelta;

        if (wrinkleDelta < -threshold)
          improvements['しわ'] = wrinkleDelta.abs();
        else if (wrinkleDelta > threshold) deteriorations['しわ'] = wrinkleDelta;

        if (brightnessDelta > threshold)
          improvements['明るさ'] = brightnessDelta;
        else if (brightnessDelta < -threshold) deteriorations['明るさ'] = brightnessDelta.abs();
      }

      // 安定性スコアを計算（変化が小さいほど高い）
      final stabilityScore = improvements.isEmpty && deteriorations.isEmpty
          ? 1.0
          : (1.0 -
                  (improvements.values.fold(0.0, (a, b) => a + b) + deteriorations.values.fold(0.0, (a, b) => a + b)) /
                      2.0)
              .clamp(0.0, 1.0);

      // グラフ用のデータを準備
      final chartData = <String, double>{
        'くすみ': cur.dullnessIndex ?? 0.0,
        'シミ': cur.spotDensity ?? 0.0,
        'ニキビ': cur.acneActivity ?? 0.0,
        'しわ': cur.wrinkleDensity ?? 0.0,
        '明るさ': cur.brightness,
      };

      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  '詳細比較結果（$comparisonType）',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // グラフ表示
            SizedBox(
              height: 200,
              child: _buildComparisonChart(chartData, comparisonData),
            ),
            const SizedBox(height: 16),
            if (improvements.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.arrow_upward, color: Colors.green.shade700, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          '改善項目',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...improvements.entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 16),
                                  const SizedBox(width: 4),
                                  Text(e.key, style: TextStyle(fontSize: 13)),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '+${(e.value * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (deteriorations.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200, width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.arrow_downward, color: Colors.red.shade700, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          '注意項目',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...deteriorations.entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning, color: Colors.red.shade700, size: 16),
                                  const SizedBox(width: 4),
                                  Text(e.key, style: TextStyle(fontSize: 13)),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '-${(e.value * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: Colors.red.shade800,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.trending_flat, color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 8),
                  Text('安定性スコア: ', style: TextStyle(fontSize: 13)),
                  Text(
                    '${(stabilityScore * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: stabilityScore > 0.7
                          ? Colors.green.shade700
                          : stabilityScore > 0.4
                              ? Colors.orange.shade700
                              : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }

  /// 比較結果のグラフを構築
  Widget _buildComparisonChart(Map<String, double> currentData, Map<String, dynamic>? comparisonData) {
    final labels = currentData.keys.toList();
    final currentValues = currentData.values.toList();
    final comparisonValues = comparisonData != null
        ? [
            comparisonData['dullnessIndex'] ?? 0.0,
            comparisonData['spotDensity'] ?? 0.0,
            comparisonData['acneActivity'] ?? 0.0,
            comparisonData['wrinkleDensity'] ?? 0.0,
            comparisonData['brightness'] ?? 0.5,
          ]
        : null;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 1.0,
        barTouchData: BarTouchData(
          enabled: false,
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      labels[value.toInt()],
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 40,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${(value * 100).toInt()}%',
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.2,
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.shade300),
        ),
        barGroups: List.generate(
          labels.length,
          (index) {
            final currentValue = currentValues[index];
            final comparisonValue = comparisonValues?[index];

            return BarChartGroupData(
              x: index,
              barRods: [
                // 比較値（前日/基礎相）
                if (comparisonValue != null)
                  BarChartRodData(
                    toY: comparisonValue,
                    color: Colors.grey.shade400,
                    width: 8,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                // 現在値
                BarChartRodData(
                  toY: currentValue,
                  color: comparisonValue != null && currentValue < comparisonValue
                      ? Colors.green.shade400
                      : comparisonValue != null && currentValue > comparisonValue
                          ? Colors.red.shade400
                          : Colors.blue.shade400,
                  width: 12,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Hugging Faceモデルの診断結果を表示（優先表示）
  Widget _buildHuggingFaceAIDiagnosisCard(SkinAnalysisResult skin) {
    final color = Color(int.parse(widget.god.colorHex.replaceFirst('#', '0xff')));

    // AI診断結果から主要指標を取得（生のAI分類結果を優先使用）
    double wrinkle, normal, darkCircle, acne, swelling;
    bool hasError = false;
    String? errorMessage;

    if (skin.aiClassification != null && skin.aiClassification!.isNotEmpty) {
      // Hugging Face AIの生の結果を優先使用（100%優先、既存分析は無視）
      // ⚠️ 重要: AI分類結果をそのまま使用（既存分析との融合は行わない）
      // UI表示では生のAI結果を100%使用
      // 強制調整後の再正規化済みの値を使用
      wrinkle = (skin.aiClassification!['wrinkle'] ?? 0.0) * 100;
      normal = (skin.aiClassification!['normal'] ?? 0.0) * 100;
      darkCircle = (skin.aiClassification!['darkcircle'] ?? 0.0) * 100;
      acne = (skin.aiClassification!['acne'] ?? 0.0) * 100;
      swelling = (skin.aiClassification!['swelling'] ?? 0.0) * 100;

      // 診断結果の合計を確認
      final total = acne + darkCircle + wrinkle + swelling + normal;

      // ⚠️ エラーチェック: すべての値が0.00%または合計が0の場合、分析未取得として扱う
      if (total < 0.01 || (wrinkle < 0.01 && normal < 0.01 && darkCircle < 0.01 && acne < 0.01 && swelling < 0.01)) {
        hasError = true;
        errorMessage = '肌の詳細分析は取得できませんでした。ネットワークを確認するか、あとでもう一度お試しください。性格診断結果はそのままご確認いただけます。';
      }

      // ⚠️ 正常肌が80%以上で他が0%の場合、モデルの出力を確認
      if (normal > 80.0 && (acne + darkCircle + wrinkle + swelling) < 5.0) {}

      // ⚠️ 強制調整が適用されているか確認（正常肌が30-60%の範囲内）
      if (normal >= 30.0 && normal <= 60.0 && acne >= 20.0) {}
    } else {
      // AI分類結果がない場合は肌詳細を非表示（メッセージはやわらかく）
      hasError = true;
      errorMessage = '肌の詳細分析は一時的に利用できませんでした。ネットワークを確認するか、あとでもう一度お試しください。性格診断結果はそのままご確認いただけます。';
      wrinkle = 0.0;
      darkCircle = 0.0;
      acne = 0.0;
      swelling = 0.0;
      normal = 0.0;
    }

    // エラーが発生した場合はエラーメッセージを表示
    if (hasError) {
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(.35), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade700, size: 24),
                const SizedBox(width: 8),
                Text(
                  '肌の詳細分析について',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    errorMessage ?? '肌の詳細分析は取得できませんでした。',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) {
                        return route.settings.name == '/capture' || route.isFirst;
                      });
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('写真を撮り直す'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 診断結果をリスト化（確率順）
    final diagnoses = [
      {'label': 'シワ', 'value': wrinkle, 'key': 'wrinkle'},
      {'label': '正常肌', 'value': normal, 'key': 'normal'},
      {'label': 'くま', 'value': darkCircle, 'key': 'darkcircle'},
      {'label': 'ニキビ', 'value': acne, 'key': 'acne'},
      {'label': 'むくみ', 'value': swelling, 'key': 'swelling'},
    ]..sort((a, b) => (b['value'] as double).compareTo(a['value'] as double));

    final topDiagnosis = diagnoses.first;
    final secondDiagnosis = diagnoses.length > 1 ? diagnoses[1] : null;
    final topConfidence = topDiagnosis['value'] as double;

    // 判定サマリーを生成
    String summaryText = '最も可能性が高い: ${topDiagnosis['label']} (${topConfidence.toStringAsFixed(1)}%)';
    if (secondDiagnosis != null) {
      summaryText += '\n次点: ${secondDiagnosis['label']} (${(secondDiagnosis['value'] as double).toStringAsFixed(1)}%)';
    }
    if (topConfidence < 50.0) {
      summaryText += '\n確信度が低め（${topConfidence.toStringAsFixed(1)}%）のため、正常肌の可能性もあります';
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.4), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: color, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Hugging Face AI診断結果',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 主要な判定結果
          const Text(
            '主要な判定結果',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...diagnoses.map((item) {
            final label = item['label'] as String;
            final value = item['value'] as double;
            final isZero = value < 0.01; // 0.00%またはそれに近い値

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$label (${item['key']}):',
                      style: TextStyle(
                        fontSize: 14,
                        color: isZero ? Colors.grey : null,
                      ),
                    ),
                  ),
                  Container(
                    width: 120,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: value / 100.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isZero ? Colors.grey : color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${value.toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isZero ? Colors.grey : color,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
          // 0.00%の値がある場合に警告を表示
          if (diagnoses.any((item) => (item['value'] as double) < 0.01)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(.5), width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '一部の診断値が0.00%です',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '診断結果が正確でない可能性があります。もう一度写真を撮ってアップロードしてください。',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            // キャプチャページに戻る
                            Navigator.of(context).popUntil((route) {
                              return route.settings.name == '/capture' || route.isFirst;
                            });
                          },
                          icon: const Icon(Icons.camera_alt, size: 16),
                          label: const Text('写真を撮り直す'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: const Size(0, 32),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // 判定サマリー
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '判定サマリー',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  summaryText,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.amber[200]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'この結果は参考情報です。医療診断は医師の診察を受けてください。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber[200],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIDiagnosisCard(SkinAIDiagnosisResult result) {
    final topDiagnosis = result.topDiagnosis ?? '';
    final topScore = result.topScore ?? 0.0;
    final translatedLabel = DiagnosisLabelTranslator.translate(topDiagnosis);
    final description = DiagnosisLabelTranslator.getDescription(topDiagnosis);
    final color = Color(int.parse(widget.god.colorHex.replaceFirst('#', '0xff')));

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science, color: color, size: 20),
              const SizedBox(width: 8),
              const Text(
                'AI診断結果',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translatedLabel,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '信頼度: ${topScore.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 14,
                        color: color.withOpacity(.9),
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (result.allResults != null && result.allResults!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '全ての診断結果',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...result.allResults!.take(5).map((item) {
              final itemLabel = DiagnosisLabelTranslator.translate(item.label);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        itemLabel,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      item.percentage,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.amber[200]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'この結果は参考情報です。医療診断は医師の診察を受けてください。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber[200],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebug(SkinAnalysisResult? s) {
    if (s == null) return const SizedBox.shrink();
    final entries = <String, String>{
      'eyeBrightness': (s.eyeBrightness ?? 0).toStringAsFixed(3),
      'darkCircle': (s.darkCircle ?? 0).toStringAsFixed(3),
      'browBalance': (s.browBalance ?? 0).toStringAsFixed(3),
      'noseGloss': (s.noseGloss ?? 0).toStringAsFixed(3),
      'jawPuffiness': (s.jawPuffiness ?? 0).toStringAsFixed(3),
      'dullnessIndex': (s.dullnessIndex ?? 0).toStringAsFixed(3),
      'spotDensity': (s.spotDensity ?? 0).toStringAsFixed(3),
      'acneActivity': (s.acneActivity ?? 0).toStringAsFixed(3),
      'wrinkleDensity': (s.wrinkleDensity ?? 0).toStringAsFixed(3),
      'textureFineness': (s.textureFineness ?? 0).toStringAsFixed(3),
      'colorUniformity': (s.colorUniformity ?? 0).toStringAsFixed(3),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DEBUG', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          for (final e in entries.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            )
        ],
      ),
    );
  }
}
