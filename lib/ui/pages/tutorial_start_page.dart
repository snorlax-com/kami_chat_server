import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tutorial_camera_instruction_page.dart';

/// チュートリアル開始画面（Skura画像と指示を表示）
class TutorialStartPage extends StatefulWidget {
  final String currentStep;

  const TutorialStartPage({
    super.key,
    required this.currentStep,
  });

  @override
  State<TutorialStartPage> createState() => _TutorialStartPageState();
}

class _TutorialStartPageState extends State<TutorialStartPage> {
  String? _imagePath;
  bool _imageError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    // ユーザーが提供した画像（桜の花びらが舞っている画像）を優先的に読み込む
    // まずイラスト画像を試す（これが桜の花びらが舞っている画像であるべき）
    try {
      await rootBundle.load('assets/illustrations/skura.png');
      if (mounted) {
        setState(() {
          _imagePath = 'assets/illustrations/skura.png';
          _imageError = false;
        });
        print('[TutorialStartPage] ✅ イラスト画像が見つかりました: assets/illustrations/skura.png');
        print('[TutorialStartPage] 📸 画像パス: $_imagePath');
      }
    } catch (e) {
      print('[TutorialStartPage] ⚠️ イラスト画像が見つかりません: $e');
      // フォールバック: キャラクター画像を試す
      try {
        await rootBundle.load('assets/characters/skura.png');
        if (mounted) {
          setState(() {
            _imagePath = 'assets/characters/skura.png';
            _imageError = false;
          });
          print('[TutorialStartPage] ✅ キャラクター画像が見つかりました: assets/characters/skura.png');
          print('[TutorialStartPage] 📸 画像パス: $_imagePath');
        }
      } catch (e2) {
        print('[TutorialStartPage] ❌ キャラクター画像も見つかりません: $e2');
        if (mounted) {
          setState(() {
            _imagePath = null;
            _imageError = true;
          });
        }
      }
    }
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
                // Skura画像（イラスト画像を表示 - 桜の花びらが舞っている画像）
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(
                    maxHeight: 500,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.black,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _imagePath != null
                        ? Image.asset(
                            _imagePath!,
                            width: double.infinity,
                            fit: BoxFit.contain,
                            key: ValueKey(_imagePath), // 画像パスが変わったときに再描画
                            errorBuilder: (context, error, stackTrace) {
                              print('[TutorialStartPage] ❌ Image.asset読み込みエラー: $_imagePath, error=$error');
                              print(
                                  '[TutorialStartPage] スタックトレース: ${stackTrace.toString().split("\n").take(5).join("\n")}');
                              return _buildErrorWidget();
                            },
                            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                              if (wasSynchronouslyLoaded) {
                                print('[TutorialStartPage] ✅ 画像が同期的に読み込まれました: $_imagePath');
                              } else if (frame != null) {
                                print('[TutorialStartPage] ✅ 画像が非同期で読み込まれました: $_imagePath');
                              }
                              return child;
                            },
                          )
                        : _imageError
                            ? _buildErrorWidget()
                            : const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(40.0),
                                  child: CircularProgressIndicator(
                                    color: Colors.purple,
                                  ),
                                ),
                              ),
                  ),
                ),
                const SizedBox(height: 40),
                // 指示文
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.purple.withOpacity(0.5),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.purple[300],
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '椅子に座り、スマホを顔の高さまで上げて内カメラを見てください。',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
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
                          builder: (_) => TutorialCameraInstructionPage(
                            currentStep: widget.currentStep,
                          ),
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

  Widget _buildErrorWidget() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.face,
            size: 120,
            color: Colors.white.withOpacity(0.5),
          ),
          const SizedBox(height: 20),
          Text(
            'Skura',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '画像が見つかりません',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
