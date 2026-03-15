import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deity.dart';

class DeityCard extends StatelessWidget {
  final Deity god;

  const DeityCard({super.key, required this.god});

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(god.colorHex.replaceFirst('#', '0xff')));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Image.asset(
            god.symbolAsset,
            width: 40,
            height: 40,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              print('[DeityCard] 画像読み込みエラー: ${god.symbolAsset}');
              print('[DeityCard] エラー詳細: $error');
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.image_not_supported, size: 24, color: Colors.grey[600]),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(god.nameJa, style: Theme.of(context).textTheme.titleMedium),
                Text(god.role, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
