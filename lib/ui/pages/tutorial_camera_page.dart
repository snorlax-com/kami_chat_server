import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path_lib;
import '../../utils/preview_transform.dart';
import '../../widgets/face_overlay_painter.dart';
import '../../skin_analysis.dart';
import 'package:kami_face_oracle/services/skin_analysis_service.dart';
import '../../feature/tutorial/device_pose_gate.dart';
import '../../feature/tutorial/tutorial_guidance_overlay.dart';
import 'package:kami_face_oracle/feature/web_shutter/web_shutter_bridge.dart';
import 'package:kami_face_oracle/feature/web_shutter/web_shutter_camera_view.dart';
import 'package:kami_face_oracle/feature/web_shutter/web_shutter_service.dart';
import 'package:kami_face_oracle/feature/web_shutter/web_shutter_state.dart';
import 'package:kami_face_oracle/web/web_camera_controller.dart';
import 'package:kami_face_oracle/web/web_camera_view.dart';
import 'package:kami_face_oracle/web/web_camera_types.dart';
import 'package:kami_face_oracle/camera/quality_signals.dart';
import 'package:kami_face_oracle/camera/guidance_engine.dart';
import 'package:kami_face_oracle/camera/capture_gate.dart';
import 'package:kami_face_oracle/camera/burst_capture.dart';
import 'package:kami_face_oracle/web/face_mesh_web_bridge.dart';
import 'package:kami_face_oracle/core/permission_service.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/inference/diagnosis_entry.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';
import 'package:kami_face_oracle/services/server_personality_service.dart';
import 'package:kami_face_oracle/utils/temp_file_helper.dart';
import 'package:kami_face_oracle/ui/pages/reveal_page.dart';

class TutorialCameraPage extends StatefulWidget {
  final String currentStep; // 'neutral' or 'smiling'
  /// 直接ルート（?e2e=1&route=camera）で開いたときのみ true。通常の「カメラで撮影」遷移では false で撮影画面を表示する。
  final bool forceE2ESkipCamera;

  const TutorialCameraPage({
    super.key,
    this.currentStep = 'neutral',
    this.forceE2ESkipCamera = false,
  });

  @override
  State<TutorialCameraPage> createState() => _TutorialCameraPageState();
}

class _TutorialCameraPageState extends State<TutorialCameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  late final FaceDetector _detector;
  late final DevicePoseGate _poseGate;

  bool _streaming = false;
  bool _detecting = false;

  List<Face> _faces = [];
  Size? _lastImageSize;

  String _guidanceTitle = '椅子に座り、スマホを目の高さで正面に構えてください';
  String? _guidanceSub;
  bool _isReadyToCapture = false;
  bool _shouldShowGuidance = true; // ガイダンスを表示するかどうか
  int _stableFrameCount = 0;
  static const int _requiredStableFrames = 5; // さらに緩和: 8 → 5
  bool _capturing = false;

  // Web 向け MediaPipe 自動シャッター
  bool _webShutterReady = false;
  bool _webShutterInitStarted = false;
  bool _webShutterInitializing = false;
  bool _webCameraStartTapped = false;
  bool _webFaceMeshReady = false;
  int _webGateStableCount = 0;
  bool _webBurstInProgress = false;
  Timer? _webGuidanceTimer;
  static const int _webGateStableRequired = 5;
  static const CaptureGateConfig _webGateConfig = CaptureGateConfig(
    maxYaw: 8,
    maxPitch: 8,
    maxRoll: 5,
    centerTol: 0.10,
    minFaceH: 0.35,
    maxFaceH: 0.65,
    minBrightness: 0.20,
  );

  final bool _debug = true;

  /// E2E時（?e2e=1）Webでカメラを使わず、一定時間後に疑似撮影→診断→結果へ
  bool _e2eMode = false;

  /// Web 簡易カメラ（getUserMedia 主体・安定化用）
  WebCameraController? _webSimpleController;
  bool _webSimpleViewRegistered = false;
  bool _webSimpleStartTapped = false;
  bool _webSimpleStarting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 画面の向きを縦向きに固定（E2E時もdisposeで解除するためここで設定）
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    _poseGate = DevicePoseGate(
      gyroStillThreshold: 0.30,
      gyroStableRequiredFrames: 3,
      pitchThresholdDeg: 20.0,
      rollThresholdDeg: 20.0,
    );
    _poseGate.start();

    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,
        enableContours: true,
        enableLandmarks: true,
        minFaceSize: 0.1,
      ),
    );

    // 直接ルート（route=camera）で開いたときだけカメラをスキップ。通常の「カメラで撮影」から来た場合は撮影画面を表示する。
    if (kIsWeb && E2E.isEnabled && widget.forceE2ESkipCamera) {
      _e2eMode = true;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _onCapturedBytesE2E();
      });
      return;
    }

    if (kIsWeb && WebCameraController.isSupported) {
      _webSimpleController = WebCameraController();
    }
    if (!kIsWeb) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (kIsWeb) {
      _webSimpleController?.stop();
      _webSimpleController = null;
      _webGuidanceTimer?.cancel();
      _webGuidanceTimer = null;
      if (FaceMeshWebBridge.isSupported) FaceMeshWebBridge.stop();
      WebShutterService.instance.stopPolling();
      if (WebShutterBridge.isSupported) {
        WebShutterBridge.stopAutoShutterLoop();
        WebShutterBridge.setOnCaptureCallback(null);
        WebShutterBridge.setOnCaptureErrorCallback(null);
      }
    }
    _poseGate.stop();
    _stopStream();
    _controller?.dispose();
    _detector.close();
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
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (kIsWeb && _webSimpleController != null) {
        _webSimpleController!.stop();
        if (mounted) setState(() {});
      }
      _stopStream();
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      if (!kIsWeb) _init();
    }
  }

  static const String _webVideoElementId = 'web_shutter_video';

  void _onWebGuidanceTick(Timer t) {
    if (!mounted || !_webFaceMeshReady || _webBurstInProgress || _capturing) return;
    FaceMeshWebBridge.analyzeFrame(_webVideoElementId).then((faceResult) {
      if (!mounted) return;
      final q = FaceMeshWebBridge.getQualitySignals(_webVideoElementId);
      final fogSuspected = QualitySignals.inferFogSuspected(q.brightness, q.contrast);
      final ws = WebShutterService.instance.state.value;
      final motion = (ws?.debug['motion'] as num?)?.toDouble() ?? 0.0;
      final shaky = motion > 0.22;

      double faceCx = 0.5, faceCy = 0.5, faceH = 0.4;
      if (faceResult.ok && faceResult.bbox != null) {
        faceCx = faceResult.bbox!.cx;
        faceCy = faceResult.bbox!.cy;
        faceH = faceResult.bbox!.h;
      }
      final gateState = CaptureGate.evaluate(
        cfg: _webGateConfig,
        yaw: faceResult.yaw,
        pitch: faceResult.pitch,
        roll: faceResult.roll,
        faceCx: faceCx,
        faceCy: faceCy,
        faceH: faceH,
        brightness: q.brightness,
      );
      final hasKeyParts = faceResult.ok && faceResult.score > 0.3;
      final msg = GuidanceEngine.decide(
        hasFace: faceResult.ok,
        hasKeyParts: hasKeyParts,
        okPose: gateState.okPose,
        okCenter: gateState.okCenter,
        okSize: gateState.okSize,
        okBrightness: gateState.okBrightness,
        fogSuspected: fogSuspected,
        shaky: shaky,
        occluded: faceResult.ok && !hasKeyParts,
        notLevel: faceResult.roll.abs() > _webGateConfig.maxRoll,
        notFront: faceResult.yaw.abs() > _webGateConfig.maxYaw || faceResult.pitch.abs() > _webGateConfig.maxPitch,
      );
      if (!mounted) return;
      setState(() {
        _guidanceSub = msg.main;
        if (gateState.okAll) {
          _webGateStableCount++;
          if (_webGateStableCount >= _webGateStableRequired) {
            _webGateStableCount = 0;
            _webBurstInProgress = true;
            _runWebBurst();
          }
        } else {
          _webGateStableCount = 0;
        }
      });
    });
  }

  Future<void> _runWebBurst() async {
    final burst = BurstCapture<String>();
    for (int i = 0; i < 3; i++) {
      if (!mounted) break;
      final faceResult = await FaceMeshWebBridge.analyzeFrame(_webVideoElementId);
      final dataUrl = await FaceMeshWebBridge.captureOneFrame(_webVideoElementId);
      if (dataUrl != null && dataUrl.isNotEmpty) {
        burst.add(dataUrl, faceResult.yaw, faceResult.pitch, faceResult.roll);
      }
      if (i < 2) await Future.delayed(const Duration(milliseconds: 270));
    }
    if (!mounted) {
      setState(() => _webBurstInProgress = false);
      return;
    }
    final best = burst.pickBest();
    if (best != null) {
      try {
        final comma = best.image.indexOf(',');
        final base64 = comma >= 0 ? best.image.substring(comma + 1) : best.image;
        final bytes = base64Decode(base64);
        final filename = 'tutorial_${widget.currentStep}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _onCapturedBytes(bytes, filename);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('連写の保存に失敗しました: $e')));
        }
      }
    }
    if (mounted) setState(() => _webBurstInProgress = false);
  }

  /// JS から返るエラーコードを実機で分かる短いメッセージに変換
  static String _webShutterInitErrorMessage(Object e) {
    final s = e.toString();
    if (s.contains('SECURE_CONTEXT_REQUIRED') || s.contains('MEDIA_DEVICES_UNAVAILABLE')) {
      return 'カメラを利用するには HTTPS で開いてください。今は HTTP のためカメラが使えません。同じ Wi‑Fi で PC から https の URL で開くか、「画像をアップロード」をご利用ください。';
    }
    if (s.contains('MEDIAPIPE_LOAD_FAILED') || s.contains('Failed to fetch') || s.contains('NetworkError')) {
      return '顔検出の読み込みに失敗しました。Wi-Fiを確認してから「カメラを開始」を再度タップしてください。';
    }
    if (s.contains('ELEMENT_NOT_FOUND') || s.contains('element not found')) {
      return '画面の準備ができていません。2〜3秒待ってから「カメラを開始」を再度タップしてください。';
    }
    if (s.contains('CAMERA_DENIED') || s.contains('NotAllowedError')) {
      return 'カメラの使用が許可されていません。ブラウザの設定でカメラを許可してください。';
    }
    if (s.contains('CAMERA_NOT_FOUND')) {
      return 'カメラが見つかりません。端末のカメラを確認してください。';
    }
    if (s.contains('CAMERA_IN_USE') || s.contains('NotReadableError')) {
      return 'カメラは他のアプリで使用中の可能性があります。';
    }
    if (s.contains('スクリプトが読み込めません')) {
      return '読み込みに時間がかかっています。ページを更新してから再度お試しください。';
    }
    return 'カメラの初期化に失敗しました。ページを更新するか、しばらく待ってから再度お試しください。';
  }

  /// Web 手動撮影時のエラーをユーザー向けメッセージに変換
  static String _webCaptureErrorMessage(Object e) {
    final s = e.toString();
    if (s.contains('StateError') ||
        s.contains('Camera not ready') ||
        s.contains('Video not ready') ||
        s.contains('wait timeout')) {
      return 'カメラが準備できていません。カメラの許可が「許可」か確認し、プレビューがはっきり出てから2〜3秒待って「撮影」を押してください。変わらない場合はページを更新して「カメラを開始」からやり直してください。';
    }
    if (s.contains('toBlob failed') || s.contains('FileReader failed')) {
      return '撮影画像の取得に失敗しました。もう一度撮影してください。';
    }
    if (s.contains('TimeoutException') || s.contains('タイムアウト')) {
      return 'サーバーが応答しません。同じWi‑Fiかネットワークを確認し、もう一度撮影してください。';
    }
    if (s.contains('CONSENT_REQUIRED') || s.contains('403')) {
      return '同意が未登録です。最初に生体データ同意で「I Agree」をタップしてください。';
    }
    if (s.contains('Failed to load') ||
        s.contains('Connection refused') ||
        s.contains('SocketException') ||
        s.contains('Connection') ||
        s.contains('NetworkError') ||
        s.contains('CORS')) {
      return 'サーバーに接続できません。Wi‑Fiを確認するか、時間をおいてもう一度撮影してください。';
    }
    if (s.contains('顔が検出されませんでした')) return s;
    if (s.contains('STOP_HERE_SERVER_INFERENCE_REQUIRED') || s.contains('サーバー推論')) {
      return '診断サーバーでエラーが発生しました。しばらく待ってからもう一度撮影してください。';
    }
    if (s.contains('画像のデコード') || s.contains('デコードに失敗')) {
      return '画像の読み込みに失敗しました。もう一度撮影してください。';
    }
    // 原因が分かるよう短く表示（長い場合は省略）
    final detail = s.length > 60 ? '${s.substring(0, 60)}…' : s;
    return '撮影に失敗しました。もう一度お試しください。（$detail）';
  }

  Future<void> _initWebShutter() async {
    if (!WebShutterBridge.isSupported) return;
    try {
      if (mounted)
        setState(() {
          _webShutterInitializing = true;
          _guidanceSub = null;
        });
      // スクリプトは動的 import のため即時アタッチ。実機は遅いので最大12秒待つ
      for (int i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        if (WebShutterBridge.isScriptLoaded) break;
        if (i == 59) {
          throw Exception('自動シャッターのスクリプトが読み込めません。ページを更新してください。');
        }
      }
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Object? lastError;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          await WebShutterBridge.init('web_shutter_video', 'web_shutter_canvas');
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          debugPrint('[TUTORIAL_CAM] Web shutter init attempt ${attempt + 1} failed: $e');
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
        }
      }
      if (lastError != null) throw lastError;
      if (!mounted) return;
      WebShutterBridge.setOnCaptureErrorCallback((String msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      });
      WebShutterBridge.setOnCaptureCallback((String base64DataUrl) {
        if (!mounted) return;
        if (_webBurstInProgress) return; // 連写中は既存シャッターを無視
        try {
          final comma = base64DataUrl.indexOf(',');
          final base64 = comma >= 0 ? base64DataUrl.substring(comma + 1) : base64DataUrl;
          final bytes = base64Decode(base64);
          final filename = 'tutorial_${widget.currentStep}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          _onCapturedBytes(bytes, filename);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('画像の取得に失敗しました: $e')));
          }
        }
      });
      WebShutterBridge.startAutoShutterLoop('onWebShutterFired');
      WebShutterService.instance.startPolling();
      if (FaceMeshWebBridge.isSupported) {
        try {
          await FaceMeshWebBridge.init();
          FaceMeshWebBridge.start();
          _webFaceMeshReady = true;
        } catch (_) {}
      }
      _webGuidanceTimer?.cancel();
      _webGuidanceTimer = Timer.periodic(const Duration(milliseconds: 200), _onWebGuidanceTick);
      if (mounted)
        setState(() {
          _webShutterReady = true;
          _webShutterInitializing = false;
        });
    } catch (e) {
      debugPrint('[TUTORIAL_CAM] Web shutter init failed: $e');
      final userMsg = _webShutterInitErrorMessage(e);
      if (mounted) {
        setState(() {
          _guidanceSub = userMsg;
          _webShutterReady = false;
          _webShutterInitializing = false;
          _webShutterInitStarted = false;
          _webCameraStartTapped = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMsg), duration: const Duration(seconds: 8)),
        );
      }
    }
  }

  Future<void> _init() async {
    debugPrint('[TUTORIAL_CAM] init start');
    final cams = await availableCameras();
    final front = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );

    // Web では低解像度で初期化を試行（成功率向上）
    final resolution = kIsWeb ? ResolutionPreset.low : ResolutionPreset.medium;
    final c = CameraController(
      front,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await c.initialize();
      _controller = c;
      if (mounted) setState(() {});
      debugPrint('[TUTORIAL_CAM] init ok previewSize=${c.value.previewSize}');
      await _startStream();
    } catch (e, stack) {
      debugPrint('[TUTORIAL_CAM] init failed: $e');
      debugPrint('[TUTORIAL_CAM] stack: ${stack?.toString().split("\n").take(5).join("\n")}');
      if (mounted) {
        setState(() {
          _guidanceSub = kIsWeb ? 'カメラ初期化に失敗しました。Webでは「画像をアップロード」をご利用ください。' : 'カメラ初期化に失敗しました。権限と接続を確認してください。';
        });
        if (!kIsWeb) {
          Future.delayed(Duration.zero, () {
            if (!mounted) return;
            PermissionService.showOpenSettingsDialog(
              context,
              title: 'カメラの使用許可が必要です',
              message: '設定から「Kami Face Oracle」のカメラを許可してください。',
            );
          });
        }
      }
    }
  }

  Future<void> _startStream() async {
    final c = _controller;
    if (c == null || _streaming) return;
    _streaming = true;

    debugPrint('[TUTORIAL_CAM] startImageStream called');
    await c.startImageStream((image) async {
      if (!_streaming || _detecting || _capturing) return;
      _detecting = true;

      try {
        final input = _toInputImage(image, c.description.sensorOrientation);
        _lastImageSize = input.metadata?.size;

        final faces = await _detector.processImage(input);
        debugPrint('[TUTORIAL_CAM] ✅ faces=${faces.length}');

        // 顔検出の詳細ログ
        if (faces.isEmpty) {
          final size = input.metadata?.size;
          debugPrint('[TUTORIAL_CAM] ⚠️ 顔が検出されませんでした');
          debugPrint(
              '[TUTORIAL_CAM] InputImage: size=${size?.width}x${size?.height}, rotation=${input.metadata?.rotation}, format=${input.metadata?.format}, bytesPerRow=${input.metadata?.bytesPerRow}');
        } else {
          debugPrint('[TUTORIAL_CAM] 顔検出成功: ${faces.length}個');
          for (int i = 0; i < faces.length; i++) {
            final f = faces[i];
            final bbox = f.boundingBox;
            debugPrint(
                '[TUTORIAL_CAM] 顔$i: bbox=(${bbox.left.toStringAsFixed(1)}, ${bbox.top.toStringAsFixed(1)}, ${bbox.width.toStringAsFixed(1)}x${bbox.height.toStringAsFixed(1)}), yaw=${f.headEulerAngleY?.toStringAsFixed(1)}, pitch=${f.headEulerAngleX?.toStringAsFixed(1)}, roll=${f.headEulerAngleZ?.toStringAsFixed(1)}');
          }
        }

        _faces = faces;

        // 自動シャッター条件を更新
        _updateAutoCaptureByState(faces);

        if (mounted) setState(() {});
      } catch (e, stackTrace) {
        debugPrint('[TUTORIAL_CAM] ❌ process failed: $e');
        debugPrint('[TUTORIAL_CAM] StackTrace: ${stackTrace.toString().split("\n").take(3).join("\n")}');
        // エラー時も空のリストでsetStateを呼ぶ
        _faces = [];
        if (mounted) setState(() {});
      } finally {
        _detecting = false;
      }
    });
  }

  Future<void> _stopStream() async {
    final c = _controller;
    _streaming = false;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) {
        await c.stopImageStream();
        debugPrint('[TUTORIAL_CAM] stopImageStream ok');
      }
    } catch (e) {
      debugPrint('[TUTORIAL_CAM] stopImageStream failed: $e');
    }
  }

  InputImageRotation _rotationFromSensorOrientation(int sensorOrientation, {CameraLensDirection? lensDirection}) {
    // フロントカメラで縦向き固定の場合、sensorOrientationに基づいて回転を設定
    // 画像サイズは元のまま（720x480）を使用し、回転で正しい向きにする
    final isFrontCamera = lensDirection == CameraLensDirection.front ||
        _controller?.description.lensDirection == CameraLensDirection.front;

    if (isFrontCamera) {
      // フロントカメラの場合、sensorOrientationに基づいて回転を設定
      // 縦向き固定でフロントカメラの場合、通常は270度回転が必要
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

    // バックカメラの場合はsensorOrientationに基づいて回転を設定
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
    final lensDirection = _controller?.description.lensDirection;
    final rotation = _rotationFromSensorOrientation(sensorOrientation, lensDirection: lensDirection);
    final isFrontCamera = lensDirection == CameraLensDirection.front;

    // 画像サイズは元のまま使用（回転で正しい向きにする）
    final imageWidth = image.width;
    final imageHeight = image.height;

    debugPrint(
        '[TUTORIAL_CAM] image format: ${image.format.group}, planes: ${image.planes.length}, size: ${image.width}x${image.height}');
    debugPrint('[TUTORIAL_CAM] isFrontCamera=$isFrontCamera, rotation=$rotation, size: ${imageWidth}x${imageHeight}');

    // Android: NV21形式を組み立て
    if (image.format.group == ImageFormatGroup.nv21 && image.planes.length >= 2) {
      final yPlane = image.planes[0];
      final uvPlane = image.planes[1];

      debugPrint(
          '[TUTORIAL_CAM] NV21: yPlane=${yPlane.bytes.length}, uvPlane=${uvPlane.bytes.length}, yBytesPerRow=${yPlane.bytesPerRow}');

      // NV21: Y平面 + UV平面（インタリーブ形式）
      final bytes = Uint8List(yPlane.bytes.length + uvPlane.bytes.length);
      bytes.setRange(0, yPlane.bytes.length, yPlane.bytes);
      bytes.setRange(yPlane.bytes.length, bytes.length, uvPlane.bytes);

      final metadata = InputImageMetadata(
        size: Size(imageWidth.toDouble(), imageHeight.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: imageWidth, // 実際の画像幅を使用（パディングを考慮しない）
      );

      debugPrint(
          '[TUTORIAL_CAM] NV21 InputImage: size=${metadata.size}, rotation=$rotation, bytesPerRow=${metadata.bytesPerRow}, totalBytes=${bytes.length}');

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
      debugPrint(
          '[TUTORIAL_CAM] BGRA8888 InputImage: size=${metadata.size}, rotation=$rotation, bytesPerRow=${metadata.bytesPerRow}');
      return InputImage.fromBytes(bytes: plane.bytes, metadata: metadata);
    }

    // YUV420形式の場合（3プレーン: Y, U, V → NV21形式に変換）
    if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length >= 3) {
      debugPrint('[TUTORIAL_CAM] YUV420 detected, converting to NV21');
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      // NV21形式: Y平面 + UVインタリーブ平面
      // パディングを除去して正しいサイズで構築
      final imageWidth = image.width;
      final imageHeight = image.height;

      // Y平面のサイズ（パディングなし）
      final ySize = imageWidth * imageHeight;
      // UV平面のサイズ（VUインタリーブ、パディングなし）
      final uvSize = (imageWidth * imageHeight) ~/ 2;

      final bytes = Uint8List(ySize + uvSize);

      // Y平面をコピー（パディングを除去）
      final yBytesPerRow = yPlane.bytesPerRow;
      for (int y = 0; y < imageHeight; y++) {
        final srcOffset = y * yBytesPerRow;
        final dstOffset = y * imageWidth;
        bytes.setRange(dstOffset, dstOffset + imageWidth, yPlane.bytes, srcOffset);
      }

      // UとVをインタリーブしてUV平面を作成（パディングを除去）
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
            bytes[ySize + uvIndex] = vPlane.bytes[vIndex]; // V
            bytes[ySize + uvIndex + 1] = uPlane.bytes[uIndex]; // U
          }
        }
      }

      // InputImageのサイズは元の画像サイズを使用（回転で正しい向きにする）
      // bytesPerRowは実際の画像幅を使用（パディングを考慮しない）
      final metadata = InputImageMetadata(
        size: Size(imageWidth.toDouble(), imageHeight.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: imageWidth, // 実際の画像幅を使用（パディングを考慮しない）
      );

      debugPrint('[TUTORIAL_CAM] YUV420→NV21: size=${metadata.size.width}x${metadata.size.height}, rotation=$rotation');
      debugPrint(
          '[TUTORIAL_CAM] YUV420→NV21: bytes=${bytes.length}, bytesPerRow=${metadata.bytesPerRow} (yPlane.bytesPerRow=${yPlane.bytesPerRow}), ySize=$ySize, uvSize=$uvSize');

      // サイズ検証（元の画像サイズで計算）
      final expectedBytes = imageWidth * imageHeight * 3 ~/ 2; // NV21形式: Y平面 + UV平面
      if (bytes.length != expectedBytes) {
        debugPrint('[TUTORIAL_CAM] ⚠️ バイト数が一致しません: actual=${bytes.length}, expected=$expectedBytes');
        debugPrint('[TUTORIAL_CAM] ⚠️ 差分: ${bytes.length - expectedBytes} bytes');
      } else {
        debugPrint('[TUTORIAL_CAM] ✅ バイト数が一致しました');
      }

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    }

    // フォールバック: 最初のプレーンを使用
    debugPrint('[TUTORIAL_CAM] ⚠️ Unknown format, using first plane as fallback');
    final bytes = image.planes.first.bytes;
    final metadata = InputImageMetadata(
      size: Size(imageWidth.toDouble(), imageHeight.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: image.planes.first.bytesPerRow,
    );
    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Rect _guideRect(Size view) {
    final w = view.width * 0.78;
    final h = view.height * 0.42;
    return Rect.fromLTWH((view.width - w) / 2, (view.height - h) / 2, w, h);
  }

  // 顔向き判定を総合スコア方式に変更
  // headEulerAngle が null の場合は「データなし」として満点扱い（Web等で角度が出ない場合に自動シャッターが切れるようにする）
  double _calculateFaceScore(Face f) {
    double score = 0.0;
    final yawVal = f.headEulerAngleY;
    final pitchVal = f.headEulerAngleX;
    final rollVal = f.headEulerAngleZ;

    void addScore(double? val) {
      if (val == null) {
        score += 1.0; // データなし＝ブロックしない
        return;
      }
      final abs = val.abs();
      if (abs < 8)
        score += 1.0;
      else if (abs < 15) score += 0.5;
    }

    addScore(yawVal);
    addScore(pitchVal);
    addScore(rollVal);
    return score;
  }

  bool _isFrontalFace(Face f) {
    // 総合スコア方式：3項目中2.5以上で合格（多少のズレは許容）
    final score = _calculateFaceScore(f);
    return score >= 2.5;
  }

  // 顔の向きの問題点を取得（指示文用）。角度が null の場合は指示を出さない
  String? _getFaceOrientationIssue(Face f) {
    final yaw = f.headEulerAngleY;
    final pitch = f.headEulerAngleX;
    final roll = f.headEulerAngleZ;
    if (yaw == null && pitch == null && roll == null) return null;
    final yawAbs = (yaw ?? 0).abs();
    final pitchAbs = (pitch ?? 0).abs();
    final rollAbs = (roll ?? 0).abs();
    if (yawAbs > 10) {
      final yawValue = f.headEulerAngleY ?? 0;
      return yawValue > 0 ? '顔を左に向けてください（右を向いています）' : '顔を右に向けてください（左を向いています）';
    } else if (pitchAbs > 10) {
      final pitchValue = f.headEulerAngleX ?? 0;
      return pitchValue > 0 ? '顔を下に向けてください（上を向いています）' : '顔を上に向けてください（下を向いています）';
    } else if (rollAbs > 10) {
      return '顔を正面に向けてください（顔が傾いています）';
    }
    return null;
  }

  bool _eyesOpen(Face f) {
    final l = f.leftEyeOpenProbability ?? 0.0;
    final r = f.rightEyeOpenProbability ?? 0.0;

    // デバッグログ
    debugPrint('[EYES] left=${l.toStringAsFixed(2)} right=${r.toStringAsFixed(2)}');

    // 端末や環境で取れない場合もあるので、取れないなら緩和して true にする運用も可
    if (l == 0.0 && r == 0.0) {
      debugPrint('[EYES] データが取れないため、緩和してtrueを返します');
      return true; // データが取れない場合は緩和
    }
    // さらに緩和: 0.5 → 0.3（目が少し開いていればOK）
    final result = l >= 0.3 && r >= 0.3;
    debugPrint('[EYES] 判定結果: $result');
    return result;
  }

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

    // 顔向き判定を総合スコア方式に変更
    final faceScore = _calculateFaceScore(face);
    debugPrint('[FACE] faceScore=$faceScore');

    if (faceScore < 2.5) {
      // 一番ズレている項目を優先して指示
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

    // ✅ 全条件OK - ガイダンスを最小限に
    _guidanceSub = null; // サブタイトルを非表示
    _shouldShowGuidance = false; // ガイダンス全体を非表示（進捗バーのみ表示）

    // 減点式：OKの時は増加、NGの時は減少（1フレームのブレで全リセットしない）
    _stableFrameCount++;
    _stableFrameCount = _stableFrameCount.clamp(0, _requiredStableFrames);
    _isReadyToCapture = _stableFrameCount >= _requiredStableFrames;

    debugPrint('[AUTO_SHOT] stable=$_stableFrameCount/$_requiredStableFrames (増加)');

    if (_isReadyToCapture) {
      _triggerAutoShutter();
    }
  }

  void _markNotReady() {
    // 減点式：NGの時は減少（全リセットしない）
    _stableFrameCount = (_stableFrameCount - 1).clamp(0, _requiredStableFrames);
    _isReadyToCapture = false;
    debugPrint('[AUTO_SHOT] stable=$_stableFrameCount/$_requiredStableFrames (減少)');
  }

  Future<void> _triggerAutoShutter() async {
    if (_capturing) return;

    _capturing = true;
    _stableFrameCount = 0;

    final c = _controller;
    if (c == null) {
      _capturing = false;
      return;
    }

    try {
      debugPrint('[AUTO_SHOT] FIRE');
      await _stopStream(); // 機種差対策
      final xFile = await c.takePicture();
      if (kIsWeb) {
        final bytes = await xFile.readAsBytes();
        final filename = xFile.name ?? 'tutorial_${widget.currentStep}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _onCapturedBytes(bytes, filename);
      } else {
        await _onCaptured(xFile.path);
      }
      await _startStream();
    } catch (e) {
      debugPrint('[AUTO_SHOT] capture failed: $e');
      _guidanceSub = '撮影に失敗しました。もう一度お試しください';
      await _startStream();
    } finally {
      _capturing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _onCaptured(String path) async {
    if (!mounted) return;

    setState(() {
      _capturing = true;
    });

    try {
      final imageFile = io.File(path);

      // ファイルを保存
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'tutorial_${widget.currentStep}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = path_lib.join(directory.path, fileName);
      final targetFile = io.File(filePath);
      await imageFile.copy(targetFile.path);

      // 顔検出を再実行（高精度モード）
      final inputImage = InputImage.fromFilePath(targetFile.path);
      final options = FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        enableClassification: true,
        enableTracking: false,
        minFaceSize: 0.05,
        performanceMode: FaceDetectorMode.accurate, // 高精度モード
      );
      final accurateDetector = FaceDetector(options: options);
      final faces = await accurateDetector.processImage(inputImage);
      await accurateDetector.close();

      if (faces.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('顔が検出されませんでした。もう一度撮影してください')),
          );
          await _startStream();
          setState(() {
            _capturing = false;
          });
        }
        return;
      }

      // 肌分析（【B】SkinAnalysisService経由で実行）
      final skinResult = await SkinAnalysisService().analyzeSkin(targetFile, faces.first);

      // 性格診断を実行
      final personalityResult = await runDiagnosis(targetFile);

      // チュートリアル用の神を保存
      try {
        final detail = await PersonalityTypeDetailService.getDetail(personalityResult.personalityType);
        if (detail != null) {
          final pillarId = detail.pillarId.toLowerCase();
          final actualGod = deities.firstWhere(
            (d) => d.id.toLowerCase() == pillarId,
            orElse: () => deities.first,
          );
          await Storage.saveTutorialDeity(actualGod.id);
        }
      } catch (e) {
        debugPrint('[TutorialCameraPage] チュートリアル神の保存エラー: $e');
      }

      // 簡易特徴量
      final face = faces.first;
      final smile = face.smilingProbability ?? 0.5;
      final eyeOpen = ((face.leftEyeOpenProbability ?? 0.5) + (face.rightEyeOpenProbability ?? 0.5)) / 2.0;
      final gloss = skinResult.brightness.clamp(0.0, 1.0);
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

      if (!mounted) return;

      // RevealPageに遷移（画像パスと顔検出結果を渡す）
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RevealPage(
            god: null,
            features: features,
            skin: skinResult,
            beautyScore: null,
            praise: personalityResult.personalityDescription,
            isTutorial: true,
            deityMeta: {
              'title': personalityResult.personalityTypeName,
              'trait': personalityResult.personalityDescription,
              'message': personalityResult.personalityDescription,
            },
            personalityDiagnosisResult: personalityResult,
            tutorialImagePath: targetFile.path, // 画像パスを渡す
            tutorialDetectedFaces: faces, // 顔検出結果を渡す
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('[TutorialCameraPage] 画像処理エラー: $e');
      debugPrint('[TutorialCameraPage] スタックトレース: ${stackTrace.toString().split("\n").take(10).join("\n")}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('処理中にエラーが発生しました: $e')),
        );
        await _startStream();
        setState(() {
          _capturing = false;
        });
      }
    }
  }

  /// Web／bytes 用: 自動シャッター後の処理（パスを使わない）
  /// Web では ML Kit は使わず、正面判定はサーバー /validate_face（MediaPipe）のみ。ここでは診断実行と結果表示のみ。
  Future<void> _onCapturedBytes(Uint8List bytes, String filename) async {
    if (!mounted) return;
    setState(() {
      _capturing = true;
    });
    try {
      // Web: ML Kit を使わない。サーバーが MediaPipe で正面判定済み（またはスキップ）なので、診断のみ実行する。
      if (kIsWeb) {
        final skinResult = SkinAnalysisResult(
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
        final personalityResult = await runDiagnosisBytes(bytes, filename);
        try {
          final detail = await PersonalityTypeDetailService.getDetail(personalityResult.personalityType);
          if (detail != null) {
            final pillarId = detail.pillarId.toLowerCase();
            final actualGod = deities.firstWhere(
              (d) => d.id.toLowerCase() == pillarId,
              orElse: () => deities.first,
            );
            await Storage.saveTutorialDeity(actualGod.id);
          }
        } catch (e) {
          debugPrint('[TutorialCameraPage] チュートリアル神の保存エラー: $e');
        }
        final features = FaceFeatures(0.5, 0.5, 0.5, 0.5, 0.5);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RevealPage(
              god: null,
              features: features,
              skin: skinResult,
              beautyScore: null,
              praise: personalityResult.personalityDescription,
              isTutorial: true,
              deityMeta: {
                'title': personalityResult.personalityTypeName,
                'trait': personalityResult.personalityDescription,
                'message': personalityResult.personalityDescription,
              },
              personalityDiagnosisResult: personalityResult,
              tutorialImagePath: null,
              tutorialImageBytes: bytes,
              tutorialDetectedFaces: <Face>[], // Web: 正面判定はサーバー MediaPipe のみ。ML Kit は使わないので顔オーバーレイなし。
            ),
          ),
        );
        return;
      }

      // モバイル: ML Kit で顔検出し、肌分析・診断・結果表示
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;
      final byteData = await uiImage.toByteData(format: ImageByteFormat.rawRgba);
      if (byteData == null) throw Exception('画像のバイトデータ変換に失敗しました');
      final rgba = byteData.buffer.asUint8List();
      final bgra = Uint8List.fromList(rgba);
      for (int i = 0; i < bgra.length; i += 4) {
        if (i + 3 < bgra.length) {
          final r = bgra[i];
          bgra[i] = bgra[i + 2];
          bgra[i + 2] = r;
        }
      }
      final inputImage = InputImage.fromBytes(
        bytes: bgra,
        metadata: InputImageMetadata(
          size: Size(uiImage.width.toDouble(), uiImage.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: uiImage.width * 4,
        ),
      );
      uiImage.dispose();
      final accurateDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableContours: true,
          enableLandmarks: true,
          enableClassification: true,
          enableTracking: false,
          minFaceSize: 0.05,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );
      final faces = await accurateDetector.processImage(inputImage);
      await accurateDetector.close();
      if (faces.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('顔が検出されませんでした。もう一度撮影してください')),
          );
          await _startStream();
          setState(() {
            _capturing = false;
          });
        }
        return;
      }
      final path = await getTempImagePathFromBytes(bytes);
      final SkinAnalysisResult skinResult;
      if (path != null) {
        skinResult = await SkinAnalysisService().analyzeSkin(io.File(path), faces.first);
      } else {
        skinResult = SkinAnalysisResult(
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
      final personalityResult = await runDiagnosisBytes(bytes, filename);
      try {
        final detail = await PersonalityTypeDetailService.getDetail(personalityResult.personalityType);
        if (detail != null) {
          final pillarId = detail.pillarId.toLowerCase();
          final actualGod = deities.firstWhere(
            (d) => d.id.toLowerCase() == pillarId,
            orElse: () => deities.first,
          );
          await Storage.saveTutorialDeity(actualGod.id);
        }
      } catch (e) {
        debugPrint('[TutorialCameraPage] チュートリアル神の保存エラー: $e');
      }
      final face = faces.first;
      final smile = face.smilingProbability ?? 0.5;
      final eyeOpen = ((face.leftEyeOpenProbability ?? 0.5) + (face.rightEyeOpenProbability ?? 0.5)) / 2.0;
      final gloss = skinResult.brightness.clamp(0.0, 1.0);
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
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RevealPage(
            god: null,
            features: features,
            skin: skinResult,
            beautyScore: null,
            praise: personalityResult.personalityDescription,
            isTutorial: true,
            deityMeta: {
              'title': personalityResult.personalityTypeName,
              'trait': personalityResult.personalityDescription,
              'message': personalityResult.personalityDescription,
            },
            personalityDiagnosisResult: personalityResult,
            tutorialImagePath: null,
            tutorialImageBytes: bytes,
            tutorialDetectedFaces: faces,
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('[TutorialCameraPage] _onCapturedBytes エラー: $e');
      debugPrint('[TutorialCameraPage] ${stackTrace.toString().split("\n").take(10).join("\n")}');
      if (mounted) {
        String message = '診断の送信に失敗しました。もう一度撮影してください。';
        final es = e.toString();
        if (es.contains('TimeoutException') || es.contains('timed out') || es.contains('タイムアウト')) {
          message = 'サーバーが応答しません。同じWi‑Fiかネットワークを確認し、しばらく待ってからもう一度撮影してください。';
        } else if (es.contains('CONSENT_REQUIRED') || es.contains('403')) {
          message = '同意が未登録です。最初に生体データ同意で「I Agree」をタップしてください。';
        } else if (es.contains('Failed to load') ||
            es.contains('CORS') ||
            es.contains('XMLHttpRequest') ||
            es.contains('Connection refused') ||
            es.contains('SocketException') ||
            es.contains('Connection')) {
          message = 'サーバーに接続できません。ネットワークを確認するか、時間をおいてもう一度撮影してください。';
        } else if (es.contains('サーバーエラー') || es.contains('server_inference') || es.contains('STOP_HERE')) {
          message = '診断サーバーでエラーが発生しました。しばらく待ってからもう一度撮影してください。';
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
        if (!kIsWeb || _controller != null) await _startStream();
        setState(() {
          _capturing = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
        });
      }
    }
  }

  /// E2E時: カメラなしで「撮影シミュレーション中」を表示（1.5秒後に自動で診断→結果へ）
  Widget _buildE2EPlaceholder() {
    return Scaffold(
      key: const Key('e2e-camera-screen'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('真顔の写真を撮影'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 24),
            Text(
              'E2E: 撮影シミュレーション中...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  /// E2E専用: 疑似撮影→モック診断→RevealPageへ（顔検出・実APIなし）
  Future<void> _onCapturedBytesE2E() async {
    if (!mounted) return;
    setState(() {
      _capturing = true;
    });
    try {
      final bytes = Uint8List.fromList(E2E.minimalJpegBytes);
      final personalityResult = await runDiagnosisBytes(bytes, 'e2e.jpg');
      final features = FaceFeatures(0.5, 0.5, 0.5, 0.5, 0.5);
      final skinResult = SkinAnalysisResult(
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
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RevealPage(
            god: null,
            features: features,
            skin: skinResult,
            beautyScore: null,
            praise: personalityResult.personalityDescription,
            isTutorial: true,
            deityMeta: {
              'title': personalityResult.personalityTypeName,
              'trait': personalityResult.personalityDescription,
              'message': personalityResult.personalityDescription,
            },
            personalityDiagnosisResult: personalityResult,
            tutorialImagePath: null,
            tutorialImageBytes: bytes,
            tutorialDetectedFaces: null,
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('[TutorialCameraPage] _onCapturedBytesE2E エラー: $e');
      debugPrint(stackTrace.toString().split('\n').take(5).join('\n'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('E2E診断エラー: $e'), duration: const Duration(seconds: 4)),
        );
        setState(() {
          _capturing = false;
        });
      }
    } finally {
      if (mounted)
        setState(() {
          _capturing = false;
        });
    }
  }

  /// Web 簡易カメラ（getUserMedia 主体）の UI。HTTPS・権限エラー時は案内＋再試行を表示。
  Widget _buildWebSimpleCameraBody() {
    final ctrl = _webSimpleController;
    if (ctrl == null) return _buildWebShutterBody();

    if (!_webSimpleViewRegistered) {
      _webSimpleViewRegistered = true;
      registerWebCameraViewFactory();
    }

    final error = ctrl.lastError;
    final isReady = ctrl.isReady;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.currentStep == 'neutral' ? '真顔で撮影' : '笑顔で撮影'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(child: buildWebCameraView()),
          if (!_webSimpleStartTapped)
            Material(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'カメラの許可が必要です',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '下の「カメラを開始」をタップし、「許可」を選んでください。',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      button: true,
                      label: 'カメラを開始する。ダブルタップでカメラを有効にします。',
                      child: ElevatedButton.icon(
                        key: const Key('camera-start-button'),
                        onPressed: () async {
                          setState(() {
                            _webSimpleStartTapped = true;
                            _webSimpleStarting = true;
                          });
                          await ctrl.start(kWebCameraVideoElementId);
                          if (!mounted) return;
                          setState(() {
                            _webSimpleStarting = false;
                          });
                        },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('カメラを開始'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_webSimpleStarting)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('カメラを準備しています…', style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            )
          else if (error != null)
            Material(
              color: Colors.black87,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        error.message,
                        key: const Key('error-message'),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      if (error == WebCameraError.notSecureContext) ...[
                        const SizedBox(height: 12),
                        Text(
                          '現在: ${Uri.base.origin}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (error == WebCameraError.permissionDenied) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'カメラの許可が必要です',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '【Chrome（Android）】\nアドレスバー左の鍵マーク（または「i」）をタップ\n→「サイトの設定」→「カメラ」を「許可」に',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '【Safari（iPhone）】\n設定 → Safari → カメラ → 許可\nまたは 設定 → プライバシー → カメラ',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '変更後、下の「再試行」を押してください。',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      Semantics(
                        button: true,
                        label: '再試行。カメラの許可後にダブルタップで再度カメラを開始します。',
                        child: ElevatedButton.icon(
                          key: const Key('retry-button'),
                          onPressed: () async {
                            setState(() {
                              _webSimpleStarting = true;
                            });
                            await ctrl.start(kWebCameraVideoElementId);
                            if (!mounted) return;
                            setState(() {
                              _webSimpleStarting = false;
                            });
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('再試行'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (isReady) ...[
            // Web: 顔を入れるガイド枠（ML Kit なしでも表示）
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _WebFaceGuidePainter(),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    button: true,
                    label: _capturing ? '処理中' : '撮影する。ダブルタップで写真を撮ります。',
                    child: ElevatedButton.icon(
                      key: const Key('capture-button'),
                      onPressed: _capturing
                          ? null
                          : () async {
                              setState(() {
                                _capturing = true;
                              });
                              try {
                                List<int> list;
                                try {
                                  list = await ctrl.captureJpegBytes(quality: 0.85);
                                } catch (captureErr) {
                                  if (!mounted) return;
                                  await Future.delayed(const Duration(milliseconds: 500));
                                  if (!mounted) return;
                                  list = await ctrl.captureJpegBytes(quality: 0.85);
                                }
                                final bytes = Uint8List.fromList(list);
                                final filename =
                                    'tutorial_${widget.currentStep}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                // Web: 正面判定は行わず、キャプチャ成功したらそのまま診断へ（撮影失敗を減らす）
                                await _onCapturedBytes(bytes, filename);
                              } catch (e, st) {
                                debugPrint('[TutorialCameraPage] 撮影失敗: $e');
                                debugPrint('[TutorialCameraPage] ${st?.toString().split("\n").take(3).join("\n")}');
                                if (mounted) {
                                  final msg = _webCaptureErrorMessage(e);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
                                  );
                                }
                              } finally {
                                if (mounted)
                                  setState(() {
                                    _capturing = false;
                                  });
                              }
                            },
                      icon: Icon(_capturing ? Icons.hourglass_empty : Icons.camera_alt),
                      label: Text(_capturing ? '処理中...' : '撮影'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWebShutterBody() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.currentStep == 'neutral' ? '真顔の写真を撮影' : '笑顔の写真を撮影'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(child: buildWebShutterCameraView()),
          if (!_webCameraStartTapped)
            Material(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Webではカメラをタップで開始します',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      button: true,
                      label: 'カメラを開始する。ダブルタップでカメラと顔検出を有効にします。',
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() => _webCameraStartTapped = true);
                          if (!_webShutterInitStarted) {
                            _webShutterInitStarted = true;
                            _initWebShutter();
                          }
                        },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('カメラを開始'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_webShutterInitializing)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('顔検出とカメラを準備しています…', style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            )
          else
            ValueListenableBuilder<WebShutterState?>(
              valueListenable: WebShutterService.instance.state,
              builder: (context, ws, _) {
                final reason = ws?.reason ?? '';
                final progress01 = ws?.progress01 ?? 0.0;
                final countingDown = ws?.countingDown ?? false;
                final countdownProgress = ws?.countdownProgress ?? 0.0;
                final subtitle = _webFaceMeshReady && (_guidanceSub ?? '').isNotEmpty
                    ? _guidanceSub
                    : (reason.isNotEmpty ? reason : ((_guidanceSub ?? '').isEmpty ? null : _guidanceSub));
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    TutorialGuidanceOverlay(
                      title: _guidanceTitle,
                      subtitle: subtitle,
                      isReady: countingDown,
                      progress01: countingDown ? countdownProgress : progress01,
                      showImage: reason.isNotEmpty,
                      compact: reason.isEmpty,
                    ),
                    _buildWebShutterDebugStrip(ws),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Semantics(
                            button: true,
                            label: '手動で撮影する。ダブルタップで写真を撮影します。',
                            child: TextButton.icon(
                              onPressed: _webBurstInProgress || _capturing
                                  ? null
                                  : () async {
                                      final dataUrl = await FaceMeshWebBridge.captureOneFrame(_webVideoElementId);
                                      if (dataUrl == null || dataUrl.isEmpty || !mounted) return;
                                      try {
                                        final comma = dataUrl.indexOf(',');
                                        final base64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
                                        final bytes = base64Decode(base64);
                                        final filename =
                                            'tutorial_${widget.currentStep}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                        await _onCapturedBytes(bytes, filename);
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(content: Text('撮影に失敗しました: $e')));
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.camera_alt, color: Colors.white),
                              label: const Text('手動で撮影', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildWebShutterDebugStrip(WebShutterState? ws) {
    if (ws == null) return const SizedBox.shrink();
    final d = ws.debug;
    final faceCount = d['faceCount'] as int? ?? 0;
    final yaw = (d['yaw'] as num?)?.toDouble() ?? 0.0;
    final pitch = (d['pitch'] as num?)?.toDouble() ?? 0.0;
    final roll = (d['roll'] as num?)?.toDouble() ?? 0.0;
    final brightness = (d['brightness'] as num?)?.toDouble() ?? 0.0;
    final motion = (d['motion'] as num?)?.toDouble() ?? 0.0;
    return Positioned(
      left: 8,
      right: 8,
      top: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '顔: $faceCount | PITCH: ${pitch.toStringAsFixed(1)}° ROLL: ${roll.toStringAsFixed(1)}° YAW: ${yaw.toStringAsFixed(1)}°\n'
          '明るさ: ${brightness.toStringAsFixed(2)} | ブレ: ${motion.toStringAsFixed(2)} | stable: ${ws.stableCount}/${ws.stableFramesRequired}',
          style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_e2eMode) return _buildE2EPlaceholder();
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      // Web: 自動シャッター復元 — MediaPipe Face Landmarker 経路（shutter_engine.js）を優先
      if (kIsWeb) return _buildWebShutterBody();
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.currentStep == 'neutral' ? '真顔の写真を撮影' : '笑顔の写真を撮影'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final previewSize = c.value.previewSize!;
    final imageSizeForView = Size(previewSize.height, previewSize.width); // 回転対策

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.currentStep == 'neutral' ? '真顔の写真を撮影' : '笑顔の写真を撮影'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, cs) {
            final viewSize = Size(cs.maxWidth, cs.maxHeight);
            final guide = _guideRect(viewSize);

            // 回転を考慮した画像サイズを計算
            // rotation270degの場合、画像サイズを入れ替える（720x480 → 480x720）
            final rawImageSize = _lastImageSize ?? imageSizeForView;
            final sensorOrientation = c.description.sensorOrientation;
            final imageSize = (sensorOrientation == 90 || sensorOrientation == 270)
                ? Size(rawImageSize.height, rawImageSize.width) // 90度または270度回転の場合、サイズを入れ替え
                : rawImageSize;

            debugPrint(
                '[TUTORIAL_CAM] transform: rawImageSize=${rawImageSize.width}x${rawImageSize.height}, sensorOrientation=$sensorOrientation, imageSize=${imageSize.width}x${imageSize.height}, viewSize=${viewSize.width}x${viewSize.height}');

            final transform = PreviewTransform(
              imageSize: imageSize,
              viewSize: viewSize,
              isFrontCamera: c.description.lensDirection == CameraLensDirection.front,
            );

            // 新しい条件判定は_updateAutoCaptureByStateで行われるため、ここでは不要

            return Stack(
              fit: StackFit.expand,
              children: [
                // ✅ 横長崩れ対策：BoxFit.coverで統一（centerCrop）
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

                // ガイダンスオーバーレイ（最前面）- 必要な時だけ表示
                if (_shouldShowGuidance || _isReadyToCapture)
                  TutorialGuidanceOverlay(
                    title: _shouldShowGuidance ? _guidanceTitle : '',
                    subtitle: _guidanceSub,
                    isReady: _isReadyToCapture,
                    progress01: _stableFrameCount / _requiredStableFrames,
                    showImage: _shouldShowGuidance, // 画像は必要な時だけ
                    compact: !_shouldShowGuidance, // 全条件OKの時はコンパクト表示
                  ),

                if (_debug)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'faces=${_faces.length} stable=$_stableFrameCount/$_requiredStableFrames\n'
                        'vertical=${_poseGate.deviceIsVertical} still=${_poseGate.deviceIsStill}\n'
                        'pitch=${_poseGate.pitchDeg.toStringAsFixed(1)}° roll=${_poseGate.rollDeg.toStringAsFixed(1)}°\n'
                        'preview=${previewSize.width.toStringAsFixed(0)}x${previewSize.height.toStringAsFixed(0)} imageSize=${imageSize.width.toStringAsFixed(0)}x${imageSize.height.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Web カメラ用の顔ガイド枠（ML Kit なしで中央に枠だけ表示）
class _WebFaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const margin = 0.15;
    final rect = Rect.fromLTWH(
      size.width * margin,
      size.height * (margin + 0.05),
      size.width * (1 - 2 * margin),
      size.height * (1 - 2 * margin - 0.1),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.orange.withOpacity(0.9);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(24)), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
