import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/ui/widgets/meditation_deity_music_list.dart';

/// 18柱それぞれの瞑想音楽の試聴と、本番瞑想（タイマー付き）への導線。
class MeditationPage extends StatelessWidget {
  const MeditationPage({super.key, this.embedInShell = false});

  final bool embedInShell;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ListView(
        children: const [
          Text('18柱の瞑想音楽', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SizedBox(height: 4),
          Text(
            '柱順（診断タイプ1〜18）に並んでいます。試聴ボタンは音楽のループ再生、人型アイコンでタイマー付きの本番瞑想に入れます。',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          SizedBox(height: 8),
          MeditationDeityMusicList(deities: deities, defaultFullSessionMinutes: 5),
        ],
      ),
    );

    if (embedInShell) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('瞑想')),
      body: body,
    );
  }
}
