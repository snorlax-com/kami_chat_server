import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_criteria_page.dart';

class TutorialDeityDetailPage extends StatefulWidget {
  final Deity deity;

  const TutorialDeityDetailPage({
    super.key,
    required this.deity,
  });

  @override
  State<TutorialDeityDetailPage> createState() => _TutorialDeityDetailPageState();
}

class _TutorialDeityDetailPageState extends State<TutorialDeityDetailPage> with TickerProviderStateMixin {
  late final AnimationController _bgController;
  late final AnimationController _fadeController;
  Map<String, dynamic>? _detailData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final color = Color(int.parse(widget.deity.colorHex.replaceFirst('#', '0xff')));

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _loadDetailData();
    _fadeController.forward();
  }

  Future<void> _loadDetailData() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/data/gods_detail.json');
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final deityKey = widget.deity.id.substring(0, 1).toUpperCase() + widget.deity.id.substring(1);
      _detailData = data[deityKey] as Map<String, dynamic>?;
    } catch (e) {
      _detailData = null;
    }
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(widget.deity.colorHex.replaceFirst('#', '0xff')));
    final size = MediaQuery.of(context).size;
    final details = _detailData?['details'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: color),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline, color: color),
            tooltip: '判断基準を見る',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TutorialCriteriaPage(),
                ),
              );
            },
          ),
        ],
      ),
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
              opacity: _fadeController,
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 20),

                            // 神のシンボル
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    color.withOpacity(0.4),
                                    color.withOpacity(0.1),
                                    Colors.transparent,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withOpacity(0.5),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                widget.deity.symbolAsset,
                                height: 100,
                                width: 100,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.auto_awesome,
                                  size: 80,
                                  color: color.withOpacity(0.8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 神の名前とタイトル
                            Text(
                              '【${widget.deity.nameJa}】',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: color.withOpacity(0.9),
                                letterSpacing: 2,
                                shadows: [
                                  Shadow(
                                    color: color.withOpacity(0.8),
                                    blurRadius: 15,
                                  ),
                                  const Shadow(
                                    color: Colors.black87,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_detailData?['title'] != null)
                              Text(
                                _detailData!['title'] as String,
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white70,
                                  letterSpacing: 1,
                                ),
                              ),
                            const SizedBox(height: 40),

                            // 詳細セクション
                            if (details != null) ...[
                              _buildDetailSection(
                                '顔に現れる印象',
                                details['impression'] as String? ?? '',
                                color,
                              ),
                              const SizedBox(height: 24),
                              _buildDetailSection(
                                '内面',
                                details['inner'] as String? ?? '',
                                color,
                              ),
                              const SizedBox(height: 24),
                              _buildDetailSection(
                                '行動傾向',
                                details['behavior'] as String? ?? '',
                                color,
                              ),
                              const SizedBox(height: 24),
                              _buildDetailSection(
                                '人との関わり方',
                                details['relationship'] as String? ?? '',
                                color,
                              ),
                            ],

                            const SizedBox(height: 40),

                            // 閉じるボタン
                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
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
                                onPressed: () => Navigator.pop(context),
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

  Widget _buildDetailSection(String title, String content, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
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
            color: color.withOpacity(0.2),
            blurRadius: 15,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color.withOpacity(0.9),
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withOpacity(0.9),
                  color.withOpacity(0.7),
                  Colors.white,
                ],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(bounds);
            },
            child: Text(
              content,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w300,
                height: 1.8,
                letterSpacing: 1.5,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: color.withOpacity(0.6),
                    blurRadius: 10,
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
