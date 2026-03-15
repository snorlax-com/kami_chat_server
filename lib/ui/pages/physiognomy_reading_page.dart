import 'package:flutter/material.dart';
import 'package:kami_face_oracle/models/personality_type_detail.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';
import 'dart:ui';

/// 人相学占い結果表示ページ
/// 背景に柱の画像を配置し、神格化した演出で表示
class PhysiognomyReadingPage extends StatefulWidget {
  final int personalityType;
  final Map<String, double> skinScores; // {"tsuya": 0.66, "kesshoku": 0.62, ...}
  final String readingText; // 生成された占いテキスト

  const PhysiognomyReadingPage({
    super.key,
    required this.personalityType,
    required this.skinScores,
    required this.readingText,
  });

  @override
  State<PhysiognomyReadingPage> createState() => _PhysiognomyReadingPageState();
}

class _PhysiognomyReadingPageState extends State<PhysiognomyReadingPage> with SingleTickerProviderStateMixin {
  PersonalityTypeDetail? _detail;
  bool _isLoading = true;
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _loadPillarInfo();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadPillarInfo() async {
    final detail = await PersonalityTypeDetailService.getDetail(widget.personalityType);
    setState(() {
      _detail = detail;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A1A2E), // 深いブルー
        body: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF4A90E2), // ブルー
          ),
        ),
      );
    }

    final characterImage = _detail?.characterImage ?? '';
    final pillarTitle = _detail?.pillarTitle ?? '';
    final pillarId = _detail?.pillarId ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0A1A2E), // 深いブルー背景
      body: Stack(
        children: [
          // 背景：柱の画像（ぼかし＋オーバーレイ）
          _buildBackground(characterImage),

          // メインコンテンツ
          SafeArea(
            child: CustomScrollView(
              slivers: [
                // ヘッダー：柱の情報
                SliverToBoxAdapter(
                  child: _buildHeader(pillarTitle, pillarId, characterImage),
                ),

                // 占いテキスト
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  sliver: SliverToBoxAdapter(
                    child: _buildReadingContent(),
                  ),
                ),

                // 肌診断スコア表示
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  sliver: SliverToBoxAdapter(
                    child: _buildSkinScores(),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 40),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 背景：柱の画像をぼかして配置
  Widget _buildBackground(String characterImage) {
    return Stack(
      children: [
        // 背景画像
        if (characterImage.isNotEmpty)
          Positioned.fill(
            child: Image.asset(
              characterImage,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(color: const Color(0xFF0A1A2E));
              },
            ),
          )
        else
          Container(color: const Color(0xFF0A1A2E)),

        // ぼかしエフェクト
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),

        // ブルーオーバーレイ（神格化演出）
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0A1A2E).withOpacity(0.85),
                      const Color(0xFF1E3A5F).withOpacity(0.75 + _glowAnimation.value * 0.15),
                      const Color(0xFF0A1A2E).withOpacity(0.90),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // 光のエフェクト（上部）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 200,
          child: AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.5,
                    colors: [
                      const Color(0xFF4A90E2).withOpacity(_glowAnimation.value * 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// ヘッダー：柱の情報とタイトル
  Widget _buildHeader(String pillarTitle, String pillarId, String characterImage) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // 柱の画像（円形、光るエフェクト付き）
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              return Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4A90E2).withOpacity(_glowAnimation.value * 0.6),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                    BoxShadow(
                      color: const Color(0xFF87CEEB).withOpacity(_glowAnimation.value * 0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF4A90E2).withOpacity(0.8),
                      width: 3,
                    ),
                  ),
                  child: ClipOval(
                    child: characterImage.isNotEmpty
                        ? Image.asset(
                            characterImage,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildPlaceholderIcon(pillarId);
                            },
                          )
                        : _buildPlaceholderIcon(pillarId),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          // タイトル：「柱からのお告げ」
          Text(
            '【${pillarTitle}】からのお告げ',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE8F4F8), // 明るいブルーグレー
              shadows: [
                Shadow(
                  color: Color(0xFF4A90E2),
                  blurRadius: 20,
                ),
                Shadow(
                  color: Color(0xFF87CEEB),
                  blurRadius: 10,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // サブタイトル
          Text(
            '今日の運勢とアドバイス',
            style: TextStyle(
              fontSize: 16,
              color: const Color(0xFFB0D4E8).withOpacity(0.9),
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// プレースホルダーアイコン
  Widget _buildPlaceholderIcon(String pillarId) {
    return Container(
      color: const Color(0xFF1E3A5F),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.auto_awesome,
            size: 60,
            color: Color(0xFF4A90E2),
          ),
          const SizedBox(height: 8),
          Text(
            pillarId,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFB0D4E8),
            ),
          ),
        ],
      ),
    );
  }

  /// 占いテキストコンテンツ
  Widget _buildReadingContent() {
    // テキストを段落ごとに分割
    final paragraphs = widget.readingText.split('\n\n');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F).withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4A90E2).withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90E2).withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: paragraphs.map((paragraph) {
          if (paragraph.trim().isEmpty) return const SizedBox.shrink();

          // 見出しの判定（【】で囲まれている）
          final isHeading = paragraph.contains('【') && paragraph.contains('】');

          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: isHeading ? _buildHeading(paragraph) : _buildParagraph(paragraph),
          );
        }).toList(),
      ),
    );
  }

  /// 見出しスタイル
  Widget _buildHeading(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Color(0xFF87CEEB), // 明るいブルー
        height: 1.5,
      ),
    );
  }

  /// 段落スタイル
  Widget _buildParagraph(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        color: Color(0xFFE8F4F8), // 明るいブルーグレー
        height: 1.8,
        letterSpacing: 0.5,
      ),
    );
  }

  /// 肌診断スコア表示
  Widget _buildSkinScores() {
    final scoreLabels = {
      'tsuya': 'ツヤ',
      'kesshoku': '血色',
      'kusumi': 'くすみ',
      'kime': 'キメ',
      'kanso': '乾燥傾向',
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F).withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF4A90E2).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '今日の肌診断',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF87CEEB),
            ),
          ),
          const SizedBox(height: 16),
          ...widget.skinScores.entries.map((entry) {
            final label = scoreLabels[entry.key] ?? entry.key;
            final score = entry.value;
            final level = _getLevel(score);
            final levelText = _getLevelText(level);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFB0D4E8),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Stack(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: const Color(0xFF0A1A2E),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: score,
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF4A90E2),
                                  const Color(0xFF87CEEB),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 60,
                    child: Text(
                      levelText,
                      style: TextStyle(
                        fontSize: 12,
                        color: _getLevelColor(level),
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  String _getLevel(double score) {
    if (score < 0.40) return 'low';
    if (score < 0.70) return 'normal';
    return 'high';
  }

  String _getLevelText(String level) {
    switch (level) {
      case 'low':
        return '低め';
      case 'normal':
        return '標準';
      case 'high':
        return '高め';
      default:
        return '標準';
    }
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'low':
        return const Color(0xFF87CEEB); // 明るいブルー
      case 'normal':
        return const Color(0xFF4A90E2); // ミディアムブルー
      case 'high':
        return const Color(0xFF00BFFF); // 明るいスカイブルー
      default:
        return const Color(0xFF4A90E2);
    }
  }
}
