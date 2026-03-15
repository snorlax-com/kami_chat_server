import 'package:flutter/material.dart';

class TutorialGuidanceOverlay extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isReady;
  final double progress01; // 0..1 stable frames progress
  final bool showImage; // 画像を表示するか
  final bool compact; // コンパクト表示モード

  const TutorialGuidanceOverlay({
    super.key,
    required this.title,
    this.subtitle,
    required this.isReady,
    required this.progress01,
    this.showImage = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    // コンパクト表示（全条件OK時）
    if (compact) {
      return IgnorePointer(
        ignoring: true,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20, left: 40, right: 40),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isReady ? Colors.greenAccent : Colors.white24,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: progress01.clamp(0.0, 1.0),
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isReady ? Colors.greenAccent : Colors.white70,
                      ),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    if (isReady) ...[
                      const SizedBox(height: 6),
                      Text(
                        'OKです。そのまま動かないでください',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 通常表示（問題がある時）
    return IgnorePointer(
      ignoring: true,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
            child: Container(
              width: w * 0.85, // 幅をさらに縮小: 0.9 → 0.85
              padding: const EdgeInsets.all(10), // パディングをさらに縮小
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isReady ? Colors.greenAccent : Colors.white24,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // image（必要な時だけ）
                  if (showImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/guides/sit_phone_forward.png',
                        height: 80, // さらに縮小: 120 → 80
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Icon(Icons.phone_android, color: Colors.white70, size: 40),
                            ),
                          );
                        },
                      ),
                    ),
                  if (showImage) const SizedBox(height: 6),

                  // text（タイトルは非表示、サブタイトルのみ）
                  if (subtitle != null) ...[
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13, // 少し大きくして見やすく
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // progress
                  LinearProgressIndicator(
                    value: progress01.clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isReady ? Colors.greenAccent : Colors.white70,
                    ),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
