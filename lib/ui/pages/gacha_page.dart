import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/services/currency_service.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/gacha_service.dart';

class GachaPage extends StatefulWidget {
  const GachaPage({super.key});

  @override
  State<GachaPage> createState() => _GachaPageState();
}

class _GachaPageState extends State<GachaPage> with SingleTickerProviderStateMixin {
  int _point = 0;
  late final AnimationController _ctrl;
  late Animation<double> _spin;
  bool _isSpinning = false;
  Deity? _result;

  @override
  void initState() {
    super.initState();
    _load();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 4000));
    _spin = CurvedAnimation(parent: _ctrl, curve: Curves.decelerate);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await Storage.getPoint();
    setState(() => _point = p);
  }

  Future<void> _play() async {
    if (_isSpinning) return;
    final wallet = await CurrencyService.load();
    if (wallet['coins']! < GachaService.costPerPlay) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('コインが不足しています')),
        );
      }
      return;
    }

    setState(() {
      _isSpinning = true;
      _result = null;
    });

    // 回転開始（減速）
    _ctrl.reset();
    await _ctrl.forward();

    // ガチャサービスで抽選
    print('[GachaPage] Starting gacha play...');
    final result = await GachaService.play();
    print('[GachaPage] Gacha result: ${result?.rewardType}, amount: ${result?.amount}');

    if (result == null) {
      setState(() {
        _isSpinning = false;
      });
      if (mounted) {
        final wallet = await CurrencyService.load();
        final canPlay = await GachaService.canPlayToday();
        String errorMsg = 'ガチャに失敗しました';
        if (!canPlay) {
          errorMsg = '今日の上限に達しています';
        } else if (wallet['coins']! < GachaService.costPerPlay) {
          errorMsg = 'コインが不足しています';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
      return;
    }

    if (result != null) {
      // 降臨した神を取得
      final deity = result.deityId != null
          ? deities.firstWhere((d) => d.id == result.deityId, orElse: () => deities.first)
          : deities[DateTime.now().millisecondsSinceEpoch % deities.length];

      setState(() {
        _result = deity;
        _isSpinning = false;
      });

      String rewardText;
      bool isRare = false;
      switch (result.rewardType) {
        case 'coins':
          rewardText = '+${result.amount} コイン';
          break;
        case 'gems':
          rewardText = '✨ 激レア！ +${result.amount} ジェム ✨';
          isRare = true;
          break;
        case 'fragments':
          rewardText = '+${result.amount} フラグメント';
          break;
        case 'meditation_card':
          rewardText = '🎴 瞑想カード +1';
          print('[GachaPage] Meditation card won! Checking inventory...');
          // カードが保存されたか確認
          final checkInv = await CloudService.getInventory(type: 'meditation_card');
          print('[GachaPage] Inventory after gacha: ${checkInv.length} cards');
          break;
        case 'boost':
          rewardText = '🌟 超激レア！ 運気ブースト +1 🌟';
          isRare = true;
          break;
        default:
          rewardText = '報酬獲得';
      }

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('【${deity.nameJa}】 降臨！ 報酬: $rewardText'),
            backgroundColor: isRare ? Colors.amber.shade700 : null,
            duration: isRare ? const Duration(seconds: 5) : const Duration(seconds: 3),
          ),
        );
      }
    } else {
      setState(() {
        _isSpinning = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ガチャに失敗しました')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final radius = size.shortestSide * 0.34;
    return Scaffold(
      appBar: AppBar(title: const Text('降臨ガチャ')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<Map<String, dynamic>>(
              future: Future.wait([
                CurrencyService.load(),
                GachaService.getRemainingPlays(),
              ]).then((results) => {
                    'wallet': results[0] as Map<String, int>,
                    'remaining': results[1] as int,
                  }),
              builder: (context, snapshot) {
                final wallet = (snapshot.data?['wallet'] as Map<String, int>?) ?? {};
                final coins = wallet['coins'] ?? 0;
                final gems = wallet['gems'] ?? 0;
                final fragments = wallet['fragments'] ?? 0;
                final remaining = snapshot.data?['remaining'] as int? ?? GachaService.dailyLimit;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ポイント: $_point'),
                    Text('コイン: $coins / ジェム: $gems / フラグメント: $fragments'),
                    Text('今日の残り回数: $remaining / ${GachaService.dailyLimit}回'),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final angle = (2 * math.pi * 6) * (1 - _spin.value); // 減速回転
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: radius * 2 + 160,
                          height: radius * 2 + 160,
                          child: Stack(
                            children: [
                              for (int i = 0; i < deities.length; i++)
                                _DeityOrbit(angle: angle, index: i, radius: radius),
                              // ジェムを回転アニメーションに追加（激レア報酬の存在を示す）
                              _GemOrbit(angle: angle, radius: radius * 0.7),
                            ],
                          ),
                        ),
                        if (_result != null) _ResultHalo(deity: _result!),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: Future.wait([
                CurrencyService.load(),
                GachaService.canPlayToday(),
              ]).then((results) => {
                    'wallet': results[0] as Map<String, int>,
                    'canPlay': results[1] as bool,
                  }),
              builder: (context, snapshot) {
                final wallet = (snapshot.data?['wallet'] as Map<String, int>?) ?? {};
                final coins = wallet['coins'] ?? 0;
                final canPlay =
                    (snapshot.data?['canPlay'] as bool? ?? true) && coins >= GachaService.costPerPlay && !_isSpinning;
                return ElevatedButton.icon(
                  onPressed: canPlay ? _play : null,
                  icon: const Icon(Icons.casino),
                  label: Text('${GachaService.costPerPlay}コインで降臨を呼ぶ'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DeityOrbit extends StatelessWidget {
  final double angle;
  final int index;
  final double radius;
  const _DeityOrbit({required this.angle, required this.index, required this.radius});

  @override
  Widget build(BuildContext context) {
    final d = deities[index];
    final t = angle + (index / deities.length) * 2 * math.pi;
    final dx = radius * math.cos(t);
    final dy = radius * math.sin(t);
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Opacity(
        opacity: 0.95,
        child: Image.asset(d.symbolAsset, height: 72, width: 72, fit: BoxFit.contain),
      ),
    );
  }
}

class _GemOrbit extends StatelessWidget {
  final double angle;
  final double radius;
  const _GemOrbit({required this.angle, required this.radius});

  @override
  Widget build(BuildContext context) {
    // ジェムが回転する（激レア報酬の存在を示す）
    final t = angle + math.pi; // 反対側に配置
    final dx = radius * math.cos(t);
    final dy = radius * math.sin(t);
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.lightBlueAccent.withOpacity(0.8),
              Colors.blueAccent.withOpacity(0.6),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.lightBlueAccent.withOpacity(0.6),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: const Icon(
          Icons.diamond,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}

class _ResultHalo extends StatelessWidget {
  final Deity deity;
  const _ResultHalo({required this.deity});

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse(deity.colorHex.replaceFirst('#', '0xff')));
    final s = MediaQuery.of(context).size.shortestSide * 0.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: s * 1.2,
          height: s * 1.2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withOpacity(.3), Colors.transparent]),
          ),
        ),
        Positioned.fill(child: const SizedBox.shrink()),
        Image.asset(deity.symbolAsset, height: s, width: s, fit: BoxFit.contain),
      ],
    );
  }
}
