import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';

/// 瞑想シーン（特定の神の瞑想音楽を再生）
class MeditationScene extends StatefulWidget {
  final Deity deity;
  final int durationMinutes; // 瞑想時間（分）

  const MeditationScene({
    super.key,
    required this.deity,
    this.durationMinutes = 5,
  });

  @override
  State<MeditationScene> createState() => _MeditationSceneState();
}

class _MeditationSceneState extends State<MeditationScene> with TickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _bellPlayer = AudioPlayer(); // ベル音用の別プレイヤー
  late final AnimationController _breathController;
  late final AnimationController _glowController;
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _isPlaying = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.durationMinutes * 60;

    // オーディオプレイヤーの初期設定（ノイズ防止のため）
    _configureAudioPlayer();

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // 自動的に瞑想を開始
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _start();
    });
  }

  /// オーディオプレイヤーの設定（ノイズ防止）
  Future<void> _configureAudioPlayer() async {
    try {
      // メディアプレイヤーモードに設定（低レイテンシ）
      await _player.setPlayerMode(PlayerMode.mediaPlayer);

      // Android用のAudioContext設定（ノイズ低減）
      await _player.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: [
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.duckOthers,
          ],
        ),
      ));
    } catch (e) {
      // AudioContext設定の失敗は無視（一部のプラットフォームでサポートされていない場合）
      // エミュレーターでは一部の設定が無視される場合があります
      print('AudioContext setting error (ignored): $e');
    }
  }

  Future<void> _playBell(int count) async {
    // ベル音を指定回数再生
    for (int i = 0; i < count; i++) {
      try {
        await _bellPlayer.play(AssetSource('sounds/bell-a-99888.mp3'));
        await _bellPlayer.onPlayerComplete.first; // 再生完了を待つ
        if (i < count - 1) {
          // 最後の1回以外は少し間隔を開ける
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        // ベル音再生エラーは無視
        print('Bell play error: $e');
      }
    }
  }

  Future<void> _start() async {
    if (_isPlaying) return;
    setState(() => _isPlaying = true);

    // 瞑想音楽を再生するので、BGMを一時停止
    BackgroundMusicService().pauseForOtherSound();

    // 瞑想開始時にベルを3回鳴らす（完了を待つ）
    await _playBell(3);

    try {
      // オーディオプレイヤーの設定はinitStateで完了している
      // 再生前のバッファリングを待つ（ノイズ防止のため少し待機）
      await Future.delayed(const Duration(milliseconds: 150));

      // 瞑想音楽を再生（アセットから）
      // まずMP3形式を試行（ユーザーが作成したBGMを優先）、なければWAVを試行
      try {
        await _player.setReleaseMode(ReleaseMode.loop); // ループ再生に設定（再生前）
        await _player.setVolume(0.8); // ボリューム設定
        await _player.play(AssetSource('sounds/meditation/${widget.deity.id}.mp3'));

        // 再生開始後、少し待ってから状態を確認（ノイズ防止）
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        // MP3がない場合はWAVを試行
        try {
          await _player.setReleaseMode(ReleaseMode.loop); // ループ再生に設定（再生前）
          await _player.setVolume(0.8); // ボリューム設定
          await _player.play(AssetSource('sounds/meditation/${widget.deity.id}.wav'));

          // 再生開始後、少し待ってから状態を確認（ノイズ防止）
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e2) {
          // 音楽ファイルがない場合は無音で続行
          print('Meditation music file not found: ${e2}');
        }
      }
    } catch (e) {
      // 音楽再生エラーは無視
      print('Meditation music play error: $e');
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds <= 1) {
          _remainingSeconds = 0;
          _complete();
          timer.cancel();
        } else {
          _remainingSeconds--;
        }
      });
    });
  }

  Future<void> _pause() async {
    _timer?.cancel();
    await _player.pause();
    setState(() => _isPlaying = false);
  }

  Future<void> _complete() async {
    _timer?.cancel();
    await _player.stop();
    setState(() {
      _isPlaying = false;
      _completed = true;
    });

    // 瞑想完了ボーナスを保存
    try {
      await CloudService.saveDailyRecord({
        'meditation': {
          'deity': widget.deity.id,
          'minutes': widget.durationMinutes,
          'completedAt': DateTime.now().toIso8601String(),
        },
        'boost': {
          'type': 'calm',
          'value': 0.1, // 運気+10%
          'duration': widget.durationMinutes,
        },
      });
    } catch (e) {
      // エラーは無視
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('瞑想完了！${widget.deity.nameJa}の加護を受けました✨'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.stop();
    _player.dispose();
    _bellPlayer.stop();
    _bellPlayer.dispose();
    _breathController.dispose();
    _glowController.dispose();
    // 瞑想音楽が終了したので、BGMを再開
    BackgroundMusicService().resumeAfterOtherSound();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(widget.deity.colorHex.replaceFirst('#', '0xff')));
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 背景：神のシンボル（大きく、薄く）
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  colors: [
                    color.withValues(alpha: 0.25),
                    color.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black,
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                  radius: 1.5,
                ),
              ),
              child: Center(
                child: Opacity(
                  opacity: 0.15, // 非常に薄く
                  child: Image.asset(
                    widget.deity.symbolAsset,
                    width: size.width * 0.8,
                    height: size.width * 0.8,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),

          // 背景グラデーション（動的）
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, _) {
              final pulse = (math.sin(_glowController.value * 2 * math.pi) + 1) / 2;
              final wave1 = math.sin(_glowController.value * 2 * math.pi * 0.7);
              final wave2 = math.cos(_glowController.value * 2 * math.pi * 0.5);

              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      wave1 * 0.2,
                      wave2 * 0.2,
                    ),
                    colors: [
                      color.withValues(alpha: 0.35 * (0.6 + pulse * 0.4)),
                      color.withValues(alpha: 0.15 * (0.5 + pulse * 0.5)),
                      color.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black87,
                    ],
                    stops: const [0.0, 0.3, 0.5, 0.8, 1.0],
                    radius: 1.8,
                  ),
                ),
              );
            },
          ),

          // パーティクル効果（光の粒）
          AnimatedBuilder(
            animation: _glowController,
            builder: (context, _) {
              return CustomPaint(
                painter: _ParticlePainter(color, _glowController.value),
                size: size,
              );
            },
          ),

          // メインコンテンツ
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 神のシンボル（呼吸アニメーション + 回転アニメーション）
                  AnimatedBuilder(
                    animation: Listenable.merge([_breathController, _glowController]),
                    builder: (context, _) {
                      final breathScale = 1.0 + (_breathController.value * 0.15);
                      final rotation = _glowController.value * 360 * 0.1; // ゆっくり回転（10%のみ）
                      final glowIntensity = 0.5 + (math.sin(_glowController.value * 2 * math.pi) * 0.3).abs();

                      return Transform.rotate(
                        angle: rotation * math.pi / 180,
                        child: Transform.scale(
                          scale: breathScale,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // 外側のグローリング（複数層）
                              for (int i = 0; i < 3; i++)
                                Container(
                                  width: size.width * (0.5 + i * 0.1),
                                  height: size.width * (0.5 + i * 0.1),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        color.withValues(alpha: glowIntensity * (0.3 - i * 0.1)),
                                        color.withValues(alpha: glowIntensity * (0.15 - i * 0.05)),
                                        Colors.transparent,
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withValues(alpha: glowIntensity * 0.4),
                                        blurRadius: 30 + i * 10,
                                        spreadRadius: 5 + i * 5,
                                      ),
                                    ],
                                  ),
                                ),
                              // メインシンボル
                              Container(
                                padding: const EdgeInsets.all(40),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      color.withValues(alpha: 0.6),
                                      color.withValues(alpha: 0.3),
                                      color.withValues(alpha: 0.1),
                                      Colors.transparent,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.6),
                                      blurRadius: 50,
                                      spreadRadius: 15,
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  widget.deity.symbolAsset,
                                  width: size.width * 0.4,
                                  height: size.width * 0.4,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.self_improvement,
                                    size: size.width * 0.3,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 40),

                  // 神の名前
                  Text(
                    '【${widget.deity.nameJa}】',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: color,
                      letterSpacing: 2,
                      shadows: [
                        Shadow(
                          color: color.withValues(alpha: 0.8),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    widget.deity.role,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                  ),

                  const SizedBox(height: 60),

                  // 残り時間
                  if (!_completed) ...[
                    Text(
                      _formatTime(_remainingSeconds),
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 40),
                  ] else ...[
                    Icon(
                      Icons.check_circle,
                      size: 64,
                      color: color,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '瞑想完了',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],

                  const SizedBox(height: 60),

                  // コントロールボタン
                  if (!_completed) ...[
                    if (!_isPlaying)
                      ElevatedButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('瞑想を開始'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      )
                    else ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _pause,
                            icon: const Icon(Icons.pause),
                            label: const Text('一時停止'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white24,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              _player.stop();
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.stop),
                            label: const Text('終了'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent.withValues(alpha: 0.7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ] else
                    ElevatedButton(
                      onPressed: () {
                        _player.stop();
                        Navigator.pop(context);
                      },
                      child: const Text('閉じる'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// パーティクルペインター（光の粒を描画）
class _ParticlePainter extends CustomPainter {
  final Color color;
  final double time;

  _ParticlePainter(this.color, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final random = math.Random(42);

    // 画面全体に散らばる光の粒
    for (int i = 0; i < 20; i++) {
      final baseX = random.nextDouble();
      final baseY = random.nextDouble();
      final x = (baseX + time * 0.1) % 1.0;
      final y = (baseY + time * 0.15) % 1.0;

      final twinkle = (math.sin(time * 2 * math.pi + i * 0.5) + 1) / 2;
      final opacity = 0.2 + twinkle * 0.4;
      final radius = 2 + twinkle * 3;

      paint.color = color.withValues(alpha: opacity);
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
