import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/ui/pages/personality_detail_page_view.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/core/deities.dart';

class PersonalityDiagnosisResultPage extends StatefulWidget {
  final PersonalityTreeDiagnosisResult diagnosisResult;

  const PersonalityDiagnosisResultPage({
    super.key,
    required this.diagnosisResult,
  });

  @override
  State<PersonalityDiagnosisResultPage> createState() => _PersonalityDiagnosisResultPageState();
}

class _PersonalityDiagnosisResultPageState extends State<PersonalityDiagnosisResultPage> {
  String? _pillarId;
  String? _displayTypeName; // 表示用のタイプ名
  String? _characterImagePath; // 柱のキャラクター画像パス
  String? _pillarTitle; // 柱のタイトル

  @override
  void initState() {
    super.initState();
    _loadPillarIdAndPlayMusic();
    _loadDisplayTypeName();
  }

  Future<void> _loadDisplayTypeName() async {
    // PersonalityTypeDetailServiceから正しいタイプ名を取得
    final detail = await PersonalityTypeDetailService.getDetail(widget.diagnosisResult.personalityType);
    if (detail != null && detail.typeName.isNotEmpty) {
      setState(() {
        _displayTypeName = detail.typeName;
      });
    } else {
      // フォールバック: 既存のpersonalityTypeNameを使用
      setState(() {
        _displayTypeName = widget.diagnosisResult.personalityTypeName;
      });
    }
  }

  @override
  void dispose() {
    // 音楽はBackgroundMusicServiceで管理されているため、ここでは停止しない
    // ホームに戻っても継続再生される
    super.dispose();
  }

  Future<void> _loadPillarIdAndPlayMusic() async {
    // pillarIdを取得
    final detail = await PersonalityTypeDetailService.getDetail(widget.diagnosisResult.personalityType);
    if (detail != null) {
      final pillarId = detail.pillarId;
      // キャラクター画像パスを構築
      final characterImagePath = 'assets/characters/${pillarId.toLowerCase()}.png';

      // deitiesからタイトルを取得
      String? pillarTitle;
      if (detail.pillarTitle.isNotEmpty) {
        pillarTitle = detail.pillarTitle;
      } else {
        try {
          final deity = deities.firstWhere(
            (d) => d.id.toLowerCase() == pillarId.toLowerCase(),
          );
          pillarTitle = deity.role;
        } catch (e) {
          pillarTitle = pillarId; // フォールバック: pillarIdを使用
        }
      }

      setState(() {
        _pillarId = pillarId;
        _characterImagePath = characterImagePath;
        _pillarTitle = pillarTitle;
      });
      // 瞑想音楽を再生
      _initBackgroundMusic(pillarId);
    }
  }

  Future<void> _initBackgroundMusic(String pillarId) async {
    try {
      final pillarIdLower = pillarId.toLowerCase();

      // BackgroundMusicServiceを使用して音楽を再生（既に再生中の場合は何もしない）
      await BackgroundMusicService().playMeditationMusic(pillarIdLower);
      print('[PersonalityDiagnosisResultPage] 瞑想音楽をBackgroundMusicServiceで再生: $pillarIdLower');
    } catch (e) {
      print('[PersonalityDiagnosisResultPage] BGM初期化エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('性格診断結果'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF8B5CF6).withOpacity(0.3),
                const Color(0xFF06B6D4).withOpacity(0.2),
                const Color(0xFF0A0E1A),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // 神秘的な背景
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  colors: [
                    const Color(0xFF8B5CF6).withOpacity(0.2),
                    const Color(0xFF06B6D4).withOpacity(0.15),
                    const Color(0xFF0A0E1A).withOpacity(0.9),
                    const Color(0xFF000000),
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                  radius: 1.5,
                ),
              ),
            ),
          ),
          // コンテンツ（チャット形式）
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Column(
                    children: [
                      // タイプ名のメッセージ
                      _buildChatMessage(
                        message:
                            '診断結果：あなたの性格タイプは「${_displayTypeName ?? widget.diagnosisResult.personalityTypeName ?? "タイプ ${widget.diagnosisResult.personalityType}"}」です。',
                        isFirst: true,
                      ),
                      const SizedBox(height: 12),

                      // 説明のメッセージ
                      _buildChatMessage(
                        message: widget.diagnosisResult.personalityDescription,
                      ),
                      const SizedBox(height: 12),

                      // 各層の判定結果をメッセージとして表示
                      ...widget.diagnosisResult.layerResults.entries.map((entry) {
                        final displayKey = entry.key.replaceAll('（', ' (').replaceAll('）', ')');
                        return Column(
                          children: [
                            _buildChatMessage(
                              message: '$displayKey: ${entry.value}',
                            ),
                            const SizedBox(height: 12),
                          ],
                        );
                      }),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // 詳細を見るボタン（下部に固定）
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E1A).withOpacity(0.9),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF8B5CF6).withOpacity(0.6),
                          const Color(0xFF06B6D4).withOpacity(0.5),
                          const Color(0xFF8B5CF6).withOpacity(0.6),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withOpacity(0.5),
                          blurRadius: 25,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (_pillarId == null) {
                          await _loadPillarIdAndPlayMusic();
                        }
                        if (mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PersonalityDetailPageView(
                                personalityType: widget.diagnosisResult.personalityType,
                                personalityTypeName: _displayTypeName ??
                                    widget.diagnosisResult.personalityTypeName ??
                                    "タイプ ${widget.diagnosisResult.personalityType}",
                                pillarId: _pillarId,
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.auto_awesome, size: 24, semanticLabel: '詳細'),
                      label: const Text(
                        '詳しく見る',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// チャットメッセージを構築
  Widget _buildChatMessage({
    required String message,
    bool isFirst = false,
  }) {
    // アイコン画像パス（フォールバック付き）
    final iconPath = _characterImagePath ?? 'assets/characters/shisaru.png';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 柱のアイコン（常に表示）
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(right: 12, top: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF8B5CF6).withOpacity(0.6),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                iconPath,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  // エラー時はデフォルトアイコンを表示
                  return Container(
                    color: Colors.grey[800],
                    child: const Icon(
                      Icons.face,
                      color: Colors.white70,
                      size: 28,
                    ),
                  );
                },
              ),
            ),
          ),

          // チャットバブル（左側に吹き出しのしっぽを追加）
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F3A).withOpacity(0.8),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(4), // しっぽの位置
                  topRight: const Radius.circular(18),
                  bottomRight: const Radius.circular(18),
                  bottomLeft: const Radius.circular(18),
                ),
                border: Border.all(
                  color: const Color(0xFF8B5CF6).withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 柱の名前（最初のメッセージのみ）
                  if (isFirst && _pillarTitle != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 14,
                            color: const Color(0xFF8B5CF6).withOpacity(0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _pillarTitle!,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF8B5CF6).withOpacity(0.9),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // メッセージ本文
                  Text(
                    message,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 15,
                      height: 1.6,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 右側のスペース（バランス調整）
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}
