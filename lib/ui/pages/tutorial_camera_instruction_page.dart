import 'package:flutter/material.dart';
import 'tutorial_camera_page.dart';

/// 撮影前の姿勢・構えの説明（動画なし・静止画とテキストのみ）。
class TutorialCameraInstructionPage extends StatelessWidget {
  final String currentStep;

  const TutorialCameraInstructionPage({
    super.key,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(currentStep == 'neutral' ? '真顔の写真を撮影' : '笑顔の写真を撮影'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.purple.withValues(alpha: 0.5),
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
                      const Expanded(
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/guides/sit_phone_forward.png',
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.purple.withValues(alpha: 0.5),
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
                          const Text(
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
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TutorialCameraPage(currentStep: currentStep),
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
