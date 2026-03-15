import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:kami_face_oracle/models/personality_type_detail.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/ui/pages/pillar_chat_page.dart';

/// 性格診断結果の詳細を1項目ずつ表示するページ
class PersonalityDetailPageView extends StatefulWidget {
  final int personalityType;
  final String personalityTypeName;
  final String? pillarId;

  const PersonalityDetailPageView({
    super.key,
    required this.personalityType,
    required this.personalityTypeName,
    this.pillarId,
  });

  @override
  State<PersonalityDetailPageView> createState() => _PersonalityDetailPageViewState();
}

class _PersonalityDetailPageViewState extends State<PersonalityDetailPageView> {
  late PageController _pageController;
  PersonalityTypeDetail? _detail;
  bool _isLoading = true;
  int _currentPage = 0;
  String? _currentPillarId; // 音楽継続再生用

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadDetail();
    // 音楽は詳細が読み込まれた後に初期化
  }

  @override
  void dispose() {
    _pageController.dispose();
    // 音楽はホーム画面でも継続するため、ここでは停止しない
    super.dispose();
  }

  Future<void> _loadDetail() async {
    print('[PersonalityDetailPageView] 詳細を読み込み中: type=${widget.personalityType}, pillarId=${widget.pillarId}');
    try {
      final detail = await PersonalityTypeDetailService.getDetail(widget.personalityType);
      print('[PersonalityDetailPageView] 詳細データ取得: ${detail != null ? "成功" : "失敗"}');
      if (detail != null) {
        print('[PersonalityDetailPageView] 詳細情報:');
        print('  - pillarId: ${detail.pillarId}');
        print('  - pillarTitle: ${detail.pillarTitle}');
        print('  - typeName: ${detail.typeName}');
        print('  - sections数: ${detail.sections.length}');
        print('  - orderedSections数: ${detail.orderedSections.length}');
        for (final entry in detail.orderedSections) {
          print('    - ${entry.key}: ${entry.value.title} (${entry.value.content.length}文字)');
        }
      }
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
      // 詳細が読み込まれたら音楽を初期化
      if (detail != null) {
        print('[PersonalityDetailPageView] 詳細を読み込み完了: pillarId=${detail.pillarId}');
        _currentPillarId = detail.pillarId;
        _initBackgroundMusic();
      } else {
        print('[PersonalityDetailPageView] ⚠️ 詳細の読み込みに失敗しました');
      }
    } catch (e, stackTrace) {
      print('[PersonalityDetailPageView] ❌ エラー: $e');
      print('[PersonalityDetailPageView] スタックトレース: ${stackTrace.toString().split("\n").take(5).join("\n")}');
      setState(() {
        _detail = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _initBackgroundMusic() async {
    try {
      // 各柱の瞑想音楽を再生（ホーム画面でも継続するため、BackgroundMusicServiceに登録）
      final pillarId = (widget.pillarId ?? _detail?.pillarId ?? '').toLowerCase();
      print(
          '[PersonalityDetailPageView] 瞑想音楽を再生: pillarId=$pillarId (widget.pillarId=${widget.pillarId}, detail.pillarId=${_detail?.pillarId})');

      if (pillarId.isNotEmpty) {
        // BackgroundMusicServiceに瞑想音楽を登録（ホーム画面でも継続）
        // 既に同じ音楽が再生中の場合は何もしない（重複再生を防ぐ）
        await BackgroundMusicService().playMeditationMusic(pillarId);
      }
    } catch (e) {
      print('[PersonalityDetailPageView] BGM初期化エラー: $e');
      // BGMファイルがない場合は無音で続行
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: _buildBackgroundDecoration(),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_detail == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('詳細情報'),
        ),
        body: Container(
          decoration: _buildBackgroundDecoration(),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'データが見つかりませんでした',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'タイプ: ${widget.personalityType}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('戻る'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final sections = _detail!.orderedSections;
    final totalPages = sections.length;

    print('[PersonalityDetailPageView] 表示準備: totalPages=$totalPages');
    if (totalPages == 0) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('詳細情報'),
        ),
        body: Container(
          decoration: _buildBackgroundDecoration(),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'セクションが見つかりませんでした',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'タイプ: ${widget.personalityType}, セクション数: ${_detail!.sections.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('戻る'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 画像パスを決定
    String characterImagePath = _detail!.characterImage;
    if (characterImagePath.isEmpty && widget.pillarId != null && widget.pillarId!.isNotEmpty) {
      characterImagePath = 'assets/characters/${widget.pillarId!.toLowerCase()}.png';
    }
    final pillarTitle = _detail!.pillarTitle.isNotEmpty ? _detail!.pillarTitle : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('性格診断詳細'),
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
          // コンテンツ（PageViewで各セクションを1ページずつ表示）
          Column(
            children: [
              // プログレスインジケーター
              _buildProgressIndicator(_currentPage, totalPages),

              // ページビュー（各セクションを1ページずつ）
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemCount: totalPages,
                  itemBuilder: (context, index) {
                    if (index >= sections.length) {
                      return const Center(child: Text('エラー: セクションが見つかりません'));
                    }
                    final sectionEntry = sections[index];
                    final section = sectionEntry.value;
                    return _buildSectionPage(
                      section.title,
                      section.content,
                      characterImagePath,
                      pillarTitle,
                      index == 0,
                    );
                  },
                ),
              ),

              // ナビゲーションボタン
              _buildNavigationButtons(_currentPage, totalPages),
            ],
          ),
        ],
      ),
    );
  }

  /// 背景の装飾（世界観に合わせたグラデーション）
  BoxDecoration _buildBackgroundDecoration() {
    // タイプに応じた色を取得（簡易版）
    final colors = _getTypeColors(widget.personalityType);

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors[0].withOpacity(0.3),
          colors[1].withOpacity(0.2),
          colors[0].withOpacity(0.4),
        ],
        stops: const [0.0, 0.5, 1.0],
      ),
    );
  }

  /// タイプに応じた色を取得
  List<Color> _getTypeColors(int typeId) {
    // タイプごとの色設定（簡易版）
    final colorMap = {
      1: [Colors.blue.shade300, Colors.purple.shade200], // 協調的リーダー
      2: [Colors.orange.shade400, Colors.red.shade300], // 情熱的革新者
      3: [Colors.green.shade300, Colors.teal.shade200], // 柔軟な適応者
      4: [Colors.pink.shade300, Colors.orange.shade200], // 情熱的表現者
      5: [Colors.grey.shade400, Colors.blueGrey.shade300], // 堅実な計画者
      6: [Colors.yellow.shade300, Colors.orange.shade200], // 社交的楽天家
      7: [Colors.blueGrey.shade400, Colors.grey.shade300], // バランス型実務家
      8: [Colors.red.shade400, Colors.orange.shade300], // 情熱的リーダー
      9: [Colors.amber.shade400, Colors.yellow.shade300], // 積極的開拓者
      10: [Colors.purple.shade400, Colors.pink.shade300], // 複雑な個性型
      11: [Colors.indigo.shade300, Colors.blue.shade200], // 冷静な観察者
      12: [Colors.green.shade400, Colors.teal.shade300], // 寛大な支援者
      13: [Colors.purple.shade300, Colors.indigo.shade200], // 内向的芸術家
      14: [Colors.orange.shade300, Colors.amber.shade200], // 情熱的革新者（協調寄り）
      15: [Colors.blueGrey.shade500, Colors.grey.shade400], // 冷静な完璧主義者
    };

    return colorMap[typeId] ?? [Colors.purple.shade300, Colors.blue.shade200];
  }

  /// プログレスインジケーター
  Widget _buildProgressIndicator(int current, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            '${current + 1} / $total',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LinearProgressIndicator(
              value: (current + 1) / total,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.white.withOpacity(0.8),
              ),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  /// セクションページを構築（チャット形式）
  Widget _buildSectionPage(
    String title,
    String content,
    String characterImagePath,
    String pillarTitle,
    bool isFirst,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: _buildChatMessage(
        title: title,
        message: content,
        characterImagePath: characterImagePath,
        pillarTitle: pillarTitle,
        isFirst: isFirst,
      ),
    );
  }

  /// チャットメッセージを構築
  Widget _buildChatMessage({
    required String title,
    required String message,
    required String characterImagePath,
    required String pillarTitle,
    bool isFirst = false,
  }) {
    // アイコン画像パス（フォールバック付き）
    final iconPath = characterImagePath.isNotEmpty ? characterImagePath : 'assets/characters/shisaru.png';

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
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 柱の名前（最初のメッセージのみ）
                  if (isFirst && pillarTitle.isNotEmpty)
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
                            pillarTitle,
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

                  // セクションタイトル
                  if (title.isNotEmpty) ...[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.95),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // メッセージ本文
                  Text(
                    message.isNotEmpty ? message : '内容がありません',
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

  /// ナビゲーションボタン
  Widget _buildNavigationButtons(int current, int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 前へボタン
          if (current > 0)
            TextButton.icon(
              onPressed: () {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              label: const Text(
                '前へ',
                style: TextStyle(color: Colors.white),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            )
          else
            const SizedBox(width: 80),

          // 次へ/完了ボタン
          ElevatedButton.icon(
            onPressed: () {
              if (current < total - 1) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              } else {
                // 最後のページ：チャットページへ遷移
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PillarChatPage(
                      personalityType: widget.personalityType,
                      pillarId: widget.pillarId,
                    ),
                  ),
                );
              }
            },
            icon: Icon(
              current < total - 1 ? Icons.arrow_forward : Icons.check,
              color: Colors.white,
            ),
            label: Text(
              current < total - 1 ? '次へ' : '完了',
              style: const TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple.withOpacity(0.8),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              elevation: 4,
            ),
          ),
        ],
      ),
    );
  }
}

/// タイプライター効果でテキストを表示するWidget
class _TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final VoidCallback? onComplete;
  final Duration delay;

  const _TypewriterText({
    required this.text,
    required this.style,
    this.onComplete,
    this.delay = const Duration(milliseconds: 30),
  });

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  String _displayText = '';
  Timer? _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTyping() {
    _timer = Timer.periodic(widget.delay, (timer) {
      if (_currentIndex < widget.text.length) {
        setState(() {
          _displayText = widget.text.substring(0, _currentIndex + 1);
          _currentIndex++;
        });
      } else {
        timer.cancel();
        widget.onComplete?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayText,
      style: widget.style,
    );
  }
}
