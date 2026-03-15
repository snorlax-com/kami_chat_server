import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/core/deities.dart';

class DeityCompatibilityPage extends StatefulWidget {
  final Deity currentDeity;

  const DeityCompatibilityPage({
    super.key,
    required this.currentDeity,
  });

  @override
  State<DeityCompatibilityPage> createState() => _DeityCompatibilityPageState();
}

class _DeityCompatibilityPageState extends State<DeityCompatibilityPage> with TickerProviderStateMixin {
  late final AnimationController _bgController;
  late final AnimationController _fadeController;
  Map<String, dynamic>? _compatibilityData;

  @override
  void initState() {
    super.initState();
    _loadCompatibilityData();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  Future<void> _loadCompatibilityData() async {
    try {
      final String response = await rootBundle.loadString('assets/data/deity_compatibility.json');
      final data = json.decode(response) as Map<String, dynamic>;
      setState(() {
        _compatibilityData = data[widget.currentDeity.id] as Map<String, dynamic>?;
      });
    } catch (e) {
      // エラー時は相性データなしとして扱う
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Deity? _findDeityById(String id) {
    try {
      return deities.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(widget.currentDeity.colorHex.replaceFirst('#', '0xff')));
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 背景グラデーション
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
          // メインコンテンツ
          SafeArea(
            child: FadeTransition(
              opacity: _fadeController,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // タイトル
                    Text(
                      '💫 あなたに降臨した神',
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white70,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '【${widget.currentDeity.nameJa}】',
                      style: TextStyle(
                        fontSize: 32,
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
                    const SizedBox(height: 40),

                    // 相性情報
                    if (_compatibilityData != null) ...[
                      // 相性が良い神
                      if (_compatibilityData!['good'] != null && (_compatibilityData!['good'] as List).isNotEmpty) ...[
                        _buildCompatibilitySection(
                          title: '✨ 相性の良い神',
                          compatibilityList: _compatibilityData!['good'] as List,
                          isGood: true,
                          color: color,
                        ),
                        const SizedBox(height: 32),
                      ],

                      // 相性が悪い神
                      if (_compatibilityData!['bad'] != null && (_compatibilityData!['bad'] as List).isNotEmpty) ...[
                        _buildCompatibilitySection(
                          title: '⚡ 相性の悪い神',
                          compatibilityList: _compatibilityData!['bad'] as List,
                          isGood: false,
                          color: color,
                        ),
                        const SizedBox(height: 32),
                      ],
                    ] else ...[
                      const Text(
                        '相性情報を読み込めませんでした',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],

                    // 閉じるボタン
                    ElevatedButton(
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
                        Navigator.pop(context);
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompatibilitySection({
    required String title,
    required List compatibilityList,
    required bool isGood,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isGood ? Colors.lightGreenAccent : Colors.orangeAccent,
            letterSpacing: 1,
            shadows: [
              Shadow(
                color: (isGood ? Colors.lightGreenAccent : Colors.orangeAccent).withOpacity(0.8),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...compatibilityList.map((comp) {
          final compData = comp as Map<String, dynamic>;
          final deityId = compData['id'] as String;
          final deityName = compData['name'] as String;
          final reason = compData['reason'] as String;
          final deity = _findDeityById(deityId);

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isGood
                    ? [
                        Colors.lightGreenAccent.withOpacity(0.1),
                        Colors.greenAccent.withOpacity(0.05),
                      ]
                    : [
                        Colors.orangeAccent.withOpacity(0.1),
                        Colors.redAccent.withOpacity(0.05),
                      ],
              ),
              border: Border.all(
                color: (isGood ? Colors.lightGreenAccent : Colors.orangeAccent).withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isGood ? Colors.lightGreenAccent : Colors.orangeAccent).withOpacity(0.2),
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
                    if (deity != null) ...[
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (isGood ? Colors.lightGreenAccent : Colors.orangeAccent).withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.asset(
                            deity.symbolAsset,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              isGood ? Icons.favorite : Icons.warning,
                              size: 32,
                              color: isGood ? Colors.lightGreenAccent : Colors.orangeAccent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deity?.nameJa ?? deityName,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isGood ? Colors.lightGreenAccent : Colors.orangeAccent,
                              shadows: [
                                Shadow(
                                  color: (isGood ? Colors.lightGreenAccent : Colors.orangeAccent).withOpacity(0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          if (deity != null)
                            Text(
                              deity.role,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white60,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    reason,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white70,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}
