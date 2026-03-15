import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../core/tutorial_classifier.dart';

class BatchDiagnosisPage extends StatefulWidget {
  final List<String> imagePaths;

  const BatchDiagnosisPage({required this.imagePaths, super.key});

  @override
  State<BatchDiagnosisPage> createState() => _BatchDiagnosisPageState();
}

class _BatchDiagnosisPageState extends State<BatchDiagnosisPage> {
  final _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
    ),
  );

  final _results = <Map<String, dynamic>>[];
  int _currentIndex = 0;
  bool _isProcessing = false;
  String _statusMessage = '準備中...';

  @override
  void initState() {
    super.initState();
    _startDiagnosis();
  }

  Future<void> _startDiagnosis() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = '診断を開始します...';
    });

    for (var i = 0; i < widget.imagePaths.length; i++) {
      final imagePath = widget.imagePaths[i];
      setState(() {
        _currentIndex = i;
        _statusMessage = '診断中: ${i + 1}/${widget.imagePaths.length} - ${imagePath.split('/').last}';
      });

      try {
        final file = File(imagePath);
        if (!await file.exists()) {
          _results.add({
            'image': imagePath,
            'deity': 'N/A',
            'error': 'ファイルが見つかりません',
          });
          continue;
        }

        final inputImage = InputImage.fromFilePath(imagePath);
        final faces = await _faceDetector.processImage(inputImage);

        if (faces.isEmpty) {
          _results.add({
            'image': imagePath,
            'deity': 'N/A',
            'error': '顔が検出されませんでした',
          });
          continue;
        }

        final face = faces.first;
        final diagnosis = await TutorialClassifier.diagnose(face);

        _results.add({
          'image': imagePath,
          'deity': diagnosis.deityId,
          'zone': diagnosis.zone,
          'polarity': diagnosis.polarity,
          'faceShape': diagnosis.faceShape,
          'reason': diagnosis.reason,
        });
      } catch (e) {
        _results.add({
          'image': imagePath,
          'deity': 'N/A',
          'error': e.toString(),
        });
      }
    }

    setState(() {
      _isProcessing = false;
      _statusMessage = '診断完了';
    });

    _saveResults();
  }

  void _saveResults() {
    final deityCounts = <String, int>{};
    for (final result in _results) {
      final deity = result['deity'] as String;
      if (deity != 'N/A') {
        deityCounts[deity] = (deityCounts[deity] ?? 0) + 1;
      }
    }

    final sorted = deityCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final mdContent = StringBuffer();
    mdContent.writeln('# 34枚の画像診断結果（最新の分散化調整を反映）');
    mdContent.writeln('');
    mdContent.writeln('## 診断対象画像数');
    mdContent.writeln('**${widget.imagePaths.length}枚の画像**を診断');
    mdContent.writeln('');
    mdContent.writeln('---');
    mdContent.writeln('');
    mdContent.writeln('## 各画像の診断結果');
    mdContent.writeln('');

    for (var i = 0; i < _results.length; i++) {
      final result = _results[i];
      final imagePath = result['image'] as String;
      final fileName = imagePath.split('/').last;
      mdContent.writeln('### 画像${i + 1}: $fileName');
      if (result.containsKey('error')) {
        mdContent.writeln('- **エラー**: ${result['error']}');
      } else {
        mdContent.writeln('- **診断結果**: **${result['deity']}**');
        mdContent.writeln('- **三停**: ${result['zone']}');
        mdContent.writeln('- **陰陽**: ${result['polarity']}');
        mdContent.writeln('- **顔の形**: ${result['faceShape']}');
        mdContent.writeln('- **理由**: ${result['reason']}');
      }
      mdContent.writeln('');
    }

    mdContent.writeln('---');
    mdContent.writeln('');
    mdContent.writeln('## 柱ごとの出現回数ランキング');
    mdContent.writeln('');
    mdContent.writeln('| 順位 | 柱名 | 出現回数 | 出現率 |');
    mdContent.writeln('|------|------|----------|--------|');

    for (var i = 0; i < sorted.length; i++) {
      final entry = sorted[i];
      final percentage = (entry.value / widget.imagePaths.length * 100).toStringAsFixed(1);
      mdContent.writeln('| ${i + 1}位 | **${entry.key}** | ${entry.value}回 | ${percentage}% |');
    }

    final allDeities = [
      'Amatera',
      'Yatael',
      'Skura',
      'Delphos',
      'Amanoira',
      'Noirune',
      'Ragias',
      'Verdatsu',
      'Osiria',
      'Fatemis',
      'Kanonis',
      'Sylna',
      'Yorusi',
      'Tenkora',
      'Shisaru',
      'Mimika',
      'Tenmira',
      'Shiran'
    ];
    final missingDeities = allDeities.where((d) => !deityCounts.containsKey(d)).toList();
    if (missingDeities.isNotEmpty) {
      for (final deity in missingDeities) {
        mdContent.writeln('| - | **$deity** | 0回 | 0% |');
      }
    }

    // 結果をファイルに保存（アプリのドキュメントディレクトリに保存）
    // 実際の保存処理は実装が必要
    print('診断結果:\n$mdContent');
  }

  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deityCounts = <String, int>{};
    for (final result in _results) {
      final deity = result['deity'] as String;
      if (deity != 'N/A') {
        deityCounts[deity] = (deityCounts[deity] ?? 0) + 1;
      }
    }

    final sorted = deityCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('一括診断'),
      ),
      body: _isProcessing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusMessage),
                  const SizedBox(height: 8),
                  Text('${_currentIndex + 1}/${widget.imagePaths.length}'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '診断結果',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text('総画像数: ${widget.imagePaths.length}'),
                Text('成功: ${_results.where((r) => r['deity'] != 'N/A').length}'),
                Text('失敗: ${_results.where((r) => r['deity'] == 'N/A').length}'),
                const SizedBox(height: 24),
                Text(
                  '柱ごとの出現回数ランキング',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                ...sorted.map((entry) {
                  final percentage = (entry.value / widget.imagePaths.length * 100).toStringAsFixed(1);
                  return ListTile(
                    title: Text(entry.key),
                    trailing: Text('${entry.value}回 (${percentage}%)'),
                  );
                }),
              ],
            ),
    );
  }
}
