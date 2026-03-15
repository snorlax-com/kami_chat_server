import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';

/// すべての柱の写真を表示するページ
class AllPillarsGalleryPage extends StatelessWidget {
  const AllPillarsGalleryPage({super.key});

  // 柱のIDリスト（全18柱 - すべて使用中）
  static const List<String> pillarIds = [
    'shisaru', // 星の神
    'ragias', // 雷の神
    'shiran', // 旅の神
    'yatael', // 導きの神
    'amanoira', // 宿命の神
    'tenkora', // 狐の神
    'kanonis', // 慈愛の神
    'yorusi', // 太陽の使い
    'tenmira', // 未来の神
    'amatera', // 太陽の女神
    'mimika', // 知恵の神
    'sylna', // 森の神
    'noirune', // 月の神
    'skura', // 春の神
    'fatemis', // 運命の神
    'delphos', // 神託の神
    'verdatsu', // 時の神
    'osiria', // 愛の神
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('すべての柱の写真'),
        backgroundColor: Colors.black87,
      ),
      backgroundColor: Colors.black,
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: pillarIds.length,
        itemBuilder: (context, index) {
          final pillarId = pillarIds[index];
          return _PillarPhotoCard(pillarId: pillarId);
        },
      ),
    );
  }
}

class _PillarPhotoCard extends StatefulWidget {
  final String pillarId;

  const _PillarPhotoCard({required this.pillarId});

  @override
  State<_PillarPhotoCard> createState() => _PillarPhotoCardState();
}

class _PillarPhotoCardState extends State<_PillarPhotoCard> {
  String? _characterImagePath;
  String? _illustrationImagePath;
  String? _pillarTitle;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPillarInfo();
  }

  Future<void> _loadPillarInfo() async {
    // まず、deitiesから該当する神を探す
    Deity? deity;
    try {
      deity = deities.firstWhere(
        (d) => d.id.toLowerCase() == widget.pillarId.toLowerCase(),
        orElse: () => deities.first,
      );
    } catch (e) {
      print('[AllPillarsGalleryPage] 神が見つかりません: ${widget.pillarId}');
    }

    // 画像パスを構築
    final characterPath = 'assets/characters/${widget.pillarId.toLowerCase()}.png';
    final illustrationPath = 'assets/illustrations/${widget.pillarId.toLowerCase()}.png';

    // タイトルを取得（deityから、またはpillar_mapping.jsonから）
    String? title;
    if (deity != null) {
      title = deity.role;
    } else {
      // pillar_mapping.jsonから取得を試みる（必要に応じて実装）
      title = _getPillarTitleFromId(widget.pillarId);
    }

    setState(() {
      _characterImagePath = characterPath;
      _illustrationImagePath = illustrationPath;
      _pillarTitle = title;
      _loading = false;
    });
  }

  String _getPillarTitleFromId(String pillarId) {
    final titles = {
      'shisaru': '星の神',
      'ragias': '雷の神',
      'shiran': '旅の神',
      'yatael': '導きの神',
      'amanoira': '宿命の神',
      'tenkora': '狐の神',
      'kanonis': '慈愛の神',
      'yorusi': '太陽の使い',
      'tenmira': '未来の神',
      'amatera': '太陽の女神',
      'mimika': '知恵の神',
      'sylna': '森の神',
      'noirune': '月の神',
      'skura': '春の神',
      'fatemis': '運命の神',
      'delphos': '神託の神',
      'verdatsu': '時の神',
      'osiria': '愛の神（海の女神）',
    };
    return titles[pillarId.toLowerCase()] ?? pillarId;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onTap: () => _showFullScreen(context),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.black87,
                Colors.black54,
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // キャラクター画像（円形）
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: ClipOval(
                    child: Image.asset(
                      _characterImagePath!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        // キャラクター画像がない場合はイラスト画像を試す
                        return Image.asset(
                          _illustrationImagePath!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error2, stackTrace2) {
                            return Container(
                              color: Colors.grey[800],
                              child: const Icon(
                                Icons.person,
                                size: 64,
                                color: Colors.white54,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
              // タイトル
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _pillarTitle ?? widget.pillarId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullScreen(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // フルスクリーン画像
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Image.asset(
                  _characterImagePath!,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset(
                      _illustrationImagePath!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error2, stackTrace2) {
                        return Container(
                          width: 300,
                          height: 300,
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.person,
                            size: 128,
                            color: Colors.white54,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            // 閉じるボタン
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  shape: const CircleBorder(),
                ),
              ),
            ),
            // タイトル
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _pillarTitle ?? widget.pillarId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
