import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_deity_detail_page.dart';
import 'package:kami_face_oracle/ui/pages/deity_compatibility_page.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_result_page.dart';
import 'package:kami_face_oracle/core/tutorial_classifier.dart';

class TutorialCommentPage extends StatefulWidget {
  final Deity deity;
  final String? comment;
  final Map<String, dynamic>? deityMeta; // 性格診断データ（title, trait, message）
  final TutorialDiagnosisResult? diagnosisResult; // 判断結果

  const TutorialCommentPage({
    super.key,
    required this.deity,
    this.comment,
    this.deityMeta,
    this.diagnosisResult,
  });

  @override
  State<TutorialCommentPage> createState() => _TutorialCommentPageState();
}

class _TutorialCommentPageState extends State<TutorialCommentPage> with TickerProviderStateMixin {
  late final AnimationController _bgController;
  late final AnimationController _textController;
  late final AnimationController _particleController;
  final List<_Particle> _particles = [];
  String _displayText = '';
  int _charIndex = 0;

  @override
  void initState() {
    super.initState();
    final color = Color(int.parse(widget.deity.colorHex.replaceFirst('#', '0xff')));

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();

    // パーティクル生成
    for (int i = 0; i < 30; i++) {
      _particles.add(_Particle(
        x: math.Random().nextDouble(),
        y: math.Random().nextDouble(),
        size: 2 + math.Random().nextDouble() * 3,
        speed: 0.2 + math.Random().nextDouble() * 0.3,
        color: color.withOpacity(0.3 + math.Random().nextDouble() * 0.4),
      ));
    }

    _textController.forward();
    _startTypingAnimation();
  }

  void _startTypingAnimation() {
    // 性格診断データから全文を作成
    final title = widget.deityMeta?['title'] ?? widget.deity.role;
    final trait = widget.deityMeta?['trait'] ?? '';
    final message = widget.comment ?? widget.deityMeta?['message'] ?? widget.deity.shortMessage;

    String fullText = '';
    if (title.isNotEmpty) {
      fullText += '【$title】\n\n';
    }
    if (trait.isNotEmpty) {
      fullText += 'あなたの性格: $trait\n\n';
    }
    fullText += message;

    Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (_charIndex < fullText.length && mounted) {
        setState(() {
          _displayText += fullText[_charIndex];
          _charIndex++;
        });
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _textController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(widget.deity.colorHex.replaceFirst('#', '0xff')));
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 神秘的な背景
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, _) {
              return Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      math.sin(_bgController.value * 2 * math.pi) * 0.3,
                      math.cos(_bgController.value * 2 * math.pi) * 0.3,
                    ),
                    colors: [
                      color.withOpacity(0.15),
                      color.withOpacity(0.05),
                      Colors.black,
                      Colors.black87,
                    ],
                    stops: const [0.0, 0.3, 0.6, 1.0],
                    radius: 1.5,
                  ),
                ),
              );
            },
          ),

          // 星空エフェクト
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, _) {
              return CustomPaint(
                painter: _StarPainter(_bgController.value),
                size: size,
              );
            },
          ),

          // パーティクル
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, _) {
              return CustomPaint(
                painter: _ParticlePainter(_particles, _particleController.value),
                size: size,
              );
            },
          ),

          // グロー効果
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  colors: [
                    color.withOpacity(0.2),
                    color.withOpacity(0.05),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                  radius: 1.0,
                ),
              ),
            ),
          ),

          // メインコンテンツ
          SafeArea(
            child: FadeTransition(
              opacity: _textController,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      // 神のシンボル（小さく）
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              color.withOpacity(0.3),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Image.asset(
                          widget.deity.symbolAsset,
                          height: 80,
                          width: 80,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.auto_awesome,
                            size: 64,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 神の名前と役割
                      Text(
                        '【${widget.deity.nameJa}】',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: color.withOpacity(0.9),
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                              color: color.withOpacity(0.8),
                              blurRadius: 12,
                            ),
                            const Shadow(
                              color: Colors.black87,
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.deity.role,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // コメントテキスト（神秘的なフォント風）
                      Container(
                        constraints: const BoxConstraints(
                          minHeight: 200,
                        ),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(0.1),
                              Colors.white.withOpacity(0.05),
                              Colors.transparent,
                            ],
                          ),
                          border: Border.all(
                            color: color.withOpacity(0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: AnimatedBuilder(
                          animation: _textController,
                          builder: (context, _) {
                            return ShaderMask(
                              shaderCallback: (bounds) {
                                return LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    color,
                                    color.withOpacity(0.8),
                                    Colors.white,
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ).createShader(bounds);
                              },
                              child: Text(
                                _displayText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w300,
                                  height: 1.8,
                                  letterSpacing: 2.5,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: color.withOpacity(0.8),
                                      blurRadius: 15,
                                      offset: const Offset(0, 0),
                                    ),
                                    Shadow(
                                      color: color.withOpacity(0.5),
                                      blurRadius: 30,
                                      offset: const Offset(0, 0),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ボタン行（相性を見る / さらに詳しく）
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.favorite, color: color),
                              label: const Text(
                                '相性を見る',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: color,
                                side: BorderSide(
                                  color: color.withOpacity(0.6),
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DeityCompatibilityPage(
                                      currentDeity: widget.deity,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.info_outline, color: color),
                              label: const Text(
                                '性格診断を見る',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: color,
                                side: BorderSide(
                                  color: color.withOpacity(0.6),
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              onPressed: () {
                                // 詳しい性格診断ページへ遷移
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TutorialDeityDetailPage(
                                      deity: widget.deity,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // 閉じるボタン
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color.withOpacity(0.8),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 48,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 8,
                          ),
                          onPressed: () {
                            // ホームまで戻る（降臨演出ページとコメントページを閉じる）
                            Navigator.popUntil(context, (route) => route.isFirst);
                          },
                          child: const Text(
                            '閉じる',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 星空ペインター
class _StarPainter extends CustomPainter {
  final double time;

  _StarPainter(this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final r = math.Random(42);
    for (int i = 0; i < 50; i++) {
      final x = r.nextDouble() * size.width;
      final y = r.nextDouble() * size.height;
      final twinkle = (math.sin(time * 2 * math.pi + i) + 1) / 2;
      paint.color = Colors.white.withOpacity(0.3 + twinkle * 0.4);
      canvas.drawCircle(Offset(x, y), 1 + twinkle * 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// パーティクルペインター
class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double time;

  _ParticlePainter(this.particles, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final y = (p.y + time * p.speed) % 1.0;
      final opacity = (math.sin(time * 2 * math.pi + p.x * 10) + 1) / 2;
      final paint = Paint()
        ..color = p.color.withOpacity(opacity * 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(p.x * size.width, y * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Particle {
  final double x;
  double y;
  final double size;
  final double speed;
  final Color color;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.color,
  });
}
