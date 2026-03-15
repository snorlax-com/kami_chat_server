import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  Map<String, int> _deityCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await CloudService.getDailyRecords(limit: 1000);
    final counts = <String, int>{};
    for (final r in records) {
      final deity = r['deity'] as String?;
      if (deity != null) {
        counts[deity] = (counts[deity] ?? 0) + 1;
      }
    }
    setState(() => _deityCounts = counts);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('神図鑑'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: deities.length,
        itemBuilder: (context, i) {
          final deity = deities[i];
          final count = _deityCounts[deity.id] ?? 0;
          final color = Color(int.parse(deity.colorHex.replaceFirst('#', '0xff')));
          return _DeityCard(
            deity: deity,
            count: count,
            onTap: () => _showDetail(context, deity, count),
          );
        },
      ),
    );
  }

  void _showDetail(BuildContext context, Deity deity, int count) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('【${deity.nameJa}】 ${deity.role}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Image.asset(
                deity.symbolAsset,
                height: 120,
                width: 120,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome, size: 96),
              ),
            ),
            const SizedBox(height: 12),
            Text('降臨回数: $count 回'),
            const SizedBox(height: 8),
            Text(
                '特徴: 表情${deity.expr == 1 ? '明' : '静'} / 肌${deity.skin == 1 ? '潤' : '乾'} / 骨格${deity.shape == 1 ? '直' : '丸'} / 主張${deity.claim == 1 ? '強' : '柔'}'),
            const SizedBox(height: 8),
            Text(deity.shortMessage, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
        ],
      ),
    );
  }
}

/// 神カードウィジェット（カード風の演出付き）
class _DeityCard extends StatefulWidget {
  final Deity deity;
  final int count;
  final VoidCallback onTap;
  const _DeityCard({
    required this.deity,
    required this.count,
    required this.onTap,
  });
  @override
  State<_DeityCard> createState() => _DeityCardState();
}

class _DeityCardState extends State<_DeityCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(widget.deity.colorHex.replaceFirst('#', '0xff')));

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: widget.onTap,
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: color.withOpacity(_glowAnimation.value),
                width: 2,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  colors: [
                    color.withOpacity(0.1 + _glowAnimation.value * 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 神のシンボル画像（グローエフェクト付き）
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.1),
                    ),
                    child: Image.asset(
                      widget.deity.symbolAsset,
                      height: 80,
                      width: 80,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome, size: 64),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 神の名前
                  Text(
                    '【${widget.deity.nameJa}】',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                  // 役割
                  Text(
                    widget.deity.role,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  // 降臨回数（バッジ風）
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '降臨: ${widget.count} 回',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
