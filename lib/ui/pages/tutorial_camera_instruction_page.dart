import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'tutorial_camera_page.dart';

class TutorialCameraInstructionPage extends StatefulWidget {
  final String currentStep;

  const TutorialCameraInstructionPage({
    super.key,
    required this.currentStep,
  });

  @override
  State<TutorialCameraInstructionPage> createState() => _TutorialCameraInstructionPageState();
}

class _TutorialCameraInstructionPageState extends State<TutorialCameraInstructionPage> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    // BuildContextが利用可能になるまで待つ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeVideo();
    });
  }

  Future<void> _initializeVideo() async {
    if (!mounted) return;

    try {
      const videoPath = 'assets/videos/1000009921.mp4';
      print('[TutorialCameraInstructionPage] 🎬 動画の初期化を開始: $videoPath');

      // 動画ファイルの存在を確認（デバッグ用）
      try {
        await DefaultAssetBundle.of(context).load(videoPath);
        print('[TutorialCameraInstructionPage] ✅ 動画ファイルがアセットバンドルに存在します');
      } catch (e) {
        print('[TutorialCameraInstructionPage] ⚠️ 動画ファイルがアセットバンドルに見つかりません: $e');
        print('[TutorialCameraInstructionPage] 💡 pubspec.yamlに assets/videos/ が登録されているか確認してください');
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
        return;
      }

      _videoController = VideoPlayerController.asset(videoPath);

      // 初期化を待つ（タイムアウトを設定）
      await _videoController!.initialize().timeout(
        const Duration(seconds: 15), // タイムアウトを15秒に延長
        onTimeout: () {
          print('[TutorialCameraInstructionPage] ⏰ タイムアウト: 動画の初期化が15秒以内に完了しませんでした');
          throw TimeoutException('動画の初期化がタイムアウトしました');
        },
      );

      if (!_videoController!.value.isInitialized) {
        throw Exception('動画の初期化が完了しませんでした');
      }

      print('[TutorialCameraInstructionPage] ✅ 動画の初期化が完了しました');
      print('[TutorialCameraInstructionPage] 📐 動画サイズ: ${_videoController!.value.size}');
      print('[TutorialCameraInstructionPage] ⏱️ 動画の長さ: ${_videoController!.value.duration}');
      print('[TutorialCameraInstructionPage] 🔄 初期化状態: ${_videoController!.value.isInitialized}');

      // ループ再生を設定
      await _videoController!.setLooping(true);
      print('[TutorialCameraInstructionPage] 🔁 ループ再生を設定しました');

      // 再生を開始
      await _videoController!.play();
      print('[TutorialCameraInstructionPage] ▶️ 動画の再生を開始しました');

      // 再生状態を確認（少し待ってから）
      await Future.delayed(const Duration(milliseconds: 500));
      print('[TutorialCameraInstructionPage] 📊 再生状態: ${_videoController!.value.isPlaying}');
      print('[TutorialCameraInstructionPage] 📊 再生位置: ${_videoController!.value.position}');

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
      }
    } on TimeoutException catch (e) {
      print('[TutorialCameraInstructionPage] ⏰ タイムアウトエラー: $e');
      print('[TutorialCameraInstructionPage] 💡 動画ファイルが assets/videos/1000009921.mp4 に存在するか確認してください');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    } catch (e, stackTrace) {
      print('[TutorialCameraInstructionPage] ❌ 動画読み込みエラー: $e');
      print('[TutorialCameraInstructionPage] エラータイプ: ${e.runtimeType}');
      print('[TutorialCameraInstructionPage] 💡 動画ファイルが assets/videos/1000009921.mp4 に存在するか確認してください');
      print('[TutorialCameraInstructionPage] スタックトレース:');
      final stackLines = stackTrace.toString().split('\n');
      for (int i = 0; i < stackLines.length && i < 10; i++) {
        print('[TutorialCameraInstructionPage]   ${stackLines[i]}');
      }
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.currentStep == 'neutral' ? '真顔の写真を撮影' : '笑顔の写真を撮影'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                // 動画プレーヤー
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.purple.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _isVideoInitialized && _videoController != null && _videoController!.value.isInitialized
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              AspectRatio(
                                aspectRatio: _videoController!.value.aspectRatio,
                                child: VideoPlayer(_videoController!),
                              ),
                              // 再生状態を表示（デバッグ用）
                              if (_videoController!.value.isPlaying)
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '再生中',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          )
                        : _hasError
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.video_library_outlined,
                                    size: 64,
                                    color: Colors.orange.withOpacity(0.7),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '動画ファイルが見つかりません',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      '動画ファイル（1000009921.mp4）を\nassets/videos/ に配置してください',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.symmetric(horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.orange.withOpacity(0.5),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      '動画がなくても「次へ」ボタンで\nカメラ撮影に進めます',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.orange[200],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    color: Colors.purple[300],
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
                const SizedBox(height: 24),
                // 「髪を上げておでこを見せてください」の指示
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.purple.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.face_retouching_natural,
                        color: Colors.purple[300],
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '髪を上げておでこを見せてください',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // イラスト画像（フォールバック）
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/guides/sit_phone_forward.png',
                    height: 200,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                const SizedBox(height: 24),
                // 説明文
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.purple.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.chair,
                            color: Colors.purple[300],
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '椅子に座る',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInstructionItem(
                        icon: Icons.phone_android,
                        text: 'スマホを目の高さに持ってくる',
                      ),
                      const SizedBox(height: 12),
                      _buildInstructionItem(
                        icon: Icons.straighten,
                        text: 'スマホをまっすぐ（垂直）に構える',
                      ),
                      const SizedBox(height: 12),
                      _buildInstructionItem(
                        icon: Icons.face_retouching_natural,
                        text: '髪を上げておでこを見せる',
                      ),
                      const SizedBox(height: 12),
                      _buildInstructionItem(
                        icon: Icons.face,
                        text: '顔を正面に向けて、カメラを見る',
                      ),
                      const SizedBox(height: 12),
                      _buildInstructionItem(
                        icon: Icons.remove_red_eye,
                        text: '目を開けて、レンズを見る',
                      ),
                      const SizedBox(height: 12),
                      _buildInstructionItem(
                        icon: Icons.handyman,
                        text: 'スマホを固定して動かさない',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                // 次へボタン
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TutorialCameraPage(currentStep: widget.currentStep),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '次へ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionItem({
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: Colors.purple[300],
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
}
