import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kami_face_oracle/services/face_analysis_service.dart';
import 'package:kami_face_oracle/services/fortune_logic.dart';
import 'package:kami_face_oracle/services/storage_service.dart';
import 'package:kami_face_oracle/services/image_input/image_input.dart';
import 'package:kami_face_oracle/services/image_input/image_input_impl.dart';
import 'package:kami_face_oracle/models/face_data_model.dart';
import 'package:kami_face_oracle/pages/fortune_result_page.dart';
import 'package:kami_face_oracle/face_painter.dart';
import 'package:kami_face_oracle/features/consent/consent_service.dart';
import 'package:kami_face_oracle/features/consent/widgets/biometric_consent_modal.dart';

/// 毎日の投稿ページ
class DailyUploadPage extends StatefulWidget {
  const DailyUploadPage({super.key});

  @override
  State<DailyUploadPage> createState() => _DailyUploadPageState();
}

class _DailyUploadPageState extends State<DailyUploadPage> with TickerProviderStateMixin {
  final FaceAnalysisService _analysisService = FaceAnalysisService();
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableContours: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  bool _isAnalyzing = false;

  ui.Image? _uploadedImage;
  List<int>? _uploadedImageBytes;
  List<Face> _detectedFaces = [];
  late AnimationController _faceOutlineController;
  late AnimationController _leftEyeController;
  late AnimationController _rightEyeController;
  late AnimationController _leftEyebrowController;
  late AnimationController _rightEyebrowController;
  late AnimationController _noseController;
  late AnimationController _mouthController;

  bool _isNeutralPhotoTaken = false;
  ui.Image? _neutralImage;

  @override
  void initState() {
    super.initState();
    _checkBaseline();

    _faceOutlineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _leftEyeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _rightEyeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _leftEyebrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _rightEyebrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _noseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _mouthController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _faceOutlineController.dispose();
    _leftEyeController.dispose();
    _rightEyeController.dispose();
    _leftEyebrowController.dispose();
    _rightEyebrowController.dispose();
    _noseController.dispose();
    _mouthController.dispose();
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _checkBaseline() async {
    final hasBaseline = await StorageService.hasBaseline();
    if (!hasBaseline && mounted) {
      Navigator.pushReplacementNamed(context, '/tutorial');
    }
  }

  Future<void> _pickImage() async {
    final canUse = await ConsentService.instance.canUseBiometricFeatures();
    if (!canUse) {
      final ok = await BiometricConsentModal.show(context);
      if (!ok || !mounted) return;
    }
    final todayFortune = await StorageService.getTodayFortune();
    if (todayFortune != null && mounted) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('今日は既に診断済みです'),
          content: const Text('再度診断を行いますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('診断する'),
            ),
          ],
        ),
      );
      if (shouldContinue != true) return;
    }

    if (!_isNeutralPhotoTaken) {
      await _pickNeutralPhoto();
    } else {
      await _pickSmilingPhoto();
    }
  }

  Future<void> _pickNeutralPhoto() async {
    final picked = await createImageInput().pick(preferCamera: false);
    if (picked == null) return;

    setState(() => _isAnalyzing = true);

    try {
      final bytes = Uint8List.fromList(picked.bytes);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;

      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        setState(() => _isAnalyzing = false);
        return;
      }
      final metadata = InputImageMetadata(
        size: Size(uiImage.width.toDouble(), uiImage.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: uiImage.width * 4,
      );
      final inputImage = InputImage.fromBytes(
        bytes: byteData.buffer.asUint8List(),
        metadata: metadata,
      );
      uiImage.dispose();
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('顔が検出できませんでした')),
          );
        }
        setState(() => _isAnalyzing = false);
        return;
      }

      final face = faces.first;
      final smilingProbability = face.smilingProbability ?? 0.0;
      final isSmiling = smilingProbability > 0.4;

      if (isSmiling) {
        if (mounted) {
          final shouldRetry = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('笑顔が検出されました'),
              content: const Text('真顔の写真を撮影してください。\n無表情で正面を向いて撮影しましょう。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('もう一度撮影'),
                ),
              ],
            ),
          );
          setState(() => _isAnalyzing = false);
          if (shouldRetry == true) {
            await _pickNeutralPhoto();
          }
        }
        return;
      }

      setState(() {
        _neutralImage = uiImage;
        _isNeutralPhotoTaken = true;
        _isAnalyzing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('真顔の写真を撮影しました。次に笑顔の写真を撮影してください。'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('[DailyUploadPage] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
        setState(() => _isAnalyzing = false);
      }
    }
  }

  Future<void> _pickSmilingPhoto() async {
    final picked = await createImageInput().pick(preferCamera: false);
    if (picked == null) return;

    setState(() => _isAnalyzing = true);

    try {
      final bytes = Uint8List.fromList(picked.bytes);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;

      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        setState(() => _isAnalyzing = false);
        return;
      }
      final metadata = InputImageMetadata(
        size: Size(uiImage.width.toDouble(), uiImage.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.bgra8888,
        bytesPerRow: uiImage.width * 4,
      );
      final inputImage = InputImage.fromBytes(
        bytes: byteData.buffer.asUint8List(),
        metadata: metadata,
      );
      uiImage.dispose();
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('顔が検出できませんでした')),
          );
        }
        setState(() => _isAnalyzing = false);
        return;
      }

      final face = faces.first;
      final smilingProbability = face.smilingProbability ?? 0.0;
      final isSmiling = smilingProbability > 0.5;

      print('[DailyUploadPage] 笑顔確率: $smilingProbability (閾値: 0.5)');

      if (!isSmiling) {
        if (mounted) {
          String guidanceMessage = '';
          if (smilingProbability < 0.2) {
            guidanceMessage = '全く笑顔が検出されませんでした。\n口角をしっかり上げて、目も笑顔になるように心がけましょう。';
          } else if (smilingProbability < 0.35) {
            guidanceMessage = '笑顔が不十分です。\nもっと口角を上げて、歯を見せるような大きな笑顔にしましょう。';
          } else {
            guidanceMessage = 'もう少し大きな笑顔が必要です。\n口角を上げて、自然な笑顔を心がけましょう。';
          }

          final shouldRetry = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('笑顔を検出できませんでした'),
              content: Text('笑顔確率: ${(smilingProbability * 100).toStringAsFixed(0)}%\n\n$guidanceMessage'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('もう一度撮影'),
                ),
              ],
            ),
          );
          setState(() => _isAnalyzing = false);
          if (shouldRetry == true) {
            await _pickSmilingPhoto();
          }
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('笑顔を確認しました！(${(smilingProbability * 100).toStringAsFixed(0)}%)'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }

      setState(() {
        _uploadedImage = uiImage;
        _uploadedImageBytes = picked.bytes;
        _detectedFaces = faces;
      });

      await Future.delayed(const Duration(milliseconds: 100));
      await _startFaceOutlineAnimation();

      if (_neutralImage == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('真顔の写真が見つかりません。最初からやり直してください。')),
          );
        }
        setState(() {
          _isAnalyzing = false;
          _isNeutralPhotoTaken = false;
          _neutralImage = null;
        });
        return;
      }

      final baselineFaceData = await _analysisService.analyzeFace(_neutralImage!);

      if (baselineFaceData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('真顔の写真を解析できませんでした')),
          );
        }
        setState(() => _isAnalyzing = false);
        return;
      }

      final currentFaceData = await _analysisService.analyzeFace(uiImage);

      if (currentFaceData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('顔が検出できませんでした')),
          );
        }
        setState(() => _isAnalyzing = false);
        return;
      }

      final storedBaseline = await StorageService.getBaseline();
      final baselineFaceDataForComparison = storedBaseline ?? baselineFaceData;

      final fortuneMap = FortuneLogic.calculateDailyFortune(
        baselineFaceDataForComparison,
        currentFaceData,
      );

      final deity = FortuneLogic.getDeityById(fortuneMap['deity'] as String);

      final result = FortuneResult(
        mental: fortuneMap['mental'] as double,
        emotional: fortuneMap['emotional'] as double,
        physical: fortuneMap['physical'] as double,
        social: fortuneMap['social'] as double,
        stability: fortuneMap['stability'] as double,
        total: fortuneMap['total'] as double,
        deity: fortuneMap['deity'] as String,
        date: DateTime.now(),
      );

      await StorageService.saveFortuneResult(result);

      final history = await StorageService.getHistory();
      final isConsecutive = FortuneLogic.checkConsecutiveVisits(
        history,
        fortuneMap['deity'] as String,
      );

      if (mounted) {
        setState(() {
          _uploadedImage = null;
          _uploadedImageBytes = null;
          _detectedFaces = [];
          _isNeutralPhotoTaken = false;
          _neutralImage = null;
        });

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FortuneResultPage(
              deity: deity,
              faceData: currentFaceData,
              fortuneResult: result,
              isBaseline: false,
              isConsecutive: isConsecutive,
            ),
          ),
        );
      }
    } catch (e) {
      print('[DailyUploadPage] Error: $e');
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

  Future<void> _startFaceOutlineAnimation() async {
    if (!mounted) return;

    print('[DailyUploadPage] アニメーション開始');

    _faceOutlineController.reset();
    _leftEyeController.reset();
    _rightEyeController.reset();
    _leftEyebrowController.reset();
    _rightEyebrowController.reset();
    _noseController.reset();
    _mouthController.reset();

    if (mounted) {
      setState(() {});
    }

    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      print('[DailyUploadPage] 顔の輪郭アニメーション開始: ${_faceOutlineController.value}');
      await _faceOutlineController.forward();
      print('[DailyUploadPage] 顔の輪郭アニメーション完了: ${_faceOutlineController.value}');
    }

    if (mounted) {
      print('[DailyUploadPage] 目のアニメーション開始: left=${_leftEyeController.value}, right=${_rightEyeController.value}');
      await Future.wait([
        _leftEyeController.forward(),
        _rightEyeController.forward(),
      ]);
      print('[DailyUploadPage] 目のアニメーション完了');
    }

    if (mounted) {
      print('[DailyUploadPage] 眉のアニメーション開始');
      await Future.wait([
        _leftEyebrowController.forward(),
        _rightEyebrowController.forward(),
      ]);
      print('[DailyUploadPage] 眉のアニメーション完了');
    }

    if (mounted) {
      print('[DailyUploadPage] 鼻のアニメーション開始: ${_noseController.value}');
      await _noseController.forward();
      print('[DailyUploadPage] 鼻のアニメーション完了: ${_noseController.value}');
    }

    if (mounted) {
      print('[DailyUploadPage] 口のアニメーション開始: ${_mouthController.value}');
      await _mouthController.forward();
      print('[DailyUploadPage] 口のアニメーション完了: ${_mouthController.value}');
    }

    print('[DailyUploadPage] 全てのアニメーション完了');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日の顔を撮る'),
      ),
      body: _uploadedImage != null && _uploadedImageBytes != null && _detectedFaces.isNotEmpty
          ? _buildImageWithFaceOutline()
          : _buildUploadScreen(),
    );
  }

  Widget _buildUploadScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isNeutralPhotoTaken ? Icons.sentiment_very_satisfied : Icons.face,
              size: 80,
              color: Colors.deepPurple,
            ),
            const SizedBox(height: 32),
            Text(
              _isNeutralPhotoTaken ? '次に笑顔の写真を撮影してください\n口角を上げて、自然な笑顔を心がけましょう' : 'まず真顔の写真を撮影してください\n無表情で正面を向いて撮影しましょう',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (_isNeutralPhotoTaken) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '笑顔でない場合は再撮影が必要です',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 48),
            if (_isAnalyzing)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('顔を解析中...'),
                ],
              )
            else ...[
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: Icon(_isNeutralPhotoTaken ? Icons.sentiment_very_satisfied : Icons.photo_library),
                label: Text(_isNeutralPhotoTaken ? '笑顔の写真を選ぶ' : '真顔の写真を選ぶ'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 20,
                  ),
                  textStyle: const TextStyle(fontSize: 20),
                ),
              ),
              if (_isNeutralPhotoTaken) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isNeutralPhotoTaken = false;
                      _neutralImage = null;
                    });
                  },
                  child: const Text('真顔の写真を撮り直す'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageWithFaceOutline() {
    if (_uploadedImage == null || _uploadedImageBytes == null || _uploadedImageBytes!.isEmpty) {
      return _buildUploadScreen();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageAspect = _uploadedImage!.width / _uploadedImage!.height;
        final containerAspect = constraints.maxWidth / constraints.maxHeight;

        double displayWidth, displayHeight;
        if (imageAspect > containerAspect) {
          displayWidth = constraints.maxWidth;
          displayHeight = constraints.maxWidth / imageAspect;
        } else {
          displayHeight = constraints.maxHeight;
          displayWidth = constraints.maxHeight * imageAspect;
        }

        final imageWidget = Image.memory(
          Uint8List.fromList(_uploadedImageBytes!),
          fit: BoxFit.contain,
          width: displayWidth,
          height: displayHeight,
        );

        return Stack(
          children: [
            Center(
              child: SizedBox(
                width: displayWidth,
                height: displayHeight,
                child: RepaintBoundary(
                  child: Stack(
                    children: [
                      imageWidget,
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _faceOutlineController,
                          _leftEyeController,
                          _rightEyeController,
                          _leftEyebrowController,
                          _rightEyebrowController,
                          _noseController,
                          _mouthController,
                        ]),
                        builder: (context, child) {
                          return SizedBox(
                            width: displayWidth,
                            height: displayHeight,
                            child: CustomPaint(
                              willChange: true,
                              painter: FacePainter(
                                faces: _detectedFaces,
                                faceOutlineProgress: _faceOutlineController.value,
                                leftEyeProgress: _leftEyeController.value,
                                rightEyeProgress: _rightEyeController.value,
                                leftEyebrowProgress: _leftEyebrowController.value,
                                rightEyebrowProgress: _rightEyebrowController.value,
                                noseProgress: _noseController.value,
                                mouthProgress: _mouthController.value,
                                imageSize: Size(
                                  _uploadedImage!.width.toDouble(),
                                  _uploadedImage!.height.toDouble(),
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
            if (_isAnalyzing)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: Colors.white,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '顔を解析中...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
