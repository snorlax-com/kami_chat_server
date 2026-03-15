import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/ui/widgets/deity_card.dart';
import 'package:kami_face_oracle/ui/pages/face_tutorial_screen.dart';

class TutorialYosenPage extends StatelessWidget {
  const TutorialYosenPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('陽占（チュートリアル）')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              key: const Key('e2e-start-face'),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const FaceTutorialScreen()));
              },
              icon: const Icon(Icons.face),
              label: const Text('顔認識を開始'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: deities.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => DeityCard(god: deities[i]),
            ),
          ),
        ],
      ),
    );
  }
}
