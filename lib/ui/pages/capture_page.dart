import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kami_face_oracle/utils/preview_transform.dart';
import 'package:kami_face_oracle/widgets/face_overlay_painter.dart';
import 'package:kami_face_oracle/feature/tutorial/device_pose_gate.dart';
import 'package:kami_face_oracle/feature/tutorial/tutorial_guidance_overlay.dart';
import 'package:kami_face_oracle/core/scoring.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/ui/pages/result_page.dart';
import 'package:kami_face_oracle/ui/pages/reveal_page.dart';
import 'package:kami_face_oracle/ui/pages/radar_chart_page.dart';
import 'package:kami_face_oracle/skin_analysis.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:intl/intl.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/skin_analysis_ai_service.dart';
import 'package:image/image.dart' as img;
import 'package:kami_face_oracle/core/file_access_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier_fixed.dart';
import 'package:kami_face_oracle/core/image_normalizer.dart';
import 'package:kami_face_oracle/services/server_personality_service.dart';
import 'package:kami_face_oracle/inference/diagnosis_entry.dart';
import 'package:kami_face_oracle/features/skin_progress/utils/skin_result_converter.dart';
import 'package:kami_face_oracle/features/skin_progress/data/skin_record_repository.dart';
import 'package:kami_face_oracle/features/skin_progress/data/skin_record_repository_hive.dart';
import 'package:kami_face_oracle/services/skin_analysis_service.dart';
import 'package:kami_face_oracle/utils/temp_file_helper.dart';
import 'package:kami_face_oracle/utils/diagnosis_error_message.dart';
import 'package:hive/hive.dart';

class CapturePage extends StatefulWidget {
  final String? initialImagePath;
  final bool autoMode;

  const CapturePage({super.key, this.initialImagePath, this.autoMode = false});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> with WidgetsBindingObserver {
  bool _busy = false;
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  late final FaceDetector _faceDetector;
  late final DevicePoseGate _poseGate;

  // 自動シャッター機能用の状態変数
  bool _streaming = false;
  bool _detecting = false;
  List<Face> _faces = [];
  Size? _lastImageSize;
  String _guidanceTitle = '椅子に座り、スマホを目の高さで正面に構えてください';
  String? _guidanceSub;
  bool _isReadyToCapture = false;
  bool _shouldShowGuidance = true;
  int _stableFrameCount = 0;
  static const int _requiredStableFrames = 5;
  final bool _debug = true;

  @override
  void initState() {
    super.initState();

    print('[AUTO_MODE] CapturePage.initState autoMode=${widget.autoMode} initialImagePath=${widget.initialImagePath}');

    if (widget.autoMode && widget.initialImagePath != null) {
      // フレーム描画後にロードを開始することで、
      // build が一度必ず走ったあとに診断処理を開始できる。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadAutoModeImage(widget.initialImagePath!);
      });
    } else if (widget.autoMode) {
      print('[AUTO_MODE] CapturePage.initState: autoMode=true but initialImagePath is null');
      print('[AUTO_MODE] status=fail reason=no_initial_path');
      if (!mounted) return;
      setState(() => _busy = false);
    } else {
      // カメラを初期化（自動モードでない場合のみ）
      WidgetsBinding.instance.addObserver(this);

      // 画面の向きを縦向きに固定
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      // DevicePoseGateを初期化
      _poseGate = DevicePoseGate(
        gyroStillThreshold: 0.30,
        gyroStableRequiredFrames: 3,
        pitchThresholdDeg: 20.0,
        rollThresholdDeg: 20.0,
      );
      _poseGate.start();

      // FaceDetectorを初期化
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableClassification: true,
          enableContours: true,
          enableLandmarks: true,
          minFaceSize: 0.1,
        ),
      );

      // フレーム描画後に初期化を実行（tutorial_camera_page.dartと同じパターン）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeCamera();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poseGate.stop();
    _stopStream();
    _cameraController?.dispose();
    _faceDetector.close();
    // 画面の向きの固定を解除
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopStream();
      _cameraController?.dispose();
      _cameraController = null;
      _isCameraInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      debugPrint('[CapturePage] 📷 カメラ初期化開始');
      final cameras = await availableCameras();
      debugPrint('[CapturePage] 利用可能なカメラ数: ${cameras.length}');

      if (cameras.isEmpty) {
        throw Exception('カメラが見つかりません');
      }

      // フロントカメラを探す（tutorial_camera_page.dartと同じロジック）
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      debugPrint('[CapturePage] 選択したカメラ: ${frontCamera.name}, lensDirection=${frontCamera.lensDirection}');

      // Web では低解像度で初期化を試行（成功率向上）
      final resolution = kIsWeb ? ResolutionPreset.low : ResolutionPreset.medium;
      final controller = CameraController(
        frontCamera,
        resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      debugPrint('[CapturePage] CameraController作成完了、初期化中...');

      await controller.initialize();

      _cameraController = controller;

      debugPrint('[CapturePage] ✅ カメラ初期化成功: previewSize=${controller.value.previewSize}');

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        debugPrint('[CapturePage] ✅ カメラ状態を更新: _isCameraInitialized=true');
        _startStream();
      }
    } catch (e, stackTrace) {
      debugPrint('[CapturePage] ❌ カメラ初期化エラー: $e');
      debugPrint('[CapturePage] スタックトレース: ${stackTrace.toString().split("\n").take(10).join("\n")}');

      _cameraController?.dispose();
      _cameraController = null;

      if (mounted) {
        final message = kIsWeb ? 'カメラの初期化に失敗しました。Webでは「画像をアップロード」をご利用ください。' : 'カメラの初期化に失敗しました: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 6),
          ),
        );
        setState(() {
          _isCameraInitialized = false;
        });
      }
    }
  }

  // ImageStreamを開始（リアルタイム顔検出用）
  Future<void> _startStream() async {
    final c = _cameraController;
    if (c == null || !_isCameraInitialized) return;

    // 2回目の診断時にストリームが既に開始されている場合は停止
    if (_streaming) {
      await _stopStream();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _streaming = true;

    debugPrint('[CapturePage] startImageStream called');
    try {
      await c.startImageStream((image) async {
        if (!_streaming || _detecting || _isCapturing || _busy) return;
        _detecting = true;

        try {
          final input = _toInputImage(image, c.description.sensorOrientation);
          _lastImageSize = input.metadata?.size;

          final faces = await _faceDetector.processImage(input);
          debugPrint('[CapturePage] ✅ faces=${faces.length}');

          _faces = faces;

          // 自動シャッター条件を更新
          _updateAutoCaptureByState(faces);

          if (mounted) setState(() {});
        } catch (e, stackTrace) {
          debugPrint('[CapturePage] ❌ process failed: $e');
          debugPrint('[CapturePage] StackTrace: ${stackTrace.toString().split("\n").take(3).join("\n")}');
          _faces = [];
          if (mounted) setState(() {});
        } finally {
          _detecting = false;
        }
      });
    } catch (e) {
      debugPrint('[CapturePage] ❌ startImageStream failed: $e');
      _streaming = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('カメラストリームの開始に失敗しました: $e')),
        );
      }
    }
  }

  Future<void> _stopStream() async {
    final c = _cameraController;
    _streaming = false;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) {
        await c.stopImageStream();
        debugPrint('[CapturePage] stopImageStream ok');
      }
    } catch (e) {
      debugPrint('[CapturePage] stopImageStream failed: $e');
    }
  }

  InputImageRotation _rotationFromSensorOrientation(int sensorOrientation, {CameraLensDirection? lensDirection}) {
    final isFrontCamera = lensDirection == CameraLensDirection.front ||
        _cameraController?.description.lensDirection == CameraLensDirection.front;

    if (isFrontCamera) {
      switch (sensorOrientation) {
        case 90:
          return InputImageRotation.rotation90deg;
        case 180:
          return InputImageRotation.rotation180deg;
        case 270:
          return InputImageRotation.rotation270deg;
        case 0:
        default:
          return InputImageRotation.rotation0deg;
      }
    }

    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      case 0:
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  InputImage _toInputImage(CameraImage image, int sensorOrientation) {
    final lensDirection = _cameraController?.description.lensDirection;
    final rotation = _rotationFromSensorOrientation(sensorOrientation, lensDirection: lensDirection);
    final imageWidth = image.width;
    final imageHeight = image.height;

    debugPrint(
        '[CapturePage] image format: ${image.format.group}, planes: ${image.planes.length}, size: ${image.width}x${image.height}');

    // Android: NV21形式を組み立て
    if (image.format.group == ImageFormatGroup.nv21 && image.planes.length >= 2) {
      final yPlane = image.planes[0];
      final uvPlane = image.planes[1];

      final bytes = Uint8List(yPlane.bytes.length + uvPlane.bytes.length);
      bytes.setRange(0, yPlane.bytes.length, yPlane.bytes);
      bytes.setRange(yPlane.bytes.length, bytes.length, uvPlane.bytes);

      final metadata = InputImageMetadata(
        size: Size(imageWidth.toDouble(), imageHeight.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: imageWidth,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    }

    // iOS: BGRA8888
    if (image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes.first;
      final metadata = InputImageMetadata(
        size: Size(imageWidth.toDouble(), imageHeight.toDouble()),
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      );
      return InputImage.fromBytes(bytes: plane.bytes, metadata: metadata);
    }

    // YUV420形式の場合（3プレーン: Y, U, V → NV21形式に変換）
    if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length >= 3) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final ySize = imageWidth * imageHeight;
      final uvSize = (imageWidth * imageHeight) ~/ 2;

      final bytes = Uint8List(ySize + uvSize);

      // Y平面をコピー（パディングを除去）
      final yBytesPerRow = yPlane.bytesPerRow;
      for (int y = 0; y < imageHeight; y++) {
        final srcOffset = y * yBytesPerRow;
        final dstOffset = y * imageWidth;
        bytes.setRange(dstOffset, dstOffset + imageWidth, yPlane.bytes, srcOffset);
      }

      // UとVをインタリーブしてUV平面を作成
      final uvWidth = imageWidth ~/ 2;
      final uvHeight = imageHeight ~/ 2;
      final uBytesPerRow = uPlane.bytesPerRow;
      final vBytesPerRow = vPlane.bytesPerRow;

      for (int y = 0; y < uvHeight; y++) {
        for (int x = 0; x < uvWidth; x++) {
          final uIndex = y * uBytesPerRow + x;
          final vIndex = y * vBytesPerRow + x;
          final uvIndex = y * uvWidth * 2 + x * 2;

          if (uIndex < uPlane.bytes.length && vIndex < vPlane.bytes.length && uvIndex + 1 < bytes.length) {
            bytes[ySize + uvIndex] = vPlane.bytes[vIndex];
            bytes[ySize + uvIndex + 1] = uPlane.bytes[uIndex];
          }
        }
      }

      final metadata = InputImageMetadata(
        size: Size(imageWidth.toDouble(), imageHeight.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: imageWidth,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    }

    // フォールバック
    debugPrint('[CapturePage] ⚠️ Unknown format, using first plane as fallback');
    final bytes = image.planes.first.bytes;
    final metadata = InputImageMetadata(
      size: Size(imageWidth.toDouble(), imageHeight.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: image.planes.first.bytesPerRow,
    );
    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  // 自動シャッター条件を更新
  void _updateAutoCaptureByState(List<Face> faces) {
    _guidanceTitle = '椅子に座り、スマホを目の高さで正面に構えてください';

    // Web ではジャイロ/加速度が取れず pitch/roll が 999 のままになるため、ポーズゲートをスキップ
    if (!kIsWeb) {
      if (!_poseGate.deviceIsVertical) {
        final pitch = _poseGate.pitchDeg;
        final roll = _poseGate.rollDeg;
        final pitchAbs = pitch.abs();
        final rollAbs = roll.abs();
        debugPrint(
            '[POSE] pitch=${pitch.toStringAsFixed(1)}° roll=${roll.toStringAsFixed(1)}° vertical=${_poseGate.deviceIsVertical}');
        if (rollAbs > pitchAbs && rollAbs > 5) {
          final rollAngle = rollAbs.toStringAsFixed(1);
          _guidanceSub = roll < 0 ? 'スマホを左に少し傾けてください（右に${rollAngle}°傾いています）' : 'スマホを右に少し傾けてください（左に${rollAngle}°傾いています）';
        } else if (pitchAbs > 5) {
          final pitchAngle = pitchAbs.toStringAsFixed(1);
          _guidanceSub =
              pitch > 0 ? 'スマホを下に向けてください（上向きに${pitchAngle}°傾いています）' : 'スマホを上に向けてください（下向きに${pitchAngle}°傾いています）';
        } else {
          _guidanceSub = 'スマホを縦向きに、画面が正面を向くようにしてください';
        }
        _shouldShowGuidance = true;
        _markNotReady();
        return;
      }
      if (!_poseGate.deviceIsStill) {
        _guidanceSub = 'スマホを動かさずに固定してください';
        _shouldShowGuidance = true;
        _markNotReady();
        return;
      }
    }

    if (faces.length != 1) {
      _guidanceSub = faces.isEmpty ? '顔が検出できません。明るい場所で正面を向いてください' : '顔が1人だけ映るようにしてください';
      _shouldShowGuidance = true;
      _markNotReady();
      return;
    }

    final face = faces.first;
    final faceScore = _calculateFaceScore(face);
    debugPrint('[FACE] faceScore=$faceScore');

    if (faceScore < 2.5) {
      final issue = _getFaceOrientationIssue(face);
      if (issue != null) {
        _guidanceSub = issue;
      } else {
        _guidanceSub = '顔を正面に向けて、カメラをまっすぐ見てください';
      }
      _shouldShowGuidance = true;
      _markNotReady();
      return;
    }

    if (!_eyesOpen(face)) {
      _guidanceSub = '目をしっかり開けて、カメラのレンズを見てください';
      _shouldShowGuidance = true;
      _markNotReady();
      return;
    }

    // ✅ 全条件OK
    _guidanceSub = null;
    _shouldShowGuidance = false;

    _stableFrameCount++;
    _stableFrameCount = _stableFrameCount.clamp(0, _requiredStableFrames);
    _isReadyToCapture = _stableFrameCount >= _requiredStableFrames;

    debugPrint('[AUTO_SHOT] stable=$_stableFrameCount/$_requiredStableFrames (増加)');

    if (_isReadyToCapture) {
      _triggerAutoShutter();
    }
  }

  void _markNotReady() {
    _stableFrameCount = (_stableFrameCount - 1).clamp(0, _requiredStableFrames);
    _isReadyToCapture = false;
    debugPrint('[AUTO_SHOT] stable=$_stableFrameCount/$_requiredStableFrames (減少)');
  }

  Future<void> _triggerAutoShutter() async {
    if (_isCapturing) return;

    _isCapturing = true;
    _stableFrameCount = 0;

    final c = _cameraController;
    if (c == null) {
      _isCapturing = false;
      return;
    }

    try {
      debugPrint('[AUTO_SHOT] FIRE');
      await _stopStream();
      final xFile = await c.takePicture();
      if (kIsWeb) {
        final bytes = await xFile.readAsBytes();
        final filename = xFile.name ?? 'capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _processBytes(bytes, filename);
      } else {
        await _processPath(xFile.path);
      }
      await _startStream();
    } catch (e) {
      debugPrint('[AUTO_SHOT] capture failed: $e');
      _guidanceSub = '撮影に失敗しました。もう一度お試しください';
      await _startStream();
    } finally {
      _isCapturing = false;
      if (mounted) setState(() {});
    }
  }

  /// Web／bytes 用: 自動シャッター後の処理（パスを使わない）
  Future<void> _processBytes(Uint8List bytes, String filename) async {
    if (_busy) {
      if (mounted) setState(() => _busy = false);
      await Future.delayed(const Duration(milliseconds: 100));
    }
    setState(() => _busy = true);
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) throw Exception('画像のバイトデータ変換に失敗しました');
      final inputImage = InputImage.fromBytes(
        bytes: byteData.buffer.asUint8List(),
        metadata: InputImageMetadata(
          size: Size(uiImage.width.toDouble(), uiImage.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: uiImage.width * 4,
        ),
      );
      uiImage.dispose();
      final accurateDetector = _createFaceDetector();
      final faces = await accurateDetector.processImage(inputImage);
      await accurateDetector.close();
      if (!mounted) {
        setState(() => _busy = false);
        return;
      }
      if (faces.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('顔が検出できませんでした。\n\n画像に顔が写っていることを確認してください。'), duration: Duration(seconds: 5)),
        );
        setState(() => _busy = false);
        return;
      }
      final face = faces.first;
      final feat = FaceFeatures(
        face.smilingProbability ?? 0.5,
        ((face.leftEyeOpenProbability ?? 0.5) + (face.rightEyeOpenProbability ?? 0.5)) / 2.0,
        0.5,
        0.5,
        0.5,
      );
      final personalityResult = await runDiagnosisBytes(bytes, filename);
      SkinAnalysisResult skin;
      if (kIsWeb) {
        skin = SkinAnalysisResult(
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
      } else {
        final path = await getTempImagePathFromBytes(bytes);
        if (path != null) {
          skin = await SkinAnalysisService().analyzeSkin(io.File(path), face);
        } else {
          skin = SkinAnalysisResult(
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
      }
      final glossAdj = () {
        final b = skin.brightness.clamp(0.0, 1.0);
        final dull = (skin.dullnessIndex ?? (1.0 - b)).clamp(0.0, 1.0);
        final spot = (skin.spotDensity ?? 0.0).clamp(0.0, 1.0);
        final acne = (skin.acneActivity ?? 0.0).clamp(0.0, 1.0);
        final penalty = (0.35 * dull + 0.25 * spot + 0.2 * acne).clamp(0.0, 1.0);
        final base = 0.6 * b + 0.4 * (1.0 - dull);
        return (base * (1.0 - penalty)).clamp(0.0, 1.0);
      }();
      final enriched = FaceFeatures(feat.smile, feat.eyeOpen, glossAdj, feat.straightness, feat.claim);
      SkinAnalysisResult? baselineSkin;
      SkinAnalysisResult? previousSkin;
      if (!kIsWeb) {
        try {
          final bMap = await Storage.getBaselineSkin();
          if (bMap != null) {
            baselineSkin = SkinAnalysisResult(
              skinType: 'baseline',
              oiliness: (bMap['oiliness'] ?? 0.5).toDouble(),
              smoothness: (bMap['smoothness'] ?? 0.5).toDouble(),
              uniformity: (bMap['uniformity'] ?? 0.5).toDouble(),
              poreSize: (bMap['poreSize'] ?? 0.3).toDouble(),
              brightness: (bMap['brightness'] ?? 0.7).toDouble(),
              skinIssues: const [],
              regionAnalysis: const {},
              recommendation: '',
              dullnessIndex: (bMap['dullnessIndex'] ?? 0.0).toDouble(),
              spotDensity: (bMap['spotDensity'] ?? 0.0).toDouble(),
              acneActivity: (bMap['acneActivity'] ?? 0.0).toDouble(),
              wrinkleDensity: (bMap['wrinkleDensity'] ?? 0.0).toDouble(),
            );
          }
          final pMap = await Storage.getLastSkin();
          if (pMap != null) {
            previousSkin = SkinAnalysisResult(
              skinType: 'previous',
              oiliness: (pMap['oiliness'] ?? 0.5).toDouble(),
              smoothness: (pMap['smoothness'] ?? 0.5).toDouble(),
              uniformity: (pMap['uniformity'] ?? 0.5).toDouble(),
              poreSize: (pMap['poreSize'] ?? 0.3).toDouble(),
              brightness: (pMap['brightness'] ?? 0.7).toDouble(),
              skinIssues: const [],
              regionAnalysis: const {},
              recommendation: '',
              dullnessIndex: (pMap['dullnessIndex'] ?? 0.0).toDouble(),
              spotDensity: (pMap['spotDensity'] ?? 0.0).toDouble(),
              acneActivity: (pMap['acneActivity'] ?? 0.0).toDouble(),
              wrinkleDensity: (pMap['wrinkleDensity'] ?? 0.0).toDouble(),
            );
          }
        } catch (_) {}
      }
      final delta = SkinAnalyzerDelta.computeDelta(baseline: baselineSkin, previous: previousSkin, current: skin);
      final skinPenalty =
          [delta.dullnessDelta, delta.spotDelta, delta.acneDelta].where((v) => v > 0).fold<double>(0, (p, v) => p + v) /
              3.0;
      final Deity? god = null; // RevealPage で personalityDiagnosisResult から取得
      double eyeBrightness = 0.6;
      try {
        final decodedImage = img.decodeImage(Uint8List.fromList(bytes));
        if (decodedImage != null) {
          final leftEyePts = face.contours[FaceContourType.leftEye]?.points ?? [];
          final rightEyePts = face.contours[FaceContourType.rightEye]?.points ?? [];
          if (leftEyePts.isNotEmpty && rightEyePts.isNotEmpty) {
            final faceRect = face.boundingBox;
            final imageWidth = decodedImage.width.toDouble();
            final imageHeight = decodedImage.height.toDouble();
            double totalBrightness = 0.0;
            int sampleCount = 0;
            for (final eyeCenter in [
              Offset(leftEyePts.map((p) => p.x.toDouble()).reduce((a, b) => a + b) / leftEyePts.length,
                  leftEyePts.map((p) => p.y.toDouble()).reduce((a, b) => a + b) / leftEyePts.length),
              Offset(rightEyePts.map((p) => p.x.toDouble()).reduce((a, b) => a + b) / rightEyePts.length,
                  rightEyePts.map((p) => p.y.toDouble()).reduce((a, b) => a + b) / rightEyePts.length),
            ]) {
              final eyeX = eyeCenter.dx.clamp(faceRect.left, faceRect.right);
              final eyeY = eyeCenter.dy.clamp(faceRect.top, faceRect.bottom);
              final eyeW = 40.0;
              final eyeH = 25.0;
              final x0 = (eyeX - eyeW / 2).clamp(0.0, imageWidth - 1).toInt();
              final y0 = (eyeY - eyeH / 2).clamp(0.0, imageHeight - 1).toInt();
              final w = (eyeW.clamp(1.0, imageWidth - x0)).toInt();
              final h = (eyeH.clamp(1.0, imageHeight - y0)).toInt();
              if (w > 0 && h > 0 && x0 >= 0 && y0 >= 0) {
                try {
                  final eyeRegion = img.copyCrop(decodedImage, x: x0, y: y0, width: w, height: h);
                  final regionBytes = eyeRegion.getBytes();
                  double sumLuma = 0.0;
                  int pixelCount = 0;
                  for (int i = 0; i < regionBytes.length; i += 4) {
                    if (i + 2 < regionBytes.length) {
                      sumLuma +=
                          (0.299 * regionBytes[i] + 0.587 * regionBytes[i + 1] + 0.114 * regionBytes[i + 2]) / 255.0;
                      pixelCount++;
                    }
                  }
                  if (pixelCount > 0) {
                    totalBrightness += sumLuma / pixelCount;
                    sampleCount++;
                  }
                } catch (_) {}
              }
            }
            if (sampleCount > 0) eyeBrightness = (totalBrightness / sampleCount).clamp(0.0, 1.0);
          }
        }
      } catch (_) {}
      final beauty = computeBeautyLuckScore(
          skin: skin, features: enriched, eyeBrightness: eyeBrightness, puffiness: 1.0 - enriched.straightness);
      final comment = beauty >= 0.75
          ? '目の輝きとツヤが調和。今日は流れが良い日です✨'
          : beauty >= 0.55
              ? '肌の調子は安定。小さなケアでさらに上向きです。'
              : '少し休息を。保湿と眠りで明日を整えましょう。';

      // 保存失敗しても結果画面へ遷移する（実機・WebでStorage/Firebaseが使えない場合がある）
      try {
        await Storage.saveLastSkin(skin.toSimpleMap());
      } catch (e) {
        print('[CapturePage] saveLastSkin skip: $e');
      }
      try {
        final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
        final dailyRecord = SkinResultConverter.convertToDailyRecord(skin, today);
        final box = Hive.box<Map>('skin_daily_records');
        final repo = SkinRecordRepositoryHive(box);
        await repo.upsert(dailyRecord);
      } catch (_) {}
      final now = DateTime.now();
      try {
        await Storage.saveDailySnapshot({
          'date': DateFormat('yyyy-MM-dd').format(now),
          'metrics': {
            'gloss': (skin.brightness * (1 - (skin.dullnessIndex ?? 0))).clamp(0.0, 1.0),
            'symmetry': enriched.straightness,
            'lip_moisture': 1.0 - (skin.acneActivity ?? 0.0),
            'eye_brightness': 0.6,
            'puffiness': 1.0 - enriched.straightness
          },
          'beauty_score': beauty,
          'deity': god?.id ?? deities.first.id,
          'comment': comment,
        });
      } catch (e) {
        print('[CapturePage] saveDailySnapshot skip: $e');
      }
      try {
        await CloudService.saveDailyRecord({
          'date': DateFormat('yyyy-MM-dd').format(now),
          'beauty_score': beauty,
          'deity': god?.id ?? deities.first.id,
          'comment': comment
        });
      } catch (e) {
        print('[CapturePage] saveDailyRecord skip: $e');
      }

      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => RevealPage(
                  god: god,
                  features: enriched,
                  skin: skin,
                  beautyScore: beauty,
                  praise: comment,
                  aiDiagnosisResult: null,
                  personalityDiagnosisResult: personalityResult)));
    } catch (e, stackTrace) {
      print('[CapturePage] _processBytes error: $e');
      print('[CapturePage] ${stackTrace.toString().split("\n").take(8).join("\n")}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(getDiagnosisErrorMessage(e)),
            duration: const Duration(seconds: 6),
          ),
        );
        setState(() => _busy = false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // headEulerAngle が null の場合は「データなし」として満点扱い（Web等で角度が出ない場合に自動シャッターが切れるようにする）
  double _calculateFaceScore(Face f) {
    double score = 0.0;
    void addScore(double? val) {
      if (val == null) {
        score += 1.0;
        return;
      }
      final abs = val.abs();
      if (abs < 8)
        score += 1.0;
      else if (abs < 15) score += 0.5;
    }

    addScore(f.headEulerAngleY);
    addScore(f.headEulerAngleX);
    addScore(f.headEulerAngleZ);
    return score;
  }

  String? _getFaceOrientationIssue(Face f) {
    if (f.headEulerAngleY == null && f.headEulerAngleX == null && f.headEulerAngleZ == null) return null;
    final yaw = (f.headEulerAngleY ?? 0).abs();
    final pitch = (f.headEulerAngleX ?? 0).abs();
    final roll = (f.headEulerAngleZ ?? 0).abs();
    if (yaw > 10) {
      final yawValue = f.headEulerAngleY ?? 0;
      return yawValue > 0 ? '顔を左に向けてください（右を向いています）' : '顔を右に向けてください（左を向いています）';
    } else if (pitch > 10) {
      final pitchValue = f.headEulerAngleX ?? 0;
      return pitchValue > 0 ? '顔を下に向けてください（上を向いています）' : '顔を上に向けてください（下を向いています）';
    } else if (roll > 10) {
      return '顔を正面に向けてください（顔が傾いています）';
    }
    return null;
  }

  bool _eyesOpen(Face f) {
    final l = f.leftEyeOpenProbability ?? 0.0;
    final r = f.rightEyeOpenProbability ?? 0.0;

    debugPrint('[EYES] left=${l.toStringAsFixed(2)} right=${r.toStringAsFixed(2)}');

    if (l == 0.0 && r == 0.0) {
      debugPrint('[EYES] データが取れないため、緩和してtrueを返します');
      return true;
    }
    final result = l >= 0.3 && r >= 0.3;
    debugPrint('[EYES] 判定結果: $result');
    return result;
  }

  Rect _guideRect(Size view) {
    final w = view.width * 0.78;
    final h = view.height * 0.42;
    return Rect.fromLTWH((view.width - w) / 2, (view.height - h) / 2, w, h);
  }

  Future<void> _loadAutoModeImage(String path) async {
    print('[AUTO_MODE] _loadAutoModeImage start path=$path');

    // 既存のリトライロジックを活かしつつ、ログを増やす
    const maxRetry = 10;
    const delayMs = 500;

    for (var i = 0; i < maxRetry; i++) {
      if (!mounted) return;

      final file = io.File(path);
      final exists = await file.exists();

      print('[AUTO_MODE] _loadAutoModeImage retry=$i exists=$exists path=$path');

      if (exists) {
        print('[AUTO_MODE] _loadAutoModeImage file found, calling _processPath');
        try {
          await _processPath(path);
          print('[AUTO_MODE] _loadAutoModeImage _processPath completed');
        } catch (e, stackTrace) {
          print('[AUTO_MODE] _loadAutoModeImage _processPath error: $e');
          print('[AUTO_MODE] _loadAutoModeImage stackTrace: ${stackTrace.toString().split("\n").take(10).join("\n")}');
          if (widget.autoMode) {
            print('[AUTO_MODE] status=fail reason=process_path_error error=$e');
          }
        }
        return;
      }

      await Future.delayed(const Duration(milliseconds: delayMs));
    }

    print('[AUTO_MODE] _loadAutoModeImage file not found after retries: $path');
    print('[AUTO_MODE] status=fail reason=file_not_found path=$path');
    if (!mounted) return;
    setState(() => _busy = false);
  }

  /// FaceDetectorを再生成（画像処理ごとに呼び出す）
  FaceDetector _createFaceDetector() {
    // 新しいFaceDetectorを作成（リアルタイム検出用は既に初期化済み）
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableContours: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    print('[CapturePage] ✅ FaceDetectorを再生成しました（キャッシュをクリア）');
    return detector;
  }

  Future<void> _processPath(String imagePath) async {
    print('[CapturePage] 📁 _processPath開始: path=$imagePath');

    // 2回目の診断時に状態をリセット
    if (_busy) {
      print('[CapturePage] ⚠️ 前回の診断が完了していません。状態をリセットします。');
      if (mounted) {
        setState(() => _busy = false);
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    setState(() => _busy = true);
    // 外部ストレージのファイルパスの場合、一時ディレクトリにコピーしてから処理
    // これにより権限エラーを回避
    String actualPath = imagePath;
    io.File? tempFile;
    try {
      // カメラで撮影したファイル（通常は/data/data/.../cache/...）は直接処理
      // 外部ストレージのパスかどうかを確認
      // アプリの内部ストレージや外部ストレージのアプリ専用ディレクトリも確認
      final isExternalStorage = imagePath.startsWith('/sdcard/') ||
          imagePath.startsWith('/storage/emulated/') ||
          imagePath.startsWith('/storage/self/primary/');

      print('[CapturePage] パス判定: isExternalStorage=$isExternalStorage, path=$imagePath');

      if (isExternalStorage) {
        try {
          print('[CapturePage] 外部ストレージのファイルを処理中: $imagePath');

          // まず、アプリの外部ストレージディレクトリに既にコピーされているファイルを確認
          final filename = imagePath.split('/').last;
          bool foundExistingFile = false;

          try {
            // 方法1: getExternalStorageDirectory()を使用
            final externalDir = await getExternalStorageDirectory();
            if (externalDir != null) {
              final appExternalCacheDir = io.Directory('${externalDir.parent.path}/cache');
              print('[CapturePage] ✅ アプリの外部ストレージキャッシュディレクトリ: ${appExternalCacheDir.path}');

              if (await appExternalCacheDir.exists()) {
                print('[CapturePage] ディレクトリ内のファイルを検索中...');
                try {
                  await for (final entity in appExternalCacheDir.list()) {
                    if (entity is io.File) {
                      final entityName = entity.path.split('/').last;
                      print('[CapturePage]   ファイル確認: $entityName');
                      // ファイル名で完全一致または部分一致をチェック
                      if (entityName.contains(filename) || filename.contains(entityName.split('_').last)) {
                        print('[CapturePage] ✅ アプリのキャッシュディレクトリに既存ファイルを発見: ${entity.path}');
                        actualPath = entity.path;
                        tempFile = entity;
                        foundExistingFile = true;
                        break;
                      }
                    }
                  }
                } catch (listError) {
                  print('[CapturePage] ⚠️ ディレクトリリストエラー: $listError');
                }
              } else {
                print('[CapturePage] ⚠️ ディレクトリが存在しません: ${appExternalCacheDir.path}');
              }
            } else {
              print('[CapturePage] ⚠️ getExternalStorageDirectory()がnullを返しました');
            }
          } catch (e) {
            print('[CapturePage] ⚠️ 外部ストレージディレクトリ確認エラー: $e');
          }

          // 方法2: 固定パスでも確認（フォールバック）
          if (!foundExistingFile) {
            try {
              final fixedPaths = [
                '/storage/emulated/0/Android/data/com.auraface.kami_face_oracle/cache',
                '/sdcard/Android/data/com.auraface.kami_face_oracle/cache',
              ];

              for (final fixedPath in fixedPaths) {
                final fixedDir = io.Directory(fixedPath);
                if (await fixedDir.exists()) {
                  print('[CapturePage] 固定パスディレクトリを確認: $fixedPath');
                  try {
                    await for (final entity in fixedDir.list()) {
                      if (entity is io.File) {
                        final entityName = entity.path.split('/').last;
                        if (entityName.contains(filename) || filename.contains(entityName.split('_').last)) {
                          print('[CapturePage] ✅ 固定パスで既存ファイルを発見: ${entity.path}');
                          actualPath = entity.path;
                          tempFile = entity;
                          foundExistingFile = true;
                          break;
                        }
                      }
                    }
                    if (foundExistingFile) break;
                  } catch (listError) {
                    print('[CapturePage] ⚠️ 固定パスディレクトリリストエラー: $listError');
                  }
                }
              }
            } catch (e) {
              print('[CapturePage] ⚠️ 固定パス確認エラー: $e');
            }
          }

          print('[CapturePage] 既存ファイル検索結果: ${foundExistingFile ? "発見" : "未発見"}');

          // 既存ファイルが見つからない場合、Platform Channelでコピーを試行
          if (!foundExistingFile && actualPath == imagePath) {
            print('[CapturePage] 既存ファイルが見つからないため、コピーを試行');

            // 方法1: copyExternalFileToAppCacheを使用（外部ストレージディレクトリにコピー）
            final copiedPath = await FileAccessHelper.copyExternalFileToAppCache(imagePath);
            if (copiedPath != null && copiedPath.isNotEmpty) {
              print('[CapturePage] ✅ AppCache経由でファイルをコピー完了: $copiedPath');
              actualPath = copiedPath;
              tempFile = io.File(copiedPath);
            } else {
              // 方法2: copyExternalFileToInternalを使用（内部ストレージにコピー）
              print('[CapturePage] ⚠️ AppCacheコピーが失敗、内部ストレージへのコピーを試行');
              final copiedPath2 = await FileAccessHelper.copyExternalFileToInternal(imagePath);
              if (copiedPath2 != null && copiedPath2.isNotEmpty) {
                print('[CapturePage] ✅ 内部ストレージ経由でファイルをコピー完了: $copiedPath2');
                actualPath = copiedPath2;
                tempFile = io.File(copiedPath2);
              } else {
                throw Exception('すべてのコピー方法が失敗しました。ファイルにアクセスできません。');
              }
            }
          }
        } catch (copyError) {
          print('[CapturePage] ⚠️ ファイルコピーエラー: $copyError');

          // エラーメッセージを表示
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('ファイルにアクセスできませんでした: $copyError\n\n推奨: 「ギャラリーから選ぶ」を使用してください。'),
                duration: const Duration(seconds: 5),
              ),
            );
          }

          // コピーに失敗した場合、エラーを再スローして処理を中断
          setState(() => _busy = false);
          return;
        }
      }

      // ファイルの存在確認とログ出力（原因3対策：詳細ログ追加）
      final file = io.File(actualPath);
      print('[CapturePage] 顔検出を実行: パス=$actualPath');
      print('[AuraFace][DEBUG] File exists? ${await file.exists()}');

      if (!await file.exists()) {
        print('[CapturePage] ⚠️ ファイルが存在しません: $actualPath');
        print('[AuraFace][ERROR] File does not exist: $actualPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ファイルが見つかりませんでした')));
        }
        setState(() => _busy = false);
        return;
      }

      final fileSize = await file.length();
      print('[CapturePage] ✅ ファイルが存在します。サイズ: $fileSize bytes');
      print('[AuraFace][DEBUG] File size: $fileSize bytes');

      if (fileSize == 0) {
        print('[AuraFace][ERROR] File size is 0 bytes - file is empty');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ファイルが空です')));
        }
        setState(() => _busy = false);
        return;
      }

      List<Face> faces;
      try {
        // 方法1: InputImage.fromFilePath()を試行
        InputImage? inputImage;
        try {
          inputImage = InputImage.fromFilePath(actualPath);
          print('[CapturePage] InputImage.fromFilePath()で作成成功');
        } catch (pathError) {
          print('[CapturePage] ⚠️ InputImage.fromFilePath()が失敗: $pathError');
          print('[CapturePage] 画像をバイト配列として読み込んで再試行します...');

          // 方法2: 画像をバイト配列として読み込んでInputImage.fromBytes()を使用
          try {
            final bytes = await file.readAsBytes();
            print('[CapturePage] 画像をバイト配列として読み込み成功: ${bytes.length} bytes');

            // ui.Imageに変換（FlutterのImageCodecを使用）
            final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
            final frame = await codec.getNextFrame();
            final uiImage = frame.image;

            print('[CapturePage] 画像サイズ: ${uiImage.width}x${uiImage.height}');

            // ui.ImageからRGBAバイトデータを取得
            final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
            if (byteData == null) {
              throw Exception('画像のバイトデータ変換に失敗しました');
            }

            // InputImage.fromBytes()を使用（BGRA8888フォーマット）
            inputImage = InputImage.fromBytes(
              bytes: byteData.buffer.asUint8List(),
              metadata: InputImageMetadata(
                size: Size(uiImage.width.toDouble(), uiImage.height.toDouble()),
                rotation: InputImageRotation.rotation0deg,
                format: InputImageFormat.bgra8888,
                bytesPerRow: uiImage.width * 4,
              ),
            );
            print('[CapturePage] InputImage.fromBytes()で作成成功');

            // ui.Imageを破棄
            uiImage.dispose();
          } catch (bytesError) {
            print('[CapturePage] ⚠️ InputImage.fromBytes()も失敗: $bytesError');
            throw Exception('画像を開けませんでした: $bytesError');
          }
        }

        if (inputImage == null) {
          throw Exception('InputImageの作成に失敗しました');
        }

        print('[CapturePage] InputImageを作成しました。顔検出を実行中...');
        print('[AuraFace][STATE] FaceDetection start');

        // ✅ 修正: 画像処理ごとにFaceDetectorを再生成（キャッシュをクリア）
        final accurateDetector = _createFaceDetector();

        faces = await accurateDetector.processImage(inputImage);

        // ✅ 修正: ランドマークのデバッグログを追加
        if (faces.isNotEmpty) {
          final f = faces.first;
          print('[CapturePage] ✅ ランドマーク数: ${f.landmarks.length}');
          print('[CapturePage] ✅ Contour数: ${f.contours.length}');

          // 重要なランドマークポイントをログ出力
          try {
            final leftEye = f.landmarks[FaceLandmarkType.leftEye];
            final rightEye = f.landmarks[FaceLandmarkType.rightEye];
            final leftMouth = f.landmarks[FaceLandmarkType.leftMouth];
            final rightMouth = f.landmarks[FaceLandmarkType.rightMouth];
            final noseBase = f.landmarks[FaceLandmarkType.noseBase];

            print('[CapturePage] ✅ raw landmark(左目): ${leftEye?.position}');
            print('[CapturePage] ✅ raw landmark(右目): ${rightEye?.position}');
            print('[CapturePage] ✅ raw landmark(口左): ${leftMouth?.position}');
            print('[CapturePage] ✅ raw landmark(口右): ${rightMouth?.position}');
            print('[CapturePage] ✅ raw landmark(鼻): ${noseBase?.position}');
          } catch (e) {
            print('[CapturePage] ⚠️ ランドマークログ出力エラー: $e');
          }
        }

        // ✅ 修正: 処理完了後、FaceDetectorを閉じる（キャッシュを残さない）
        await accurateDetector.close();
        print('[CapturePage] 顔検出結果: ${faces.length}個の顔を検出');

        // 原因1対策：ML Kitの顔検出結果の詳細ログ
        if (faces.isEmpty) {
          print('[AuraFace][STATE] FaceDetection failed (no face)');
          print('[AuraFace][DEBUG] MLKit face count = 0');
        } else {
          print('[AuraFace][STATE] FaceDetection success');
          print('[AuraFace][DEBUG] MLKit face count = ${faces.length}');
          if (faces.isNotEmpty) {
            final bbox = faces.first.boundingBox;
            print(
                '[AuraFace][DEBUG] MLKit bbox = left:${bbox.left}, top:${bbox.top}, width:${bbox.width}, height:${bbox.height}');
          }
        }

        if (!mounted) {
          setState(() => _busy = false);
          return;
        }

        if (faces.isEmpty) {
          print('[CapturePage] ⚠️ 顔が検出されませんでした。画像を確認してください。');
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('顔が検出できませんでした。\n\n画像に顔が写っていることを確認してください。'),
            duration: Duration(seconds: 5),
          ));
          setState(() => _busy = false);
          return;
        }
      } catch (e) {
        print('[CapturePage] ⚠️ 顔検出エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('画像を開けませんでした: $e'),
            duration: const Duration(seconds: 5),
          ));
        }
        setState(() => _busy = false);
        return;
      }

      // ✅ 画像正規化処理を無効化（Python推論と同じように元画像をそのまま使用）
      // Python推論スクリプトでは画像をそのまま読み込んでMediaPipeで処理しているため、
      // Flutter側でも同じように元画像をそのまま使用する必要があります
      print('[CapturePage] 📐 画像正規化をスキップ（Python推論と一致させるため、元画像をそのまま使用）');

      // 元画像のFaceオブジェクトをそのまま使用
      final face = faces.first;

      // 検出された顔の特徴を抽出
      print('[AuraFace][STATE] FeatureExtract start');
      final feat = FaceFeatures(
        face.smilingProbability ?? 0.5,
        ((face.leftEyeOpenProbability ?? 0.5) + (face.rightEyeOpenProbability ?? 0.5)) / 2.0,
        0.5,
        0.5,
        0.5,
      );

      print('[AuraFace][STATE] FeatureExtract success');

      // ✅ 性格診断を実行（PersonalityTreeClassifier）
      print('[AuraFace][STATE] Personality start');

      // ✅ 修正: 画像切替時に以前のランドマークを保持しないように、全レイヤーの状態をリセット
      // （PersonalityTreeClassifierはstaticメソッドなので、ここではログのみ）
      print('[CapturePage] ✅ 画像切替: ランドマークをリセットしてから診断開始');

      // ✅ 修正: 画像アップロード直後にsetStateを確実に実行
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) {
        setState(() {});
      }

      PersonalityTreeDiagnosisResult? personalityResult;

      // 🔥 逃げ道ゼロ構成: runDiagnosis() を必ず使用
      // この関数が実行されない場合、アプリは必ずクラッシュします
      print('[CapturePage] 🔥🔥🔥 runDiagnosis() を呼び出します 🔥🔥🔥');

      try {
        // 🔥 新しいエントリーポイントを使用（サーバー推論強制）
        personalityResult = await runDiagnosis(file);

        // server_inferenceフラグのチェックはrunDiagnosis内で実行済み
        print('[AuraFace][STATE] Personality complete (Server)');
        print(
            '[CapturePage] ✅ 性格診断結果（サーバー）: タイプ=${personalityResult.personalityType} (${personalityResult.personalityTypeName})');
        print('[CapturePage] サーバー推論結果のLayer:');
        for (final entry in personalityResult.layerResults.entries) {
          print('[CapturePage]   ${entry.key}: ${entry.value}');
        }
      } catch (e, stackTrace) {
        print('[CapturePage] 🔥🔥🔥 サーバー推論エラー: $e 🔥🔥🔥');
        print('[CapturePage] スタックトレース: ${stackTrace.toString().split("\n").take(10).join("\n")}');
        final userMessage = getDiagnosisErrorMessage(e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userMessage),
              duration: const Duration(seconds: 8),
              backgroundColor: Colors.red,
            ),
          );
        }
        throw Exception("STOP_HERE_SERVER_INFERENCE_REQUIRED: $e");
      }

      // サーバー推論が成功しなかった場合は処理を中断
      if (personalityResult == null) {
        print('[CapturePage] 🔥🔥🔥 サーバー推論結果がnullです。クラッシュします。 🔥🔥🔥');
        // 🔥 必ずクラッシュさせる
        throw Exception("STOP_HERE_SERVER_INFERENCE_REQUIRED: personalityResult is null");
      }

      // 追加: 肌AI分析を実行し、gloss相当を補正
      // 実際のパスを使用（一時ファイルの場合はそれを使用）
      // fileは既に上で宣言されているので、そのまま使用
      SkinAnalysisResult skin;
      try {
        print('[CapturePage] 📊 肌診断を開始します...');
        print('[CapturePage] 画像ファイル: ${file.path}');
        print('[CapturePage] 顔検出結果: ${face.boundingBox}');
        // 【B】SkinAnalysisService経由で実行（多重実行防止・キュー化）
        skin = await SkinAnalysisService().analyzeSkin(file, face);
        print('[CapturePage] ✅ 肌診断完了');
        print('[CapturePage] 診断結果サマリー:');
        print('[CapturePage]   - shineScore: ${skin.shineScore}');
        print('[CapturePage]   - brightness: ${skin.brightness}');
        print('[CapturePage]   - evenness: ${skin.evenness}');
        print('[CapturePage]   - toneScore: ${skin.toneScore}');
        print('[CapturePage]   - redness: ${skin.redness}');
        print('[CapturePage]   - dullnessIndex: ${skin.dullnessIndex}');
        print('[CapturePage]   - texture: ${skin.texture}');
        print('[CapturePage]   - textureFineness: ${skin.textureFineness}');
        print('[CapturePage]   - dryness: ${skin.dryness}');
        print('[CapturePage]   - aiClassification: ${skin.aiClassification}');
      } catch (e, stackTrace) {
        print('[CapturePage] ❌ 肌診断エラー: $e');
        print('[CapturePage] スタックトレース: ${stackTrace.toString().split("\n").take(15).join("\n")}');

        // エラー時は再撮影を促すダイアログを表示
        if (mounted) {
          final shouldRetry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('画像分析エラー'),
              content: const Text(
                '画像分析中にエラーが発生しました。\n\n'
                '以下の点を確認して、もう一度撮影してください：\n'
                '• 顔がはっきり写っているか\n'
                '• 照明が十分か\n'
                '• カメラがぶれていないか\n'
                '• 正面を向いているか',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4E6CF0),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('もう一度撮影'),
                ),
              ],
            ),
          );

          if (shouldRetry == true) {
            // 再撮影を促すため、処理を中断して戻る
            if (mounted) {
              setState(() => _busy = false);
            }
            return;
          } else {
            // キャンセルの場合も処理を中断
            if (mounted) {
              setState(() => _busy = false);
            }
            return;
          }
        } else {
          // mountedでない場合は処理を中断
          return;
        }
      }

      // 診断結果の妥当性チェック
      if (skin.shineScore == null && skin.brightness == null) {
        print('[CapturePage] ⚠️ ツヤの診断結果が取得できませんでした');
      }
      if (skin.evenness == null && skin.toneScore == null && skin.redness == null) {
        print('[CapturePage] ⚠️ 血色の診断結果が取得できませんでした');
      }
      if (skin.dullnessIndex == null) {
        print('[CapturePage] ⚠️ くすみの診断結果が取得できませんでした');
      }
      if (skin.texture == null && skin.textureFineness == null) {
        print('[CapturePage] ⚠️ キメの診断結果が取得できませんでした');
      }
      if (skin.dryness == null) {
        print('[CapturePage] ⚠️ 乾燥傾向の診断結果が取得できませんでした');
      }

      // ⚠️ 重要: 診断結果の妥当性チェックを緩和
      // 主要な指標（brightness, dullnessIndex, texture, dryness）が取得できていれば続行
      // すべての指標が必須ではなく、主要な指標があれば診断を続行
      final hasEssentialMetrics = (skin.shineScore != null || skin.brightness != null) &&
          skin.dullnessIndex != null &&
          (skin.texture != null || skin.textureFineness != null) &&
          skin.dryness != null;

      if (!hasEssentialMetrics) {
        print('[CapturePage] ⚠️ 主要な診断結果が取得できていません');
        print('[CapturePage]   - shineScore: ${skin.shineScore}, brightness: ${skin.brightness}');
        print('[CapturePage]   - dullnessIndex: ${skin.dullnessIndex}');
        print('[CapturePage]   - texture: ${skin.texture}, textureFineness: ${skin.textureFineness}');
        print('[CapturePage]   - dryness: ${skin.dryness}');

        // 不足している指標を補完（デフォルト値を使用）
        if (skin.shineScore == null && skin.brightness == null) {
          print('[CapturePage] ⚠️ ツヤが取得できていないため、brightnessにデフォルト値を設定');
          // brightnessは既に計算されているはずなので、ここでは警告のみ
        }
        if (skin.dullnessIndex == null) {
          print('[CapturePage] ⚠️ くすみが取得できていないため、デフォルト値0.3を設定');
          // dullnessIndexは既に計算されているはずなので、ここでは警告のみ
        }
        if (skin.texture == null && skin.textureFineness == null) {
          print('[CapturePage] ⚠️ キメが取得できていないため、デフォルト値50.0を設定');
          // textureは既に計算されているはずなので、ここでは警告のみ
        }
        if (skin.dryness == null) {
          print('[CapturePage] ⚠️ 乾燥傾向が取得できていないため、デフォルト値50.0を設定');
          // drynessは既に計算されているはずなので、ここでは警告のみ
        }

        // ⚠️ 重要: brightnessがあれば最低限の診断は可能
        // dullnessIndexはbrightnessから推測できるため、brightnessがあれば続行
        final hasMinimumMetrics = (skin.shineScore != null || skin.brightness != null);

        if (!hasMinimumMetrics) {
          print('[CapturePage] ❌ 最低限の診断結果も取得できていません');
          if (mounted) {
            final shouldRetry = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('診断結果が不完全です'),
                content: const Text(
                  '主要な診断項目が正しく取得できませんでした。\n\n'
                  'もう一度撮影してください。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('キャンセル'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4E6CF0),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('もう一度撮影'),
                  ),
                ],
              ),
            );

            if (shouldRetry == true) {
              if (mounted) {
                setState(() => _busy = false);
              }
              return;
            } else {
              if (mounted) {
                setState(() => _busy = false);
              }
              return;
            }
          }
        } else {
          print('[CapturePage] ⚠️ 一部の指標が不足していますが、最低限の診断は可能です');
          print('[CapturePage] brightnessから不足している指標を推測します');
        }
      }
      final glossAdj = () {
        final b = skin.brightness.clamp(0.0, 1.0);
        final dull = (skin.dullnessIndex ?? (1.0 - b)).clamp(0.0, 1.0);
        final spot = (skin.spotDensity ?? 0.0).clamp(0.0, 1.0);
        final acne = (skin.acneActivity ?? 0.0).clamp(0.0, 1.0);
        final penalty = (0.35 * dull + 0.25 * spot + 0.2 * acne).clamp(0.0, 1.0);
        final base = 0.6 * b + 0.4 * (1.0 - dull);
        return (base * (1.0 - penalty)).clamp(0.0, 1.0);
      }();

      final enriched = FaceFeatures(
        feat.smile,
        feat.eyeOpen,
        glossAdj, // 潤い/ツヤを肌分析で補正
        feat.straightness,
        feat.claim,
      );

      // ベースライン/前日の肌結果を取得（なければ初期化）
      SkinAnalysisResult? baselineSkin;
      SkinAnalysisResult? previousSkin;
      try {
        final bMap = await Storage.getBaselineSkin();
        if (bMap == null) {
          // baseline画像があれば解析して保存
          final basePath = await Storage.getBaselineImagePath('neutral');
          if (basePath != null && io.File(basePath).existsSync()) {
            final baseInput = InputImage.fromFilePath(basePath);
            // ✅ 修正: FaceDetectorを再生成（キャッシュをクリア）
            // _faceDetectorはlate finalなので、新しいFaceDetectorを作成して使用
            final baseDetector = _createFaceDetector();
            try {
              final baseFaces = await baseDetector.processImage(baseInput);
              if (baseFaces.isNotEmpty) {
                // 【B】SkinAnalysisService経由で実行（多重実行防止・キュー化）
                final bRes = await SkinAnalysisService().analyzeSkin(io.File(basePath), baseFaces.first);
                await Storage.saveBaselineSkin(bRes.toSimpleMap());
                baselineSkin = bRes;
              }
            } catch (e) {
              print('[CapturePage] ⚠️ ベースライン画像の分析エラー: $e');
            } finally {
              await baseDetector.close();
            }
          }
        } else {
          baselineSkin = SkinAnalysisResult(
            skinType: 'baseline',
            oiliness: (bMap['oiliness'] ?? 0.5).toDouble(),
            smoothness: (bMap['smoothness'] ?? 0.5).toDouble(),
            uniformity: (bMap['uniformity'] ?? 0.5).toDouble(),
            poreSize: (bMap['poreSize'] ?? 0.3).toDouble(),
            brightness: (bMap['brightness'] ?? 0.7).toDouble(),
            skinIssues: const [],
            regionAnalysis: const {},
            recommendation: '',
            dullnessIndex: (bMap['dullnessIndex'] ?? 0.0).toDouble(),
            spotDensity: (bMap['spotDensity'] ?? 0.0).toDouble(),
            acneActivity: (bMap['acneActivity'] ?? 0.0).toDouble(),
            wrinkleDensity: (bMap['wrinkleDensity'] ?? 0.0).toDouble(),
          );
        }

        final pMap = await Storage.getLastSkin();
        if (pMap != null) {
          previousSkin = SkinAnalysisResult(
            skinType: 'previous',
            oiliness: (pMap['oiliness'] ?? 0.5).toDouble(),
            smoothness: (pMap['smoothness'] ?? 0.5).toDouble(),
            uniformity: (pMap['uniformity'] ?? 0.5).toDouble(),
            poreSize: (pMap['poreSize'] ?? 0.3).toDouble(),
            brightness: (pMap['brightness'] ?? 0.7).toDouble(),
            skinIssues: const [],
            regionAnalysis: const {},
            recommendation: '',
            dullnessIndex: (pMap['dullnessIndex'] ?? 0.0).toDouble(),
            spotDensity: (pMap['spotDensity'] ?? 0.0).toDouble(),
            acneActivity: (pMap['acneActivity'] ?? 0.0).toDouble(),
            wrinkleDensity: (pMap['wrinkleDensity'] ?? 0.0).toDouble(),
          );
        }
      } catch (_) {}

      final delta = SkinAnalyzerDelta.computeDelta(
        baseline: baselineSkin,
        previous: previousSkin,
        current: skin,
      );

      // 肌悪化の合成ペナルティ（0..1）
      final skinPenalty = [
            delta.dullnessDelta,
            delta.spotDelta,
            delta.acneDelta,
          ].map((v) => v).where((v) => v > 0).fold<double>(0, (p, v) => p + v) /
          3.0;

      // サーバー診断結果がある場合は、その結果から正しい神を取得
      // 注意: RevealPageでpersonalityDiagnosisResultから正しい神を取得するため、
      // ここではgodをnullにしても良い（RevealPageで決定される）
      Deity? god;
      if (personalityResult != null) {
        print('[CapturePage] ✅ サーバー診断結果あり: type=${personalityResult.personalityType}');
        print('[CapturePage] RevealPageでpersonalityDiagnosisResultから正しい神を取得します');
        // RevealPageでpersonalityDiagnosisResultから正しい神を取得するため、ここではnullを渡す
        god = null;
      } else {
        print('[CapturePage] ⚠️ サーバー診断結果がないため、既存ロジックで神を決定');
        god = Scoring.nearestDeityWeighted(enriched, skinDeltaPenalty: skinPenalty.clamp(0.0, 1.0));
      }

      // 目領域の明度解析
      double eyeBrightness = 0.6; // デフォルト値
      try {
        final leftEyePts = face.contours[FaceContourType.leftEye]?.points ?? [];
        final rightEyePts = face.contours[FaceContourType.rightEye]?.points ?? [];
        if (leftEyePts.isNotEmpty && rightEyePts.isNotEmpty) {
          // 目の中心座標を計算
          final leftEyeCenter = Offset(
            leftEyePts.map((p) => p.x.toDouble()).reduce((a, b) => a + b) / leftEyePts.length,
            leftEyePts.map((p) => p.y.toDouble()).reduce((a, b) => a + b) / leftEyePts.length,
          );
          final rightEyeCenter = Offset(
            rightEyePts.map((p) => p.x.toDouble()).reduce((a, b) => a + b) / rightEyePts.length,
            rightEyePts.map((p) => p.y.toDouble()).reduce((a, b) => a + b) / rightEyePts.length,
          );

          // 目のサイズを推定（輪郭のバウンディングボックスから）
          final leftEyeWidth =
              (leftEyePts.map((p) => p.x).reduce(math.max) - leftEyePts.map((p) => p.x).reduce(math.min)).toDouble();
          final leftEyeHeight =
              (leftEyePts.map((p) => p.y).reduce(math.max) - leftEyePts.map((p) => p.y).reduce(math.min)).toDouble();
          final rightEyeWidth =
              (rightEyePts.map((p) => p.x).reduce(math.max) - rightEyePts.map((p) => p.x).reduce(math.min)).toDouble();
          final rightEyeHeight =
              (rightEyePts.map((p) => p.y).reduce(math.max) - rightEyePts.map((p) => p.y).reduce(math.min)).toDouble();

          // 目の領域をサンプリング（画像の範囲内に収める）
          final faceRect = face.boundingBox;
          final decodedImage = img.decodeImage(Uint8List.fromList(await io.File(actualPath).readAsBytes()));
          if (decodedImage != null) {
            final imageWidth = decodedImage.width.toDouble();
            final imageHeight = decodedImage.height.toDouble();

            double totalBrightness = 0.0;
            int sampleCount = 0;

            // 左目と右目をサンプリング
            for (final eyeCenter in [leftEyeCenter, rightEyeCenter]) {
              final eyeX = eyeCenter.dx.clamp(faceRect.left, faceRect.right);
              final eyeY = eyeCenter.dy.clamp(faceRect.top, faceRect.bottom);
              final eyeW = ((leftEyeWidth + rightEyeWidth) / 2).clamp(10.0, 100.0);
              final eyeH = ((leftEyeHeight + rightEyeHeight) / 2).clamp(5.0, 50.0);

              // 目の領域を画像から抽出して明度を計算
              final x0 = (eyeX - eyeW / 2).clamp(0.0, imageWidth - 1).toInt();
              final y0 = (eyeY - eyeH / 2).clamp(0.0, imageHeight - 1).toInt();
              final w = (eyeW.clamp(1.0, imageWidth - x0)).toInt();
              final h = (eyeH.clamp(1.0, imageHeight - y0)).toInt();

              if (w > 0 && h > 0 && x0 >= 0 && y0 >= 0 && x0 + w <= imageWidth && y0 + h <= imageHeight) {
                try {
                  final eyeRegion = img.copyCrop(decodedImage, x: x0, y: y0, width: w, height: h);
                  final bytes = eyeRegion.getBytes();
                  double sumLuma = 0.0;
                  int pixelCount = 0;
                  for (int i = 0; i < bytes.length; i += 4) {
                    final r = bytes[i].toDouble();
                    final g = bytes[i + 1].toDouble();
                    final b = bytes[i + 2].toDouble();
                    final luma = 0.299 * r + 0.587 * g + 0.114 * b;
                    sumLuma += luma;
                    pixelCount++;
                  }
                  if (pixelCount > 0) {
                    totalBrightness += (sumLuma / pixelCount) / 255.0;
                    sampleCount++;
                  }
                } catch (e) {
                  // 画像処理エラー時はスキップ
                }
              }
            }

            if (sampleCount > 0) {
              eyeBrightness = (totalBrightness / sampleCount).clamp(0.0, 1.0);
            }
          }
        }
      } catch (e) {
        // エラー時はデフォルト値を使用
        eyeBrightness = 0.6;
      }

      // 美運スコア算出
      final beauty = computeBeautyLuckScore(
        skin: skin,
        features: enriched,
        eyeBrightness: eyeBrightness,
        puffiness: 1.0 - enriched.straightness, // 直線率の逆を簡易むくみ近似
      );

      // シンプル褒めコメント（前日比は保存後に別画面で評価）
      final comment = beauty >= 0.75
          ? '目の輝きとツヤが調和。今日は流れが良い日です✨'
          : beauty >= 0.55
              ? '肌の調子は安定。小さなケアでさらに上向きです。'
              : '少し休息を。保湿と眠りで明日を整えましょう。';

      // 今回の肌を「前回」として保存（失敗しても結果画面へ遷移）
      try {
        await Storage.saveLastSkin(skin.toSimpleMap());
      } catch (e) {
        print('[CapturePage] saveLastSkin skip (file path): $e');
      }

      // ✅ 肌診断結果をDaily Progressに保存
      try {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        print('[CapturePage] 📊 肌診断結果をDaily Progressに保存開始...');
        print('[CapturePage] 診断結果: shineScore=${skin.shineScore}, brightness=${skin.brightness}');
        print('[CapturePage] 診断結果: evenness=${skin.evenness}, toneScore=${skin.toneScore}, redness=${skin.redness}');
        print('[CapturePage] 診断結果: dullnessIndex=${skin.dullnessIndex}');
        print('[CapturePage] 診断結果: texture=${skin.texture}, textureFineness=${skin.textureFineness}');
        print('[CapturePage] 診断結果: dryness=${skin.dryness}');

        final dailyRecord = SkinResultConverter.convertToDailyRecord(skin, today);
        final box = Hive.box<Map>('skin_daily_records');
        final repo = SkinRecordRepositoryHive(box);
        await repo.upsert(dailyRecord);
        print(
            '[CapturePage] ✅ Daily Progressに保存完了: glow=${dailyRecord.glow}, tone=${dailyRecord.tone}, dullness=${dailyRecord.dullness}, texture=${dailyRecord.texture}, dryness=${dailyRecord.dryness}');
      } catch (e, stackTrace) {
        print('[CapturePage] ❌ Daily Progress保存エラー: $e');
        print('[CapturePage] スタックトレース: ${stackTrace.toString().split("\n").take(10).join("\n")}');
        // エラーが発生しても処理を継続
      }

      // ✅ AI診断を実行（バックグラウンドで非同期実行、エラーがあっても処理を継続）
      SkinAIDiagnosisResult? aiDiagnosisResult;
      try {
        // サーバーURLを明示的に設定（ServerPersonalityServiceと同じURLを使用）
        final aiService = SkinAnalysisAIService(
          apiUrl: ServerPersonalityService.serverUrl,
        );
        // サーバーの状態を確認（オプション）
        final isHealthy = await aiService.checkServerHealth().timeout(
              const Duration(seconds: 3),
              onTimeout: () => false,
            );

        if (isHealthy) {
          aiDiagnosisResult = await aiService.analyzeFromFile(file).timeout(
                const Duration(seconds: 25),
                onTimeout: () => SkinAIDiagnosisResult(
                  success: false,
                  error: 'タイムアウト',
                ),
              );

          if (aiDiagnosisResult?.success == true) {
            print(
                '[CapturePage] AI診断成功: ${aiDiagnosisResult?.topDiagnosis} (${aiDiagnosisResult?.topScore?.toStringAsFixed(1)}%');

            // サーバーからの8項目をSkinAnalysisResultに反映
            if (aiDiagnosisResult?.metrics != null) {
              print('[CapturePage] 📊 サーバーからの8項目を反映中...');
              final serverMetrics = aiDiagnosisResult!.metrics!;

              // サーバーからの8項目を取得（0-100スコア）
              final serverOiliness = serverMetrics['oiliness'] ?? skin.oiliness * 100;
              final serverDryness = serverMetrics['dryness'] ?? skin.dryness;
              final serverTexture = serverMetrics['texture'] ?? skin.texture;
              final serverEvenness = serverMetrics['evenness'] ?? skin.evenness;
              final serverPores = serverMetrics['pores'] ?? (skin.poreSize ?? 0.0) * 100;
              final serverRedness = serverMetrics['redness'] ?? skin.redness;
              final serverFirmness = serverMetrics['firmness'] ?? skin.firmness;
              final serverAcne = serverMetrics['acne'] ?? skin.acne;

              print('[CapturePage] サーバーからの8項目:');
              print('[CapturePage]   - oiliness: $serverOiliness');
              print('[CapturePage]   - dryness: $serverDryness');
              print('[CapturePage]   - texture: $serverTexture');
              print('[CapturePage]   - evenness: $serverEvenness');
              print('[CapturePage]   - pores: $serverPores');
              print('[CapturePage]   - redness: $serverRedness');
              print('[CapturePage]   - firmness: $serverFirmness');
              print('[CapturePage]   - acne: $serverAcne');

              // SkinAnalysisResultを更新（既存の値を保持しつつ、サーバーからの8項目で上書き）
              skin = SkinAnalysisResult(
                skinType: skin.skinType,
                oiliness: (serverOiliness / 100.0).clamp(0.0, 1.0), // 0-100を0-1に変換
                smoothness: skin.smoothness,
                uniformity: skin.uniformity,
                poreSize: (serverPores / 100.0).clamp(0.0, 1.0), // 0-100を0-1に変換
                brightness: skin.brightness,
                skinIssues: skin.skinIssues,
                regionAnalysis: skin.regionAnalysis,
                recommendation: skin.recommendation,
                dullnessIndex: skin.dullnessIndex,
                spotDensity: skin.spotDensity,
                acneActivity: skin.acneActivity,
                wrinkleDensity: skin.wrinkleDensity,
                eyeBrightness: skin.eyeBrightness,
                darkCircle: skin.darkCircle,
                browBalance: skin.browBalance,
                noseGloss: skin.noseGloss,
                jawPuffiness: skin.jawPuffiness,
                aiClassification: skin.aiClassification,
                textureFineness: skin.textureFineness,
                colorUniformity: skin.colorUniformity,
                shineScore: skin.shineScore,
                firmnessScore: skin.firmnessScore,
                toneScore: skin.toneScore,
                // サーバーからの8項目で上書き
                dryness: (serverDryness ?? 0.0).toDouble().clamp(0.0, 100.0),
                redness: (serverRedness ?? 0.0).toDouble().clamp(0.0, 100.0),
                texture: (serverTexture ?? 0.0).toDouble().clamp(0.0, 100.0),
                evenness: (serverEvenness ?? 0.0).toDouble().clamp(0.0, 100.0),
                firmness: (serverFirmness ?? 0.0).toDouble().clamp(0.0, 100.0),
                acne: (serverAcne ?? 0.0).toDouble().clamp(0.0, 100.0),
                // raw値も保持
                dullnessIndexRaw: skin.dullnessIndexRaw,
                spotDensityRaw: skin.spotDensityRaw,
                acneActivityRaw: skin.acneActivityRaw,
                wrinkleDensityRaw: skin.wrinkleDensityRaw,
                eyeBrightnessRaw: skin.eyeBrightnessRaw,
                darkCircleRaw: skin.darkCircleRaw,
                browBalanceRaw: skin.browBalanceRaw,
                noseGlossRaw: skin.noseGlossRaw,
                jawPuffinessRaw: skin.jawPuffinessRaw,
              );

              print('[CapturePage] ✅ サーバーからの8項目を反映完了');
            } else {
              print('[CapturePage] ⚠️ サーバーからのmetricsがnullです');
            }
          } else {
            print('[CapturePage] AI診断エラー: ${aiDiagnosisResult?.error}');
          }
        } else {
          print('[CapturePage] AI診断サーバーが利用できません');
        }
      } catch (e) {
        print('[CapturePage] AI診断例外: $e');
        // AI診断が失敗しても既存の処理は継続
      }

      // 日次スナップ保存（失敗しても結果画面へ遷移）
      final now = DateTime.now();
      try {
        await Storage.saveDailySnapshot({
          'date': DateFormat('yyyy-MM-dd').format(now),
          'metrics': {
            'gloss': (skin.brightness * (1 - (skin.dullnessIndex ?? 0))).clamp(0.0, 1.0),
            'symmetry': enriched.straightness,
            'lip_moisture': 1.0 - (skin.acneActivity ?? 0.0),
            'eye_brightness': 0.6,
            'puffiness': 1.0 - enriched.straightness,
          },
          'beauty_score': beauty,
          'deity': god?.id ?? deities.first.id,
          'comment': comment,
        });
      } catch (e) {
        print('[CapturePage] saveDailySnapshot skip (file path): $e');
      }
      try {
        await CloudService.saveDailyRecord({
          'date': DateFormat('yyyy-MM-dd').format(now),
          'beauty_score': beauty,
          'deity': god?.id ?? deities.first.id,
          'comment': comment,
        });
      } catch (e) {
        print('[CapturePage] saveDailyRecord skip (file path): $e');
      }

      print('[AuraFace][STATE] ResultPage show');

      // DIAG_RESULTログを出力（実機自動テスト用）
      if (personalityResult != null) {
        try {
          final diagnosisData = {
            'personalityType': personalityResult.personalityType,
            'personalityTypeName': personalityResult.personalityTypeName,
            'personalityDescription': personalityResult.personalityDescription,
            'layerResults': personalityResult.layerResults,
            'layerValues': personalityResult.layerValues.map((k, v) => MapEntry(k, v.toString())),
            'layerReasons': personalityResult.layerReasons,
            'hasError': personalityResult.hasError,
            'warnings': personalityResult.warnings
                .map((w) => {
                      'type': w.type,
                      'message': w.message,
                      'layer': w.layer,
                    })
                .toList(),
            'timestamp': DateTime.now().toIso8601String(),
          };

          // DIAG_RESULTタグ付きでログ出力
          print('DIAG_RESULT: ${jsonEncode(diagnosisData)}');

          // AUTO_MODE形式のログ出力（必須）
          if (widget.autoMode) {
            final fileName = actualPath.split('/').last;
            final layerStr = personalityResult.layerResults.values.join(',');
            final typeStr = personalityResult.personalityType.toString();
            print('[AUTO_MODE] file=$fileName status=success type=$typeStr layers=$layerStr');
          }
        } catch (e) {
          print('[CapturePage] ⚠️ DIAG_RESULTログ出力エラー: $e');
          if (widget.autoMode) {
            print('[AUTO_MODE] status=fail reason=log_error');
          }
        }
      } else if (widget.autoMode) {
        print('[AUTO_MODE] status=fail reason=diagnosis_failed');
      }

      // アップロード後、まずアニメーション画面（RevealPage）を表示
      // 成功時に_busyをリセット（Navigator.pushReplacementの前）
      if (mounted) {
        setState(() => _busy = false);
      }

      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => RevealPage(
                    god: god, // サーバー結果がある場合はnull、RevealPageで決定される
                    features: enriched,
                    skin: skin,
                    beautyScore: beauty,
                    praise: comment,
                    aiDiagnosisResult: aiDiagnosisResult,
                    personalityDiagnosisResult: personalityResult, // ✅ 性格診断結果を渡す（これから正しい神を取得）
                  )));

      // 一時ファイルをクリーンアップ
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
          print('[CapturePage] ✅ 一時ファイルを削除: ${tempFile.path}');
        } catch (deleteError) {
          print('[CapturePage] ⚠️ 一時ファイル削除エラー: $deleteError');
        }
      }
    } catch (e) {
      print('[CapturePage] Error: $e');

      // エラー時も一時ファイルをクリーンアップ
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
          print('[CapturePage] ✅ エラー時も一時ファイルを削除: ${tempFile.path}');
        } catch (deleteError) {
          print('[CapturePage] ⚠️ 一時ファイル削除エラー: $deleteError');
        }
      }

      if (widget.autoMode) {
        print('[AUTO_MODE] status=fail reason=${e.toString()}');
      }

      if (mounted) {
        if (!widget.autoMode) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
        }
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('撮影/アップロード'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final previewSize = c.value.previewSize!;
    final imageSizeForView = Size(previewSize.height, previewSize.width);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('撮影/アップロード'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, cs) {
            final viewSize = Size(cs.maxWidth, cs.maxHeight);
            final guide = _guideRect(viewSize);

            final rawImageSize = _lastImageSize ?? imageSizeForView;
            final sensorOrientation = c.description.sensorOrientation;
            final imageSize = (sensorOrientation == 90 || sensorOrientation == 270)
                ? Size(rawImageSize.height, rawImageSize.width)
                : rawImageSize;

            debugPrint(
                '[CapturePage] transform: rawImageSize=${rawImageSize.width}x${rawImageSize.height}, sensorOrientation=$sensorOrientation, imageSize=${imageSize.width}x${imageSize.height}, viewSize=${viewSize.width}x${viewSize.height}');

            final transform = PreviewTransform(
              imageSize: imageSize,
              viewSize: viewSize,
              isFrontCamera: c.description.lensDirection == CameraLensDirection.front,
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                // カメラプレビュー（BoxFit.coverで統一）
                Center(
                  child: ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: imageSizeForView.width,
                        height: imageSizeForView.height,
                        child: CameraPreview(c),
                      ),
                    ),
                  ),
                ),

                // 顔検出オーバーレイ
                Positioned.fill(
                  child: CustomPaint(
                    painter: FaceOverlayPainter(
                      faces: _faces,
                      transform: transform,
                      guideRect: guide,
                      debug: _debug,
                    ),
                  ),
                ),

                // ガイダンスオーバーレイ（最前面）
                if (_shouldShowGuidance || _isReadyToCapture)
                  TutorialGuidanceOverlay(
                    title: _shouldShowGuidance ? _guidanceTitle : '',
                    subtitle: _guidanceSub,
                    isReady: _isReadyToCapture,
                    progress01: _stableFrameCount / _requiredStableFrames,
                    showImage: _shouldShowGuidance,
                    compact: _isReadyToCapture,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // 不要なメソッドを削除: _buildMysticButton
}
