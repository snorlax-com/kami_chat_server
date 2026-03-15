import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

/// バックグラウンド音楽管理サービス
/// BGM3とBGM4を交互に再生し、他の効果音が優先される
class BackgroundMusicService {
  static final BackgroundMusicService _instance = BackgroundMusicService._internal();
  factory BackgroundMusicService() => _instance;
  BackgroundMusicService._internal();

  final AudioPlayer _bgmPlayer = AudioPlayer();
  bool _isBGMPlaying = false;
  bool _isOtherSoundPlaying = false; // 他の効果音が再生中か
  int _currentBGMIndex = 3; // 現在のBGM（3 or 4）
  StreamSubscription? _playerStateSubscription;
  Timer? _nextBGMTimer;
  String? _currentMeditationMusic; // 現在再生中の瞑想音楽
  bool _wasPlayingBeforePause = false; // 一時停止前に再生中だったか
  String? _pausedMeditationMusic; // 一時停止前の瞑想音楽
  bool _bgmAssetsMissing = false; // BGMファイルがない場合はログを1回だけ

  /// 初期化（アプリ起動時）
  Future<void> initialize() async {
    try {
      await _bgmPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _bgmPlayer.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient, // 他の音と共存
          options: [
            AVAudioSessionOptions.mixWithOthers,
            AVAudioSessionOptions.duckOthers,
          ],
        ),
      ));

      // 再生完了を監視して次のBGMに切り替え
      _playerStateSubscription = _bgmPlayer.onPlayerComplete.listen((_) {
        if (_isBGMPlaying && !_isOtherSoundPlaying) {
          _switchToNextBGM();
        }
      });

      // 最初のBGMを再生
      _startBGM();
    } catch (e) {
      debugPrint('[BackgroundMusicService] 初期化エラー: $e');
    }
  }

  /// BGMを開始（BGM3から開始）
  Future<void> _startBGM() async {
    if (_isOtherSoundPlaying) return; // 他の効果音が優先
    if (_bgmAssetsMissing) return; // アセットがない場合は試さない

    try {
      _currentBGMIndex = 3; // BGM3から開始
      await _playCurrentBGM();
    } catch (e) {
      debugPrint('[BackgroundMusicService] BGM開始エラー: $e');
    }
  }

  /// 現在のBGMを再生
  Future<void> _playCurrentBGM() async {
    if (_isOtherSoundPlaying) return; // 他の効果音が優先
    if (_currentMeditationMusic != null) return; // 瞑想音楽が再生中の場合は通常BGMを再生しない
    if (_bgmAssetsMissing) return;

    try {
      final bgmFile = 'sounds/bgm$_currentBGMIndex.mp3';
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop); // ループ再生
      await _bgmPlayer.setVolume(0.3); // ボリュームは控えめに（30%）
      await _bgmPlayer.play(AssetSource(bgmFile));
      _isBGMPlaying = true;
      debugPrint('[BackgroundMusicService] BGM$_currentBGMIndex を再生開始');
    } catch (e) {
      if (!_bgmAssetsMissing) {
        _bgmAssetsMissing = true;
        debugPrint('[BackgroundMusicService] BGMアセットなし(bgm3/bgm4.mp3)。再生をスキップします。');
      }
      // ファイルが見つからない場合は次のBGMを試す（1回だけ）
      if (_currentBGMIndex == 3) {
        _currentBGMIndex = 4;
        try {
          await _playCurrentBGM();
        } catch (_) {}
      }
    }
  }

  /// 次のBGMに切り替え（交互に再生）
  Future<void> _switchToNextBGM() async {
    if (_isOtherSoundPlaying) return; // 他の効果音が優先

    // 交互に切り替え: 3 → 4 → 3 → 4...
    _currentBGMIndex = _currentBGMIndex == 3 ? 4 : 3;

    try {
      // 少し間隔を空けてから次のBGMを再生（フェード効果）
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_isOtherSoundPlaying) {
        await _playCurrentBGM();
      }
    } catch (e) {
      debugPrint('[BackgroundMusicService] BGM切り替えエラー: $e');
      // エラー時はもう一方のBGMを試す
      _currentBGMIndex = _currentBGMIndex == 3 ? 4 : 3;
      try {
        await _playCurrentBGM();
      } catch (_) {}
    }
  }

  /// 他の効果音が再生開始されたとき（BGMを一時停止）
  void pauseForOtherSound() {
    if (_isOtherSoundPlaying) return; // 既に一時停止中
    _isOtherSoundPlaying = true;
    if (_isBGMPlaying) {
      _bgmPlayer.pause();
      debugPrint('[BackgroundMusicService] 他の効果音のためBGMを一時停止');
    }
  }

  /// 他の効果音が終了したとき（BGMを再開）
  Future<void> resumeAfterOtherSound() async {
    if (!_isOtherSoundPlaying) return; // 既に再生中
    _isOtherSoundPlaying = false;

    // 少し待ってから再開（効果音の終了を待つ）
    await Future.delayed(const Duration(milliseconds: 300));

    if (!_isBGMPlaying) {
      // 次のBGMに切り替えて再生（交互再生を維持）
      await _switchToNextBGM();
    } else {
      // 既に再生中なら再開
      await _bgmPlayer.resume();
    }
    debugPrint('[BackgroundMusicService] 他の効果音終了後、BGMを再開');
  }

  /// BGMを停止（アプリ終了時など）
  Future<void> stop() async {
    await _bgmPlayer.stop();
    _isBGMPlaying = false;
    _playerStateSubscription?.cancel();
    _nextBGMTimer?.cancel();
    debugPrint('[BackgroundMusicService] BGMを停止');
  }

  /// 瞑想音楽を再生（ホーム画面でも継続）
  Future<void> playMeditationMusic(String pillarId) async {
    try {
      final pillarIdLower = pillarId.toLowerCase();

      // 既に同じ瞑想音楽が再生中の場合は何もしない
      if (_currentMeditationMusic == pillarIdLower && _isBGMPlaying) {
        debugPrint('[BackgroundMusicService] 既に瞑想音楽が再生中: $pillarIdLower');
        return;
      }

      // 既存のBGMを停止
      if (_isBGMPlaying) {
        await _bgmPlayer.stop();
        _isBGMPlaying = false;
      }

      // 瞑想音楽を再生
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.setVolume(0.8);

      try {
        await _bgmPlayer.play(AssetSource('sounds/meditation/$pillarIdLower.mp3'));
        _currentMeditationMusic = pillarIdLower;
        _isBGMPlaying = true;
        _isOtherSoundPlaying = false; // 瞑想音楽は継続再生のため
        debugPrint('[BackgroundMusicService] 瞑想音楽を再生: $pillarIdLower.mp3');
      } catch (e) {
        try {
          await _bgmPlayer.play(AssetSource('sounds/meditation/$pillarIdLower.wav'));
          _currentMeditationMusic = pillarIdLower;
          _isBGMPlaying = true;
          _isOtherSoundPlaying = false;
          debugPrint('[BackgroundMusicService] 瞑想音楽を再生: $pillarIdLower.wav');
        } catch (e2) {
          debugPrint('[BackgroundMusicService] 瞑想音楽が見つかりません: $pillarIdLower');
          // 瞑想音楽がない場合は通常のBGMに戻す
          _currentMeditationMusic = null;
          await _startBGM();
        }
      }
    } catch (e) {
      debugPrint('[BackgroundMusicService] 瞑想音楽再生エラー: $e');
      // エラー時は通常のBGMに戻す
      _currentMeditationMusic = null;
      await _startBGM();
    }
  }

  /// 瞑想音楽を停止して通常のBGMに戻す
  Future<void> stopMeditationMusic() async {
    if (_currentMeditationMusic != null) {
      _currentMeditationMusic = null;
      await _bgmPlayer.stop();
      _isBGMPlaying = false;
      await _startBGM();
    }
  }

  /// アプリがバックグラウンドに移行したとき（音楽を一時停止）
  Future<void> pauseForBackground() async {
    if (_isBGMPlaying) {
      _wasPlayingBeforePause = true;
      _pausedMeditationMusic = _currentMeditationMusic;
      await _bgmPlayer.pause();
      debugPrint('[BackgroundMusicService] アプリがバックグラウンドに移行したため、音楽を一時停止');
    }
  }

  /// アプリがフォアグラウンドに戻ったとき（音楽を再開）
  Future<void> resumeFromBackground() async {
    if (_wasPlayingBeforePause) {
      _wasPlayingBeforePause = false;

      // 瞑想音楽が再生中だった場合は再開
      if (_pausedMeditationMusic != null) {
        _currentMeditationMusic = _pausedMeditationMusic;
        _pausedMeditationMusic = null;
        await _bgmPlayer.resume();
        _isBGMPlaying = true;
        debugPrint('[BackgroundMusicService] アプリがフォアグラウンドに戻ったため、瞑想音楽を再開: $_currentMeditationMusic');
      } else {
        // 通常のBGMを再開
        await _bgmPlayer.resume();
        _isBGMPlaying = true;
        debugPrint('[BackgroundMusicService] アプリがフォアグラウンドに戻ったため、BGMを再開');
      }
    }
  }

  /// リソースを解放
  Future<void> dispose() async {
    await stop();
    await _bgmPlayer.dispose();
  }
}
