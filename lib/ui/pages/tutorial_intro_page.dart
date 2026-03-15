import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'tutorial_start_page.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/core/deities.dart';

/// チュートリアルイントロ画面（動画と説明を順番に表示）
class TutorialIntroPage extends StatefulWidget {
  const TutorialIntroPage({super.key});

  @override
  State<TutorialIntroPage> createState() => _TutorialIntroPageState();
}

class _TutorialIntroPageState extends State<TutorialIntroPage> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  int _currentStep = 0; // 0-5のステップ

  // 降臨した柱の情報
  String _characterImagePath = 'assets/characters/skura.png';
  String _pillarTitle = 'スクラ';

  // 各ステップの説明文
  final List<String> _messages = [
    'AuraFaceの世界へようこそ',
    'あなたは直感で「この人は優しそう！」「この人は怖そう」などと感じたことはありますか？人は誰でも生まれつき人相見であります',
    'このアプリではまず、チュートリアルとしてAuraFaceの柱が陽占として人相を見てあなたの性格を占います',
    '人相を占った後、隠占として占い師に悩み事などがあれば打ち明け、チャット形式で相談することが可能です',
    'また、毎日の肌診断により人相学でも大切な肌についてその日の運勢占うことが可能です',
    'まずは陽占である人相をAuraFaceの柱に占ってもらい、あなたの性格にぴったりな柱に降臨してもらいましょう',
  ];

  @override
  void initState() {
    super.initState();
    _loadDescendedPillar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeVideo();
    });
  }

  /// 降臨した柱の情報を読み込む
  Future<void> _loadDescendedPillar() async {
    try {
      final deityId = await Storage.getTutorialDeity();
      if (deityId != null && deityId.isNotEmpty) {
        // 降臨した柱を取得
        try {
          final deity = deities.firstWhere(
            (d) => d.id.toLowerCase() == deityId.toLowerCase(),
          );
          setState(() {
            _characterImagePath = 'assets/characters/${deity.id.toLowerCase()}.png';
            _pillarTitle = deity.role;
          });
          print('[TutorialIntroPage] 降臨した柱を読み込み: ${deity.id} (${deity.role})');
        } catch (e) {
          print('[TutorialIntroPage] 柱が見つかりません: $deityId, デフォルトのSkuraを使用');
        }
      } else {
        print('[TutorialIntroPage] 降臨した柱がありません。デフォルトのSkuraを使用');
      }
    } catch (e) {
      print('[TutorialIntroPage] 柱情報の読み込みエラー: $e');
    }
  }

  Future<void> _initializeVideo() async {
    try {
      const videoPath = 'assets/videos/opening_animation.mp4';

      print('[TutorialIntroPage] 🎬 動画の初期化を開始: $videoPath');

      // ファイルの存在を確認
      try {
        await DefaultAssetBundle.of(context).load(videoPath);
        print('[TutorialIntroPage] ✅ 動画ファイルが見つかりました');
      } catch (e) {
        print('[TutorialIntroPage] ❌ 動画ファイルが見つかりません: $videoPath');
        print('[TutorialIntroPage] エラー詳細: $e');
        // 動画がなくても続行
        if (mounted) {
          setState(() {
            _isVideoInitialized = false;
          });
        }
        return;
      }

      print('[TutorialIntroPage] 📹 VideoPlayerControllerを作成中...');
      _videoController = VideoPlayerController.asset(videoPath);

      // 初期化を待つ（タイムアウトを30秒に延長）
      print('[TutorialIntroPage] ⏳ 動画の初期化を待機中...');
      await _videoController!.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('[TutorialIntroPage] ⚠️ 動画の初期化がタイムアウトしました（30秒）');
          throw TimeoutException('動画の初期化がタイムアウトしました');
        },
      );

      print('[TutorialIntroPage] 📊 動画情報:');
      print('  - 初期化済み: ${_videoController!.value.isInitialized}');
      print('  - アスペクト比: ${_videoController!.value.aspectRatio}');
      print('  - 解像度: ${_videoController!.value.size}');
      print('  - 長さ: ${_videoController!.value.duration}');

      if (!_videoController!.value.isInitialized) {
        print('[TutorialIntroPage] ❌ 動画の初期化が完了しませんでした');
        throw Exception('動画の初期化が完了しませんでした');
      }

      // ループ再生を設定
      print('[TutorialIntroPage] 🔁 ループ再生を設定中...');
      await _videoController!.setLooping(true);

      // 再生を開始
      print('[TutorialIntroPage] ▶️ 動画の再生を開始...');
      await _videoController!.play();

      // 再生状態を確認（少し待ってから）
      await Future.delayed(const Duration(milliseconds: 500));
      print('[TutorialIntroPage] 📊 再生状態: ${_videoController!.value.isPlaying}');
      print('[TutorialIntroPage] 📊 再生位置: ${_videoController!.value.position}');

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
        print('[TutorialIntroPage] ✅ 動画の初期化と再生が完了しました');
      }

      // 再生が開始されていない場合は再試行
      if (!_videoController!.value.isPlaying) {
        print('[TutorialIntroPage] ⚠️ 再生が開始されていません。再試行します...');
        await Future.delayed(const Duration(milliseconds: 500));
        await _videoController!.play();
        print('[TutorialIntroPage] 📊 再試行後の再生状態: ${_videoController!.value.isPlaying}');
      }
    } catch (e, stackTrace) {
      print('[TutorialIntroPage] ⚠️ 動画読み込みエラー: $e');
      print('[TutorialIntroPage] スタックトレース: $stackTrace');
      // 動画がなくても続行
      if (mounted) {
        setState(() {
          _isVideoInitialized = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _messages.length - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      // 最後のステップ: 既存のチュートリアルへ
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const TutorialStartPage(currentStep: 'neutral'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentMessage = _messages[_currentStep];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 動画（上部）
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                color: Colors.black,
                child: _isVideoInitialized && _videoController != null && _videoController!.value.isInitialized
                    ? ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.width / (_videoController!.value.aspectRatio),
                              child: VideoPlayer(_videoController!),
                            ),
                          ),
                        ),
                      )
                    : Container(
                        color: Colors.black,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(
                                color: Colors.purple,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '動画を準備しています…',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),

            // チャット形式の説明文とボタン（下部）
            Expanded(
              flex: 1,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.black,
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    // チャットメッセージ表示エリア
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        child: _buildChatMessage(
                          message: currentMessage,
                          isFirst: _currentStep == 0,
                        ),
                      ),
                    ),

                    // 次へボタン（下部に固定）
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _nextStep,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 8,
                          ),
                          child: Text(
                            _currentStep < _messages.length - 1 ? '次へ' : '始める',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// チャットメッセージを構築
  Widget _buildChatMessage({
    required String message,
    bool isFirst = false,
  }) {
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
                _characterImagePath,
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
                  if (isFirst)
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
                            _pillarTitle,
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
