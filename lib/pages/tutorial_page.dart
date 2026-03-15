import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:kami_face_oracle/services/face_analysis_service.dart';
import 'package:kami_face_oracle/services/fortune_logic.dart';
import 'package:kami_face_oracle/services/storage_service.dart';
import 'package:kami_face_oracle/services/image_input/image_input.dart';
import 'package:kami_face_oracle/services/image_input/image_input_impl.dart';
import 'package:kami_face_oracle/pages/fortune_result_page.dart';
import 'package:kami_face_oracle/widgets/deity_effects.dart';
import 'package:kami_face_oracle/features/consent/consent_service.dart';
import 'package:kami_face_oracle/features/consent/widgets/biometric_consent_modal.dart';

/// 初回チュートリアルページ（基礎神判定）
class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> with SingleTickerProviderStateMixin {
  final FaceAnalysisService _analysisService = FaceAnalysisService();
  bool _isAnalyzing = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final canUse = await ConsentService.instance.canUseBiometricFeatures();
    if (!canUse) {
      final ok = await BiometricConsentModal.show(context);
      if (!ok || !mounted) return;
    }
    final picked = await createImageInput().pick(preferCamera: false);
    if (picked == null) return;

    setState(() => _isAnalyzing = true);

    try {
      final bytes = Uint8List.fromList(picked.bytes);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;

      final faceData = await _analysisService.analyzeFace(uiImage);

      if (faceData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('顔が検出できませんでした')),
          );
        }
        setState(() => _isAnalyzing = false);
        return;
      }

      final deityId = FortuneLogic.determineBaselineDeity(faceData);
      final deity = FortuneLogic.getDeityById(deityId);

      await StorageService.saveBaseline(faceData);

      _animationController.forward();
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 2300));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FortuneResultPage(
              deity: deity,
              faceData: faceData,
              isBaseline: true,
            ),
          ),
        );
      }
    } catch (e) {
      print('[TutorialPage] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple.shade100,
              Colors.blue.shade100,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 80,
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 32),
                const Text(
                  'あなたの基礎神（陽占）を見つけましょう',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  '初回の顔写真から、あなたの基礎となる神を判定します。\n'
                  '自然な表情の写真を選んでください。',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                if (_isAnalyzing)
                  const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('顔を解析中...'),
                    ],
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('写真を選ぶ'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
                if (_isAnalyzing)
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _animationController.value,
                        child: Transform.scale(
                          scale: _animationController.value,
                          child: Container(
                            margin: const EdgeInsets.only(top: 32),
                            child: const Text(
                              '✨ 神が降臨しています... ✨',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
