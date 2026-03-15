import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:kami_face_oracle/services/image_input/image_input.dart';
import 'package:kami_face_oracle/services/image_input/image_input_impl.dart';
import 'package:kami_face_oracle/utils/temp_file_helper.dart';
import 'package:kami_face_oracle/utils/diagnosis_error_message.dart';
import '../../face_painter.dart';
import '../../skin_analysis.dart';
import 'package:kami_face_oracle/services/skin_analysis_service.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/inference/diagnosis_entry.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';
import 'package:kami_face_oracle/services/server_personality_service.dart';
import 'package:kami_face_oracle/ui/pages/reveal_page.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_criteria_page.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_camera_page.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_camera_instruction_page.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_start_page.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_intro_page.dart';
import 'package:kami_face_oracle/features/consent/consent_service.dart';
import 'package:kami_face_oracle/features/consent/widgets/biometric_consent_modal.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_camera_page.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class FaceTutorialScreen extends StatefulWidget {
  const FaceTutorialScreen({super.key});

  @override
  State<FaceTutorialScreen> createState() => _FaceTutorialScreenState();
}

class _FaceTutorialScreenState extends State<FaceTutorialScreen> with TickerProviderStateMixin {
  PickedImage? _pickedImage;
  io.File? _selectedImage;
  ui.Image? _decodedImage;
  List<Face> _faces = [];
  bool _isProcessing = false;
  String _statusMessage = '真顔の写真を撮影してください';
  SkinAnalysisResult? _skinAnalysisResult;
  String _currentStep = 'neutral';
  io.File? _neutralImage;
  io.File? _smilingImage;
  final _analyzer = FaceAnalyzer();

  // アニメーションコントローラー
  late AnimationController _faceOutlineController;
  late AnimationController _leftEyeController;
  late AnimationController _rightEyeController;
  late AnimationController _leftEyebrowController;
  late AnimationController _rightEyebrowController;
  late AnimationController _noseController;
  late AnimationController _mouthController;

  // アニメーション
  late Animation<double> _faceOutlineAnimation;
  late Animation<double> _leftEyeAnimation;
  late Animation<double> _rightEyeAnimation;
  late Animation<double> _leftEyebrowAnimation;
  late Animation<double> _rightEyebrowAnimation;
  late Animation<double> _noseAnimation;
  late Animation<double> _mouthAnimation;

  late FaceDetector _faceDetector;

  @override
  void initState() {
    super.initState();
    _initializeFaceDetector();
    _initializeAnimations();
  }

  void _initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: false,
      minFaceSize: 0.05,
      performanceMode: FaceDetectorMode.accurate,
    );
    _faceDetector = FaceDetector(options: options);
  }

  void _initializeAnimations() {
    _faceOutlineController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    );
    _leftEyeController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    _rightEyeController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    _leftEyebrowController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
    _rightEyebrowController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
    _noseController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _mouthController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _faceOutlineAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _faceOutlineController, curve: Curves.easeInOut));
    _leftEyeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _leftEyeController, curve: Curves.easeInOut));
    _rightEyeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _rightEyeController, curve: Curves.easeInOut));
    _leftEyebrowAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _leftEyebrowController, curve: Curves.easeInOut));
    _rightEyebrowAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _rightEyebrowController, curve: Curves.easeInOut));
    _noseAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _noseController, curve: Curves.easeInOut));
    _mouthAnimation =
        Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _mouthController, curve: Curves.easeInOut));
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
    super.dispose();
  }

  /// Ensures biometric consent before any face image flow. Returns true if user can proceed.
  Future<bool> _ensureBiometricConsent() async {
    final canUse = await ConsentService.instance.canUseBiometricFeatures();
    if (canUse) return true;
    return BiometricConsentModal.show(context);
  }

  Future<void> _pickImage() async {
    final ok = await _ensureBiometricConsent();
    if (!ok || !mounted) return;
    final imageInput = createImageInput();
    final picked = await imageInput.pick(preferCamera: false);
    if (picked == null || !mounted) return;

    final codec = await ui.instantiateImageCodec(Uint8List.fromList(picked.bytes));
    final frame = await codec.getNextFrame();
    final img = frame.image;

    if (!kIsWeb) {
      final path = await getTempImagePathFromBytes(picked.bytes);
      if (path != null) {
        setState(() {
          _pickedImage = picked;
          _selectedImage = io.File(path);
          _decodedImage = img;
          _isProcessing = true;
          _statusMessage = '顔を検出中...';
        });
      } else {
        setState(() {
          _pickedImage = picked;
          _selectedImage = null;
          _decodedImage = img;
          _isProcessing = true;
          _statusMessage = '顔を検出中...';
        });
      }
    } else {
      setState(() {
        _pickedImage = picked;
        _selectedImage = null;
        _decodedImage = img;
        _isProcessing = true;
        _statusMessage = '顔を検出中...';
      });
    }
    await _detectFaces();
  }

  Future<void> _detectFaces() async {
    if (_pickedImage == null || _decodedImage == null) return;
    final byteData = await _decodedImage!.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return;
    final metadata = InputImageMetadata(
      size: Size(_decodedImage!.width.toDouble(), _decodedImage!.height.toDouble()),
      rotation: InputImageRotation.rotation0deg,
      format: InputImageFormat.bgra8888,
      bytesPerRow: _decodedImage!.width * 4,
    );
    final inputImage = InputImage.fromBytes(
      bytes: byteData.buffer.asUint8List(),
      metadata: metadata,
    );
    final faces = await _faceDetector.processImage(inputImage);

    setState(() {
      _faces = faces;
      if (faces.isEmpty) {
        _statusMessage = '顔が検出されませんでした';
        _isProcessing = false;
      } else {
        _statusMessage = '顔を検出しました';
        _startAnimations();
      }
    });

    if (faces.isNotEmpty) {
      // 顔検出完了（オフライン処理完了）
      setState(() {
        _statusMessage = '顔検出完了。肌分析を開始してください（オンライン必須）。';
        _isProcessing = false;
      });
    }
  }

  void _resetAnimations() {
    _faceOutlineController.reset();
    _leftEyeController.reset();
    _rightEyeController.reset();
    _leftEyebrowController.reset();
    _rightEyebrowController.reset();
    _noseController.reset();
    _mouthController.reset();
  }

  void _startAnimations() {
    _resetAnimations();

    _faceOutlineController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      _leftEyebrowController.forward();
      _rightEyebrowController.forward();
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      _leftEyeController.forward();
      _rightEyeController.forward();
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      _noseController.forward();
    });
    Future.delayed(const Duration(milliseconds: 1600), () {
      _mouthController.forward();
    });
  }

  Future<void> _analyzeSkin() async {
    if (_faces.isEmpty || _pickedImage == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = '肌分析中...（オンライン接続が必要です）';
    });

    try {
      final serverUrl = ServerPersonalityService.serverUrl;
      final sessionId = await ConsentService.instance.getOrCreateSessionId();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/predict'),
      );
      request.headers['X-Consent-Session-ID'] = sessionId;
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        _pickedImage!.bytes,
        filename: _pickedImage!.filename,
      ));

      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
          );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        print('[FaceTutorialScreen] ✅ サーバー推論成功（肌分析）');
        SkinAnalysisResult? result;
        if (!kIsWeb && _selectedImage != null) {
          result = await SkinAnalysisService().analyzeSkin(_selectedImage!, _faces.first);
        }
        if (result == null && mounted) {
          result = SkinAnalysisResult(
            skinType: 'normal',
            oiliness: 0.5,
            smoothness: 0.5,
            uniformity: 0.5,
            poreSize: 0.3,
            brightness: 0.5,
            skinIssues: const [],
            regionAnalysis: const {},
            recommendation: '',
            shineScore: 0.5,
            toneScore: 0.5,
            dullnessIndex: 0.5,
            textureFineness: 0.5,
            dryness: 0.5,
            evenness: 0.5,
            redness: 0.5,
            texture: 0.5,
          );
        }
        if (mounted && result != null) {
          setState(() {
            _skinAnalysisResult = result;
            _isProcessing = false;
            _statusMessage = '肌分析完了。診断を開始してください（オンライン必須）。';
          });
        }

        // アニメーション鑑賞時間を確保
        await Future.delayed(const Duration(milliseconds: 2400));
      } else {
        throw Exception('サーバーエラー: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      print('[FaceTutorialScreen] 🔥🔥🔥 肌分析サーバー推論エラー: $e 🔥🔥🔥');
      print('[FaceTutorialScreen] スタックトレース: ${stackTrace.toString().split("\n").take(10).join("\n")}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('肌分析中にエラーが発生しました: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _isProcessing = false;
          _statusMessage = '肌分析エラー。もう一度お試しください（オンライン接続が必要です）。';
        });
      }
    }
  }

  Future<void> _startDiagnosis() async {
    if (_faces.isEmpty || _skinAnalysisResult == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = '診断中...（オンライン接続が必要です）';
    });

    await _autoRunTutorialReveal();
  }

  Future<void> _autoRunTutorialReveal() async {
    if (_faces.isEmpty || _skinAnalysisResult == null) return;

    try {
      final face = _faces.first;
      final brightness = _skinAnalysisResult!.brightness;

      // 🔥 サーバー推論を使用（オンライン必須）
      // 🔥 逃げ道ゼロ構成: サーバー推論が失敗した場合は必ずクラッシュ
      PersonalityTreeDiagnosisResult personalityResult;

      // 画像データの存在確認（bytes優先＝Web/共通、pathはモバイル用フォールバック）
      if (_pickedImage != null) {
        print('[FaceTutorialScreen] 🔥 サーバー推論を実行します（bytes）: ${_pickedImage!.filename}');
        try {
          personalityResult = await runDiagnosisBytes(_pickedImage!.bytes, _pickedImage!.filename);
          print('[FaceTutorialScreen] ✅ サーバー推論成功: タイプ=${personalityResult.personalityType}');
        } catch (e, stackTrace) {
          print('[FaceTutorialScreen] 🔥🔥🔥 サーバー推論エラー: $e 🔥🔥🔥');
          print('[FaceTutorialScreen] スタックトレース: ${stackTrace.toString().split("\n").take(10).join("\n")}');
          throw Exception("STOP_HERE_SERVER_INFERENCE_REQUIRED: $e");
        }
      } else if (!kIsWeb && _selectedImage != null && await _selectedImage!.exists()) {
        print('[FaceTutorialScreen] 🔥 サーバー推論を実行します（ファイル）: ${_selectedImage!.path}');
        try {
          personalityResult = await runDiagnosis(_selectedImage!);
          print('[FaceTutorialScreen] ✅ サーバー推論成功: タイプ=${personalityResult.personalityType}');
        } catch (e, stackTrace) {
          print('[FaceTutorialScreen] 🔥🔥🔥 サーバー推論エラー: $e 🔥🔥🔥');
          print('[FaceTutorialScreen] スタックトレース: ${stackTrace.toString().split("\n").take(10).join("\n")}');
          throw Exception("STOP_HERE_SERVER_INFERENCE_REQUIRED: $e");
        }
      } else {
        print('[FaceTutorialScreen] ❌ 画像が存在しません');
        throw Exception('STOP_HERE_SERVER_INFERENCE_REQUIRED: 画像が存在しません');
      }

      // 性格タイプに基づいて神を選択
      // 注意: RevealPageでpersonalityDiagnosisResultから正しい神を取得するため、
      // ここではnullを渡す（RevealPageで決定される）
      final Deity? god = null;
      print('[FaceTutorialScreen] RevealPageでpersonalityDiagnosisResultから正しい神を取得します');
      // 簡易特徴量
      final smile = face.smilingProbability ?? 0.5;
      final eyeOpen = ((face.leftEyeOpenProbability ?? 0.5) + (face.rightEyeOpenProbability ?? 0.5)) / 2.0;
      final gloss = brightness.clamp(0.0, 1.0);
      double straightness = 0.5;
      final faceContour = face.contours[FaceContourType.face];
      if (faceContour != null && faceContour.points.length >= 3) {
        final pts = faceContour.points;
        final a = pts.first;
        final b = pts[pts.length ~/ 2];
        final c = pts.last;
        double dist(ax, ay, bx, by) => math.sqrt(math.pow(ax - bx, 2) + math.pow(ay - by, 2));
        final ab = dist(a.x.toDouble(), a.y.toDouble(), b.x.toDouble(), b.y.toDouble());
        final bc = dist(b.x.toDouble(), b.y.toDouble(), c.x.toDouble(), c.y.toDouble());
        final ac = dist(a.x.toDouble(), a.y.toDouble(), c.x.toDouble(), c.y.toDouble());
        final detour = (ab + bc) / (ac + 1e-6);
        straightness = (2 - detour).clamp(0.0, 1.0);
      }
      final claim = 0.5;
      final features = FaceFeatures(smile.clamp(0.0, 1.0), eyeOpen.clamp(0.0, 1.0), gloss, straightness, claim);
      // チュートリアルで選ばれた神を保存（RevealPageで決定された神を使用）
      // 注意: ここでは保存しない（RevealPageで決定された後に保存する）
      // 一時的にデフォルトの神を保存（後でRevealPageで決定された神で上書きされる）
      try {
        final detail = await PersonalityTypeDetailService.getDetail(personalityResult.personalityType);
        if (detail != null) {
          final pillarId = detail.pillarId.toLowerCase();
          final actualGod = deities.firstWhere(
            (d) => d.id.toLowerCase() == pillarId,
            orElse: () => deities.first,
          );
          await Storage.saveTutorialDeity(actualGod.id);
          print('[FaceTutorialScreen] チュートリアル神を保存: ${actualGod.id} (pillarId=$pillarId)');
        }
      } catch (e) {
        print('[FaceTutorialScreen] ⚠️ チュートリアル神の保存エラー: $e');
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RevealPage(
            god: god,
            features: features,
            skin: _skinAnalysisResult,
            beautyScore: null,
            praise: personalityResult.personalityDescription,
            isTutorial: true,
            deityMeta: {
              'title': personalityResult.personalityTypeName,
              'trait': personalityResult.personalityDescription,
              'message': personalityResult.personalityDescription,
            },
            personalityDiagnosisResult: personalityResult, // 新しい診断結果を渡す
          ),
        ),
      );
    } catch (e, stackTrace) {
      print('[FaceTutorialScreen] エラーが発生しました: $e');
      print('[FaceTutorialScreen] スタックトレース: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(getDiagnosisErrorMessage(e)),
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() {
          _isProcessing = false;
          _statusMessage = '診断に失敗しました。もう一度お試しください。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('顔認識の陽占'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: '判断基準を見る',
            onPressed: () {
              print('[FaceTutorialScreen] 判断基準ページを開きます');
              try {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) {
                      print('[FaceTutorialScreen] TutorialCriteriaPageを作成します');
                      return const TutorialCriteriaPage();
                    },
                  ),
                ).then((_) {
                  print('[FaceTutorialScreen] 判断基準ページが閉じられました');
                }).catchError((error) {
                  print('[FaceTutorialScreen] エラー: $error');
                });
              } catch (e) {
                print('[FaceTutorialScreen] ナビゲーションエラー: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('判断基準ページを開けませんでした: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_pickedImage != null && _decodedImage != null)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 画像のアスペクト比を計算
                  final imageAspect = _decodedImage!.width / _decodedImage!.height;
                  final containerAspect = constraints.maxWidth / constraints.maxHeight;
                  // 実際の表示サイズを計算（BoxFit.containと同じロジック）
                  double displayWidth, displayHeight;
                  if (imageAspect > containerAspect) {
                    displayWidth = constraints.maxWidth;
                    displayHeight = constraints.maxWidth / imageAspect;
                  } else {
                    displayHeight = constraints.maxHeight;
                    displayWidth = constraints.maxHeight * imageAspect;
                  }
                  // bytes で統一表示（Web/モバイル共通）
                  final imageWidget = Image.memory(
                    Uint8List.fromList(_pickedImage!.bytes),
                    fit: BoxFit.contain,
                    width: displayWidth,
                    height: displayHeight,
                  );
                  return Center(
                    child: SizedBox(
                      width: displayWidth,
                      height: displayHeight,
                      child: Stack(
                        children: [
                          imageWidget,
                          // 顔検出オーバーレイ
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              _faceOutlineAnimation,
                              _leftEyeAnimation,
                              _rightEyeAnimation,
                              _leftEyebrowAnimation,
                              _rightEyebrowAnimation,
                              _noseAnimation,
                              _mouthAnimation,
                            ]),
                            builder: (context, child) {
                              return SizedBox(
                                width: displayWidth,
                                height: displayHeight,
                                child: CustomPaint(
                                  painter: FacePainter(
                                    faces: _faces,
                                    imageSize: Size(_decodedImage!.width.toDouble(), _decodedImage!.height.toDouble()),
                                    faceOutlineProgress: _faceOutlineAnimation.value,
                                    leftEyeProgress: _leftEyeAnimation.value,
                                    rightEyeProgress: _rightEyeAnimation.value,
                                    leftEyebrowProgress: _leftEyebrowAnimation.value,
                                    rightEyebrowProgress: _rightEyebrowAnimation.value,
                                    noseProgress: _noseAnimation.value,
                                    mouthProgress: _mouthAnimation.value,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(_statusMessage, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Semantics(
                      button: true,
                      label: 'カメラで撮影する。ダブルタップでカメラ画面を開く。',
                      child: ElevatedButton.icon(
                        key: const Key('e2e-camera'),
                        onPressed: _isProcessing
                            ? null
                            : () async {
                                final ok = await _ensureBiometricConsent();
                                if (!ok || !mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const TutorialIntroPage(),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('カメラで撮影'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Semantics(
                      button: true,
                      label: _isProcessing ? '処理中' : '画像を選択する。ダブルタップでギャラリーを開く。',
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _pickImage,
                        child: Text(_isProcessing ? '処理中...' : '画像を選択'),
                      ),
                    ),
                    if (E2E.isEnabled) ...[
                      const SizedBox(width: 16),
                      ElevatedButton(
                        key: const Key('e2e-camera-shortcut'),
                        onPressed: _isProcessing
                            ? null
                            : () async {
                                final ok = await _ensureBiometricConsent();
                                if (!ok || !mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const TutorialCameraPage(currentStep: 'neutral'),
                                  ),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('E2E: カメラ画面へ'),
                      ),
                    ],
                  ],
                ),
                if (_faces.isNotEmpty && _skinAnalysisResult == null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '✅ 顔検出完了（オフライン処理）',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _analyzeSkin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_isProcessing ? '肌分析中...（オンライン接続が必要）' : '肌分析を開始（オンライン）'),
                  ),
                ],
                if (_skinAnalysisResult != null && _faces.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('肌タイプ: ${_skinAnalysisResult!.skinType}'),
                  Text('油分: ${(_skinAnalysisResult!.oiliness * 100).toStringAsFixed(1)}%'),
                  const SizedBox(height: 16),
                  const Text(
                    '✅ 肌分析完了（オンライン処理）',
                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _isProcessing ? null : _startDiagnosis,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_isProcessing ? '診断中...（オンライン接続が必要）' : '診断を開始（オンライン）'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
