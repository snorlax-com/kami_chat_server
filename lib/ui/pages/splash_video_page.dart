import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kami_face_oracle/bootstrap/deferred_startup.dart';
import 'package:kami_face_oracle/bootstrap/opening_video_preload.dart';
import 'package:video_player/video_player.dart';

/// 起動時の白画面対策: スプラッシュ動画を全画面で再生してから次画面へ遷移する。
class SplashVideoPage extends StatefulWidget {
  const SplashVideoPage({
    super.key,
    required this.next,
    this.splashAsset = 'assets/videos/opening_animation.mp4',
  });

  final Widget next;
  final String splashAsset;

  @override
  State<SplashVideoPage> createState() => _SplashVideoPageState();
}

class _SplashVideoPageState extends State<SplashVideoPage> {
  VideoPlayerController? _controller;
  bool _navigated = false;
  bool _frozen = false;
  late final String _line;

  // 「AuraFace」ロゴが見えるタイミングで静止画化する。
  static const Duration _freezeAt = Duration(milliseconds: 8000);
  static const Duration _holdAfterFreeze = Duration(milliseconds: 2600);
  // 端末の見た目で約1.5cmぶん上へ（概算）、その後 約1cm だけ下げる（0.5cm 調整との同比率: 38/1.5≒25px/cm）
  static const double _captionLiftPx = 38;
  static const double _captionBoardDownApproxOneCmPx = 26;
  // `_captionLiftPx` を約15mm とみなした論理px/mm（実機の物理寸法とは一致しないが既存調整と整合）
  static const double _captionLogicalPxPerMm = _captionLiftPx / 15;
  static const double _captionBoardRightApprox1mmPx = _captionLogicalPxPerMm * 1;
  static const double _captionBoardDownApprox5mmPx = _captionLogicalPxPerMm * 5;
  static const double _captionBoardRadius = 13;
  static const String _captionBoardAsset = 'assets/illustrations/splash_comment_board.png';
  // コメント行の幅を約1cm狭めて折り返しやすくする（総幅 -1cm ≒ 26px @ 上記 cm 目安）
  static const double _captionTextHorizontalPadBasePx = 14;
  static const double _captionTextShrinkApproxOneCmExtraPerSidePx = 13;
  static const double _captionTextHorizontalPadPx =
      _captionTextHorizontalPadBasePx + _captionTextShrinkApproxOneCmExtraPerSidePx;

  static const List<String> _lines = [
    '口が大きい人は、エネルギーが強く人を惹きつける傾向があるかも',
    '目に強い意志を感じる人は、決断力に優れたリーダー気質かも',
    '目元が柔らかい人は、共感力が高く人を支える力を持つ傾向',
    '鼻筋が通っている人は、現実的で安定を築く力があるかも',
    '眉がはっきりしている人は、信念を持って行動するタイプかも',
    '口角が上がりやすい人は、人との縁を自然に広げる力があるタイプ',
    '顎しっかりしている人は、粘り強く結果を出すタイプ',
    '顔全体のバランスが整っている人は、安定した運を持つかも',
    '表情が豊かな人は、表現力や創造性が高い傾向',
    '額が広い人は、先を読む力があり長期的に考える傾向',
    '眉と目の距離が近い人は、集中力が高く決断が早いタイプかも',
    '目が大きい人は、感受性が高く表現力に優れている傾向',
    '目が細めの人は、冷静で観察力に優れているタイプかも',
    '唇が厚い人は、感情表現が豊かで人との距離が近い傾向',
    '唇が薄い人は、理性的で物事を客観的に判断する力がある',
    '頬に丸みがある人は、柔らかく親しみやすい印象を持たれやすい',
    '輪郭がシャープな人は、意志が強くストイックな傾向',
    '眉の位置が高めの人は、情報処理が早く反応が速いタイプかも',
    '鼻先に丸みがある人は、金運や対人運を引き寄せやすい傾向',
    '',
    'Amateraはよく姿を消しますが、それは新しい発想を探しているだけです',
    'Tenkoraは気づけば誰かと話しています、それが力の源です',
    'Mimikaは静かに見えますが、すべてを見ています',
    'Yorusiは迷うより先に動きます、それが道を作るからです',
    'Noiruneは夜になるほど本領を発揮するタイプです',
    'Ragiasは突然ひらめきます、周囲は少し驚きます',
    'Amanoiraは急がず進みますが、最終的に一番遠くへ行きます',
    'Shiranは流れに乗るのが上手いですが、実は計算しています',
    'Delphosは考える前に動きますが、だいたい正解です',
    'Fatemisは細かいですが、それが完成度を高めています',
  ];

  @override
  void initState() {
    super.initState();
    final candidates = _lines.where((e) => e.trim().isNotEmpty).toList(growable: false);
    _line = candidates.isEmpty ? '' : candidates[Random().nextInt(candidates.length)];
    unawaited(_start());
  }

  Future<void> _start() async {
    OpeningVideoPreload.start();
    var c = await OpeningVideoPreload.take();
    if (c == null || !c.value.isInitialized) {
      c = await _createController(widget.splashAsset);
    }
    if (!mounted || c == null) {
      // 動画が開けない場合でも白画面のまま止まらないように次へ進める。
      await _goNext();
      return;
    }
    _controller = c;
    setState(() {});

    c.addListener(_maybeComplete);
    await c.play();
  }

  Future<VideoPlayerController?> _createController(String asset) async {
    try {
      final c = VideoPlayerController.asset(asset);
      await c.initialize();
      c.setLooping(false);
      c.setVolume(0.0);
      return c;
    } catch (_) {
      return null;
    }
  }

  void _maybeComplete() {
    final c = _controller;
    if (c == null || _navigated) return;
    final v = c.value;
    if (!v.isInitialized) return;
    if (!_frozen && v.position >= _freezeAt) {
      _frozen = true;
      unawaited(c.pause());
      unawaited(Future<void>.delayed(_holdAfterFreeze, _goNext));
      return;
    }
    if (!v.isPlaying && v.position >= v.duration && v.duration > Duration.zero) {
      unawaited(_goNext());
    }
  }

  Future<void> _goNext() async {
    if (!mounted || _navigated) return;
    _navigated = true;
    _controller?.removeListener(_maybeComplete);
    await DeferredStartup.awaitReady(timeout: const Duration(seconds: 8));
    if (!mounted) return;
    debugPrint('[StartupFlow] splash complete → age/policy gate');
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => widget.next),
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_maybeComplete);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final videoWidget = (c != null && c.value.isInitialized)
        ? FittedBox(
            // 「最大限すべて表示」: cover ではなく contain でトリミングを避ける
            fit: BoxFit.contain,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          )
        : const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 誤タップで早期遷移しないよう、起動スプラッシュのタップスキップは無効化
        onTap: () {},
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背面: 動画
            Align(
              alignment: Alignment.center,
              child: Transform.translate(
                offset: const Offset(0, -10),
                child: videoWidget,
              ),
            ),
            // 前面: コメント枠（動画と被ってOK、上に持ち上げる）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Transform.translate(
                  offset: Offset(
                    _captionBoardRightApprox1mmPx,
                    -_captionLiftPx +
                        _captionBoardDownApproxOneCmPx +
                        _captionBoardDownApprox5mmPx,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        image: DecorationImage(
                          image: AssetImage(_captionBoardAsset),
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                        ),
                        borderRadius: BorderRadius.circular(_captionBoardRadius),
                        border: Border.all(color: const Color(0xFF120A05), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black,
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        clipBehavior: Clip.hardEdge,
                        borderRadius: BorderRadius.circular(_captionBoardRadius),
                        child: Padding(
                          // 縦を約 +1cm 伸ばす（上下にまとめて付与）、横は上記で約1cm分狭い行幅で折り返し
                          padding: const EdgeInsets.symmetric(
                            horizontal: _captionTextHorizontalPadPx,
                            vertical: 31,
                          ),
                          child: Text(
                            _line,
                            maxLines: 12,
                            softWrap: true,
                            overflow: TextOverflow.clip,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              // 木の板に書いた感じ（少し暗め＋影で読みやすさ確保）
                              color: Color(0xFFF7E7C7),
                              fontSize: 12.8,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              shadows: [
                                Shadow(color: Color(0xFF120A05), blurRadius: 2, offset: Offset(0, 1)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

