import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/pages/meditation_scene.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';

/// 性格診断の柱順（type 1〜18）に合わせた神ID。瞑想BGMアセット名 `sounds/meditation/<id>.mp3` と一致。
const List<String> kMeditationDeityIdOrderPillar = <String>[
  'shisaru',
  'ragias',
  'shiran',
  'yatael',
  'amanoira',
  'tenkora',
  'kanonis',
  'yorusi',
  'tenmira',
  'amatera',
  'mimika',
  'sylna',
  'noirune',
  'skura',
  'fatemis',
  'delphos',
  'verdatsu',
  'osiria',
];

List<Deity> _deitiesInPillarOrder(List<Deity> all) {
  final byId = {for (final d in all) d.id: d};
  return kMeditationDeityIdOrderPillar
      .map((id) => byId[id])
      .whereType<Deity>()
      .toList();
}

/// 18柱分の瞑想音楽を一覧表示し、プレビュー再生と本番瞑想画面への遷移を提供する。
class MeditationDeityMusicList extends StatefulWidget {
  const MeditationDeityMusicList({
    super.key,
    required this.deities,
    this.defaultFullSessionMinutes = 5,
  });

  final List<Deity> deities;
  final int defaultFullSessionMinutes;

  @override
  State<MeditationDeityMusicList> createState() => _MeditationDeityMusicListState();
}

class _MeditationDeityMusicListState extends State<MeditationDeityMusicList> {
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _bellPlayer = AudioPlayer();
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  Future<void> _configure() async {
    try {
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _bellPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      final ctx = AudioContext(
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
      );
      await _player.setAudioContext(ctx);
      await _bellPlayer.setAudioContext(ctx);
    } catch (e) {
      debugPrint('[MeditationDeityMusicList] AudioContext: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    unawaited(_bellPlayer.dispose());
    if (_playingId != null) {
      unawaited(BackgroundMusicService().resumeAfterOtherSound());
    }
    super.dispose();
  }

  /// 本番瞑想ボタン押下直後: `sounds/bell-a-99888.mp3` を3回（間に短い間隔）
  Future<void> _playThreeBells() async {
    for (var i = 0; i < 3; i++) {
      try {
        await _bellPlayer.stop();
        await _bellPlayer.play(AssetSource('sounds/bell-a-99888.mp3'));
        await _bellPlayer.onPlayerComplete.first;
        if (i < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        debugPrint('[MeditationDeityMusicList] bell: $e');
      }
    }
  }

  Future<void> _stopPreview() async {
    await _player.stop();
    if (_playingId != null) {
      _playingId = null;
      await BackgroundMusicService().resumeAfterOtherSound();
    }
    if (mounted) setState(() {});
  }

  Future<void> _togglePreview(Deity d) async {
    if (_playingId == d.id) {
      await _stopPreview();
      return;
    }

    await _stopPreview();
    BackgroundMusicService().pauseForOtherSound();
    setState(() => _playingId = d.id);

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0.8);
      await _player.play(AssetSource('sounds/meditation/${d.id}.mp3'));
    } catch (e) {
      try {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.setVolume(0.8);
        await _player.play(AssetSource('sounds/meditation/${d.id}.wav'));
      } catch (e2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('音楽を読み込めませんでした: ${d.nameJa}')),
          );
        }
        await _stopPreview();
        return;
      }
    }

  }

  Future<void> _openFull(Deity d) async {
    await _stopPreview();
    if (!mounted) return;
    BackgroundMusicService().pauseForOtherSound();
    try {
      await _playThreeBells();
    } catch (e) {
      debugPrint('[MeditationDeityMusicList] pre-meditation bells: $e');
    }
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MeditationScene(
          deity: d,
          durationMinutes: widget.defaultFullSessionMinutes,
          playEntryBells: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _deitiesInPillarOrder(widget.deities);
    if (ordered.length != 18) {
      debugPrint('[MeditationDeityMusicList] 柱数想定18件: 実際は ${ordered.length}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < ordered.length; i++)
          _MeditationDeityRow(
            index: i + 1,
            deity: ordered[i],
            isPlaying: _playingId == ordered[i].id,
            onPreview: () => _togglePreview(ordered[i]),
            onFullSession: () => _openFull(ordered[i]),
            fullSessionMinutes: widget.defaultFullSessionMinutes,
          ),
      ],
    );
  }
}

class _MeditationDeityRow extends StatelessWidget {
  const _MeditationDeityRow({
    required this.index,
    required this.deity,
    required this.isPlaying,
    required this.onPreview,
    required this.onFullSession,
    required this.fullSessionMinutes,
  });

  final int index;
  final Deity deity;
  final bool isPlaying;
  final VoidCallback onPreview;
  final VoidCallback onFullSession;
  final int fullSessionMinutes;

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(deity.colorHex.replaceFirst('#', '0xff')));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white10,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              deity.symbolAsset,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(Icons.self_improvement, color: color),
            ),
          ),
        ),
        title: Text(
          '$index. 【${deity.nameJa}】',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: color,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          deity.role,
          style: const TextStyle(fontSize: 12, color: Colors.white60),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: isPlaying ? '停止' : '聴く',
              onPressed: onPreview,
              style: IconButton.styleFrom(
                backgroundColor: isPlaying ? color.withValues(alpha: 0.4) : Colors.white24,
                foregroundColor: Colors.white,
              ),
              icon: Icon(isPlaying ? Icons.stop : Icons.headphones),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '瞑想（$fullSessionMinutes分）',
              onPressed: onFullSession,
              icon: const Icon(Icons.self_improvement),
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}
