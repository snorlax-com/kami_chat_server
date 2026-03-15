import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 神降臨エフェクト（光・風・星）
class DeityEffectsWidget extends StatefulWidget {
  final Color color;
  final bool showParticles;
  final Widget child;

  const DeityEffectsWidget({
    super.key,
    required this.color,
    required this.child,
    this.showParticles = false,
  });

  @override
  State<DeityEffectsWidget> createState() => _DeityEffectsWidgetState();
}

class _DeityEffectsWidgetState extends State<DeityEffectsWidget> with TickerProviderStateMixin {
  late AnimationController _lightController;
  late AnimationController _windController;
  late AnimationController _starController;
  late List<Particle> _particles;

  @override
  void initState() {
    super.initState();
    _lightController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _windController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _starController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // 光粒パーティクルを初期化
    _particles = List.generate(
      20,
      (i) => Particle(
        x: math.Random().nextDouble(),
        y: math.Random().nextDouble(),
        size: math.Random().nextDouble() * 4 + 2,
        speed: math.Random().nextDouble() * 0.02 + 0.01,
      ),
    );
  }

  @override
  void dispose() {
    _lightController.dispose();
    _windController.dispose();
    _starController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 光のエフェクト
        AnimatedBuilder(
          animation: _lightController,
          builder: (context, child) {
            return CustomPaint(
              painter: LightPainter(
                color: widget.color,
                progress: _lightController.value,
              ),
              child: Container(),
            );
          },
        ),
        // 風のエフェクト
        AnimatedBuilder(
          animation: _windController,
          builder: (context, child) {
            return CustomPaint(
              painter: WindPainter(
                color: widget.color,
                progress: _windController.value,
              ),
              child: Container(),
            );
          },
        ),
        // 星のエフェクト
        AnimatedBuilder(
          animation: _starController,
          builder: (context, child) {
            return CustomPaint(
              painter: StarPainter(
                color: widget.color,
                progress: _starController.value,
              ),
              child: Container(),
            );
          },
        ),
        // 光粒パーティクル（肌ツヤ上昇時）
        if (widget.showParticles)
          CustomPaint(
            painter: ParticlePainter(
              particles: _particles,
              color: widget.color,
            ),
            child: Container(),
          ),
        // メインコンテンツ
        widget.child,
      ],
    );
  }
}

/// 光のエフェクト（放射状の光線）
class LightPainter extends CustomPainter {
  final Color color;
  final double progress;

  LightPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.3 * (1 - progress.abs()))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.max(size.width, size.height);

    // 放射状の光線
    for (int i = 0; i < 8; i++) {
      final angle = (i * math.pi / 4) + (progress * math.pi * 2);
      final startRadius = maxRadius * 0.3;
      final endRadius = maxRadius * 0.8;

      final startX = center.dx + math.cos(angle) * startRadius;
      final startY = center.dy + math.sin(angle) * startRadius;
      final endX = center.dx + math.cos(angle) * endRadius;
      final endY = center.dy + math.sin(angle) * endRadius;

      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(LightPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// 風のエフェクト（曲線的な流れ）
class WindPainter extends CustomPainter {
  final Color color;
  final double progress;

  WindPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 風の流れ（波状の線）
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final y = (size.height / 6) * (i + 1);
      path.moveTo(0, y);
      for (double x = 0; x < size.width; x += 10) {
        final wave = math.sin((x / size.width * 4 * math.pi) + (progress * math.pi * 2)) * 10;
        path.lineTo(x, y + wave);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WindPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// 星のエフェクト（キラキラ）
class StarPainter extends CustomPainter {
  final Color color;
  final double progress;

  StarPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    final random = math.Random(42); // 固定シードで一貫性のある配置
    final starCount = 15;

    for (int i = 0; i < starCount; i++) {
      final x = (random.nextDouble() * size.width);
      final y = (random.nextDouble() * size.height);

      // 星の点滅効果
      final opacity = (math.sin(progress * math.pi * 2 + i) + 1) / 2;
      paint.color = color.withOpacity(0.6 * opacity);

      // 星を描画（十字型）
      final starSize = 4 + random.nextDouble() * 4;
      _drawStar(canvas, Offset(x, y), starSize, paint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final angle = (i * 4 * math.pi / 5) - (math.pi / 2);
      final x = center.dx + math.cos(angle) * size;
      final y = center.dy + math.sin(angle) * size;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(StarPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// 光粒パーティクル
class Particle {
  double x;
  double y;
  double size;
  double speed;
  double angle;

  Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
  }) : angle = math.Random().nextDouble() * math.pi * 2;
}

/// パーティクルペインター
class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final Color color;

  ParticlePainter({required this.particles, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final particle in particles) {
      // パーティクルの位置を更新
      particle.x += math.cos(particle.angle) * particle.speed;
      particle.y += math.sin(particle.angle) * particle.speed;

      // 画面外に出たらリセット
      if (particle.x < 0 || particle.x > 1 || particle.y < 0 || particle.y > 1) {
        particle.x = math.Random().nextDouble();
        particle.y = math.Random().nextDouble();
        particle.angle = math.Random().nextDouble() * math.pi * 2;
      }

      // パーティクルを描画
      paint.color = color.withOpacity(0.7);
      canvas.drawCircle(
        Offset(particle.x * size.width, particle.y * size.height),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(ParticlePainter oldDelegate) {
    return true; // 常に再描画（アニメーションのため）
  }
}
