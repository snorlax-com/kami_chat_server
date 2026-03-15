import 'dart:math' as math;
import 'dart:async';
import 'dart:typed_data';
import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';
import 'package:kami_face_oracle/skin_analysis.dart';
import 'package:kami_face_oracle/ui/pages/result_page.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_comment_page.dart';
import 'package:kami_face_oracle/ui/pages/radar_chart_page.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_result_page.dart';
import 'package:kami_face_oracle/ui/pages/skin_diagnosis_result_page.dart';
import 'package:kami_face_oracle/core/tutorial_classifier.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/ui/pages/personality_diagnosis_result_page.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/services/skin_analysis_ai_service.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';
import 'package:kami_face_oracle/face_painter.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/core/e2e_web_signal.dart';

class RevealPage extends StatefulWidget {
  final Deity? god; // オプショナルに変更（personalityDiagnosisResultから取得する場合があるため）
  final FaceFeatures features;
  final SkinAnalysisResult? skin;
  final double? beautyScore;
  final String? praise;
  final bool isTutorial;
  final Map<String, dynamic>? deityMeta; // チュートリアル用性格診断データ
  final SkinAIDiagnosisResult? aiDiagnosisResult; // ✅ AI診断結果
  final TutorialDiagnosisResult? diagnosisResult; // チュートリアル判断結果（旧）
  final PersonalityTreeDiagnosisResult? personalityDiagnosisResult; // 新しい性格診断結果
  final String? tutorialImagePath; // チュートリアル用画像パス（モバイル）
  final Uint8List? tutorialImageBytes; // チュートリアル用画像 bytes（Web／bytes 由来）
  final List<Face>? tutorialDetectedFaces; // チュートリアル用顔検出結果

  const RevealPage({
    super.key,
    this.god,
    required this.features,
    this.skin,
    this.beautyScore,
    this.praise,
    this.isTutorial = false,
    this.deityMeta,
    this.aiDiagnosisResult,
    this.diagnosisResult,
    this.personalityDiagnosisResult,
    this.tutorialImagePath,
    this.tutorialImageBytes,
    this.tutorialDetectedFaces,
  });

  @override
  State<RevealPage> createState() => _RevealPageState();
}

class _RevealPageState extends State<RevealPage> with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  final AudioPlayer _player = AudioPlayer();
  AudioPlayer? _meditationPlayer; // 瞑想音楽用
  bool _played = false;
  bool _showFinal = false;
  late final Animation<double> _spin; // ぐるぐる演出用
  Deity? _actualGod; // 実際に表示する神（サーバー結果から取得）

  // 顔輪郭アニメーション用
  ui.Image? _tutorialImage;
  late AnimationController _faceOutlineController;
  late AnimationController _leftEyeController;
  late AnimationController _rightEyeController;
  late AnimationController _leftEyebrowController;
  late AnimationController _rightEyebrowController;
  late AnimationController _noseController;
  late AnimationController _mouthController;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
    _scale = Tween(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.65, 1.0, curve: Curves.easeOutBack)));
    _opacity = Tween(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.65, 1.0, curve: Curves.easeIn)));
    _spin = Tween(begin: 0.0, end: 2 * 3.1415926535 * 2)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.easeInOut)));
    _ctrl.forward();

    // 顔輪郭アニメーション用コントローラー（チュートリアル用）
    if (widget.isTutorial && (widget.tutorialImagePath != null || widget.tutorialImageBytes != null)) {
      _faceOutlineController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2000), // ゆっくり
      );
      _leftEyeController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );
      _rightEyeController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );
      _leftEyebrowController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1000),
      );
      _rightEyebrowController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1000),
      );
      _noseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1000),
      );
      _mouthController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      );

      // 画像を読み込む
      _loadTutorialImage();
    }

    if (E2E.isEnabled) signalE2EResultShown();

    // サーバー結果から正しい神を取得
    _loadActualGod();

    // 最終表示フェーズへ（チュートリアルの場合はアニメーション完了後に表示）
    // チュートリアルモードでは、アニメーション完了後に_showFinalをtrueにするため、ここでは設定しない
    if (!widget.isTutorial || (widget.tutorialImagePath == null && widget.tutorialImageBytes == null)) {
      // 通常モードは2秒後
      Timer(const Duration(milliseconds: 2000), () {
        if (mounted) setState(() => _showFinal = true);
      });
    }
    // 効果音または瞑想音楽を再生
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_played) return;
      _played = true;

      // 性格診断結果がある場合は瞑想音楽を再生（柱降臨後の音楽）
      if (widget.personalityDiagnosisResult != null) {
        // 柱降臨後の音楽を優先するため、すべてのBGMを停止
        await _playMeditationMusic();
      } else {
        // 効果音を再生（一時停止のみ）
        BackgroundMusicService().pauseForOtherSound();
        try {
          await _player.stop();
          await _player.play(AssetSource('sounds/reveal.mp3'));
          _player.onPlayerComplete.listen((_) {
            BackgroundMusicService().resumeAfterOtherSound();
          });
        } catch (_) {
          BackgroundMusicService().resumeAfterOtherSound();
        }
      }
    });
  }

  Future<void> _loadTutorialImage() async {
    if (widget.tutorialImagePath == null && widget.tutorialImageBytes == null) return;

    try {
      final Uint8List bytes;
      if (widget.tutorialImageBytes != null) {
        bytes = widget.tutorialImageBytes!;
      } else {
        final file = io.File(widget.tutorialImagePath!);
        bytes = Uint8List.fromList(await file.readAsBytes());
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _tutorialImage = frame.image;

      if (mounted) {
        setState(() {});
        // 画像読み込み後にアニメーション開始
        await Future.delayed(const Duration(milliseconds: 500));
        _startFaceOutlineAnimation();
      }
    } catch (e) {
      print('[RevealPage] 画像読み込みエラー: $e');
    }
  }

  Future<void> _startFaceOutlineAnimation() async {
    if (!mounted || widget.tutorialDetectedFaces == null || widget.tutorialDetectedFaces!.isEmpty) return;

    // 全てのコントローラーをリセット
    _faceOutlineController.reset();
    _leftEyeController.reset();
    _rightEyeController.reset();
    _leftEyebrowController.reset();
    _rightEyebrowController.reset();
    _noseController.reset();
    _mouthController.reset();

    if (mounted) setState(() {});

    await Future.delayed(const Duration(milliseconds: 300));

    // 顔の輪郭アニメーション
    if (mounted) {
      await _faceOutlineController.forward();
    }

    // 目のアニメーション（同時に）
    if (mounted) {
      await Future.wait([
        _leftEyeController.forward(),
        _rightEyeController.forward(),
      ]);
    }

    // 眉のアニメーション（同時に）
    if (mounted) {
      await Future.wait([
        _leftEyebrowController.forward(),
        _rightEyebrowController.forward(),
      ]);
    }

    // 鼻のアニメーション
    if (mounted) {
      await _noseController.forward();
    }

    // 口のアニメーション
    if (mounted) {
      await _mouthController.forward();
    }

    // アニメーション完了後に神の降臨を表示
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _showFinal = true;
      });
    }
  }

  /// サーバー結果から正しい神を取得
  Future<void> _loadActualGod() async {
    if (widget.personalityDiagnosisResult != null) {
      // サーバー結果からpillarIdを取得
      final detail = await PersonalityTypeDetailService.getDetail(widget.personalityDiagnosisResult!.personalityType);
      if (detail != null) {
        final pillarId = detail.pillarId.toLowerCase();
        print(
            '[RevealPage] サーバー結果から神を取得: pillarId=$pillarId (type=${widget.personalityDiagnosisResult!.personalityType})');
        // pillarIdに基づいてDeityを取得
        try {
          _actualGod = deities.firstWhere(
            (d) => d.id.toLowerCase() == pillarId,
            orElse: () => widget.god ?? deities.first,
          );
          print('[RevealPage] 取得した神: ${_actualGod!.id} (${_actualGod!.nameJa})');
          if (mounted) setState(() {});
        } catch (e) {
          print('[RevealPage] ⚠️ 神の取得エラー: $e');
          _actualGod = widget.god ?? deities.first;
          if (mounted) setState(() {});
        }
      } else {
        print('[RevealPage] ⚠️ 詳細情報の取得に失敗');
        _actualGod = widget.god ?? deities.first;
      }
    } else {
      // サーバー結果がない場合は、渡されたgodを使用
      _actualGod = widget.god ?? deities.first;
    }
  }

  Future<void> _playMeditationMusic() async {
    try {
      // pillarIdを取得
      final detail = await PersonalityTypeDetailService.getDetail(widget.personalityDiagnosisResult!.personalityType);
      if (detail == null) return;

      final pillarId = detail.pillarId.toLowerCase();

      // BackgroundMusicServiceを使用して音楽を再生（一度だけ、継続再生）
      await BackgroundMusicService().playMeditationMusic(pillarId);
      print('[RevealPage] 瞑想音楽をBackgroundMusicServiceで再生: $pillarId');
    } catch (e) {
      print('[RevealPage] 瞑想音楽再生エラー: $e');
    }
  }

  @override
  void dispose() {
    // 瞑想音楽はBackgroundMusicServiceで管理されているため、ここでは停止しない
    // ホームに戻っても継続再生される
    _player.dispose();
    _ctrl.dispose();
    // 顔輪郭アニメーション用コントローラーを破棄
    if (widget.isTutorial && (widget.tutorialImagePath != null || widget.tutorialImageBytes != null)) {
      _faceOutlineController.dispose();
      _leftEyeController.dispose();
      _rightEyeController.dispose();
      _leftEyebrowController.dispose();
      _rightEyebrowController.dispose();
      _noseController.dispose();
      _mouthController.dispose();
    }
    _tutorialImage?.dispose();
    // 次のページで音楽が再生されるため、BGMは再開しない
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 実際に表示する神を決定（サーバー結果から取得した神、または渡された神）
    final god = _actualGod ?? widget.god ?? deities.first;
    final deityColor = Color(int.parse(god.colorHex.replaceFirst('#', '0xff')));
    // チュートリアルモードでは金色の神秘的な背景、通常モードでは神の色
    final bgColor = widget.isTutorial
        ? const Color(0xFFFFD700) // 金色
        : deityColor;
    final scaffold = Scaffold(
      key: const Key('e2e-result-screen'),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(
                          math.sin(_ctrl.value * 2 * math.pi) * 0.15,
                          math.cos(_ctrl.value * 2 * math.pi) * 0.15,
                        ),
                        colors: widget.isTutorial
                            ? [
                                // 金色の神秘的なグラデーション（強化版）
                                const Color(0xFFFFD700).withOpacity(0.4 * _opacity.value),
                                const Color(0xFFFFB300).withOpacity(0.25 * _opacity.value),
                                const Color(0xFFFF8C00).withOpacity(0.15 * _opacity.value),
                                const Color(0xFF8B5CF6).withOpacity(0.1 * _opacity.value),
                                Colors.black.withOpacity(0.9),
                                Colors.black,
                              ]
                            : [
                                // 神の色 + 神秘的な紫と青のグラデーション
                                bgColor.withOpacity(0.35 * _opacity.value),
                                const Color(0xFF8B5CF6).withOpacity(0.25 * _opacity.value),
                                const Color(0xFF06B6D4).withOpacity(0.15 * _opacity.value),
                                Colors.black.withOpacity(0.9),
                                Colors.black,
                              ],
                        radius: 0.9 + math.sin(_ctrl.value * 2 * math.pi) * 0.1,
                        stops:
                            widget.isTutorial ? const [0.0, 0.2, 0.4, 0.6, 0.85, 1.0] : const [0.0, 0.3, 0.5, 0.8, 1.0],
                      ),
                    ),
                  );
                },
              ),
            ),
            // ぐるぐる演出
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final size = MediaQuery.of(context).size;
                final radius = size.shortestSide * 0.42; // 画面全体を活用
                return IgnorePointer(
                  child: Opacity(
                    opacity: _showFinal ? 0.0 : 1.0,
                    child: Center(
                      child: SizedBox(
                        width: radius * 2 + 220,
                        height: radius * 2 + 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 光輪
                            Container(
                              width: radius * 1.6,
                              height: radius * 1.6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.08),
                                    Colors.white.withOpacity(0.0),
                                  ],
                                  stops: const [0.0, 1.0],
                                ),
                              ),
                            ),
                            for (int i = 0; i < deities.length; i++) ...[
                              Builder(builder: (_) {
                                final t = (i / deities.length) * 2 * 3.1415926535 + _spin.value;
                                final dx = radius * math.cos(t);
                                final dy = radius * math.sin(t);
                                final d = deities[i];
                                return Transform.translate(
                                  offset: Offset(dx, dy),
                                  child: Opacity(
                                    opacity: 0.9,
                                    child: Image.asset(d.symbolAsset, height: 96, width: 96, fit: BoxFit.contain),
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // チュートリアル用画像表示とアニメーション（神の降臨前のみ表示）
            if (widget.isTutorial && !_showFinal && _tutorialImage != null)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final imageSize = Size(_tutorialImage!.width.toDouble(), _tutorialImage!.height.toDouble());
                    final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
                    final imageAspect = imageSize.width / imageSize.height;
                    final viewAspect = viewSize.width / viewSize.height;
                    double displayWidth, displayHeight;
                    if (imageAspect > viewAspect) {
                      displayWidth = viewSize.width;
                      displayHeight = viewSize.width / imageAspect;
                    } else {
                      displayHeight = viewSize.height;
                      displayWidth = viewSize.height * imageAspect;
                    }
                    final hasFaces = widget.tutorialDetectedFaces != null && widget.tutorialDetectedFaces!.isNotEmpty;
                    return Center(
                      child: SizedBox(
                        width: displayWidth,
                        height: displayHeight,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: RawImage(
                                image: _tutorialImage,
                                fit: BoxFit.contain,
                              ),
                            ),
                            if (hasFaces)
                              Positioned.fill(
                                child: AnimatedBuilder(
                                  animation: Listenable.merge([
                                    _faceOutlineController,
                                    _leftEyeController,
                                    _rightEyeController,
                                    _leftEyebrowController,
                                    _rightEyebrowController,
                                    _noseController,
                                    _mouthController,
                                  ]),
                                  builder: (context, _) {
                                    return CustomPaint(
                                      painter: FacePainter(
                                        faces: widget.tutorialDetectedFaces!,
                                        faceOutlineProgress: _faceOutlineController.value,
                                        leftEyeProgress: _leftEyeController.value,
                                        rightEyeProgress: _rightEyeController.value,
                                        leftEyebrowProgress: _leftEyebrowController.value,
                                        rightEyebrowProgress: _rightEyebrowController.value,
                                        noseProgress: _noseController.value,
                                        mouthProgress: _mouthController.value,
                                        imageSize: imageSize,
                                      ),
                                    );
                                  },
                                ),
                              )
                            else
                              // Web など顔データがない場合: 中央に簡易の顔枠を表示
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _SimpleFaceFramePainter(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            // 最終表示（対象の神を強調）
            if (_showFinal)
              Center(
                child: ScaleTransition(
                  scale: _scale,
                  child: FadeTransition(
                    opacity: _opacity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // ハロー効果（チュートリアルでは神の色、通常では神の色）
                            Container(
                              width: MediaQuery.of(context).size.shortestSide * 0.72,
                              height: MediaQuery.of(context).size.shortestSide * 0.72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: widget.isTutorial
                                      ? [
                                          deityColor.withOpacity(.4),
                                          const Color(0xFFFFD700).withOpacity(.2),
                                          Colors.transparent,
                                        ]
                                      : [deityColor.withOpacity(.35), Colors.transparent],
                                  stops: widget.isTutorial ? const [0.0, 0.5, 1.0] : const [0.0, 1.0],
                                ),
                              ),
                            ),
                            Image.asset(
                              god.symbolAsset,
                              height: MediaQuery.of(context).size.shortestSide * 0.56,
                              width: MediaQuery.of(context).size.shortestSide * 0.56,
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '【${god.nameJa}】が降臨',
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          god.role,
                          style: TextStyle(color: Colors.white.withOpacity(.9)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  if (widget.isTutorial) {
                    // チュートリアルでは新しい性格診断結果ページへ
                    if (widget.personalityDiagnosisResult != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PersonalityDiagnosisResultPage(
                            diagnosisResult: widget.personalityDiagnosisResult!,
                          ),
                        ),
                      );
                    } else if (widget.diagnosisResult != null) {
                      // 旧診断結果がある場合（後方互換性）
                      final god = _actualGod ?? widget.god ?? deities.first;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TutorialResultPage(
                            diagnosisResult: widget.diagnosisResult!,
                            deity: god,
                            deityMeta: widget.deityMeta,
                            comment: widget.praise,
                          ),
                        ),
                      );
                    } else {
                      // 判断結果がない場合は直接性格診断ページへ
                      final god = _actualGod ?? widget.god ?? deities.first;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TutorialCommentPage(
                            deity: god,
                            comment: widget.praise,
                            deityMeta: widget.deityMeta,
                            diagnosisResult: widget.diagnosisResult,
                          ),
                        ),
                      );
                    }
                  } else {
                    // アニメーション後、肌診断結果ページを表示
                    final god = _actualGod ?? widget.god ?? deities.first;
                    if (widget.skin != null) {
                      // 新しい肌診断結果UIを表示
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SkinDiagnosisResultPage(
                            skinResult: widget.skin!,
                            diagnosisDate: DateTime.now(),
                          ),
                        ),
                      ).then((_) {
                        // 肌診断結果ページを閉じた後、RadarChartPageに遷移
                        if (mounted) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RadarChartPage(
                                skin: widget.skin!,
                                god: god,
                                features: widget.features,
                                beautyScore: widget.beautyScore,
                                praise: widget.praise,
                                aiDiagnosisResult: widget.aiDiagnosisResult,
                              ),
                            ),
                          );
                        }
                      });
                    } else {
                      // skinがnullの場合は既存のResultPageに遷移
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ResultPage(
                            god: god,
                            features: widget.features,
                            skin: widget.skin,
                            beautyScore: widget.beautyScore,
                            praise: widget.praise,
                            aiDiagnosisResult: widget.aiDiagnosisResult,
                          ),
                        ),
                      );
                    }
                  }
                },
                child: Text(widget.isTutorial ? '詳しく見る' : '肌トラブル診断を見る'),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      label: E2E.isEnabled ? 'e2e-result-screen' : '診断結果画面。性格診断と肌分析の結果を表示しています。',
      child: scaffold,
    );
  }
}

/// 顔データがない場合（Web 等）の簡易顔枠
class _SimpleFaceFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const margin = 0.18;
    final rect = Rect.fromLTWH(
      size.width * margin,
      size.height * (margin + 0.05),
      size.width * (1 - 2 * margin),
      size.height * (1 - 2 * margin - 0.1),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.orange.withOpacity(0.85);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20)), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
