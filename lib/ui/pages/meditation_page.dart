import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/pages/meditation_scene.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';

/// RouteObserverを使用して画面復帰時に自動リロード
class MeditationPageObserver extends RouteObserver<PageRoute<dynamic>> {
  final VoidCallback onRouteReturned;
  MeditationPageObserver(this.onRouteReturned);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute is PageRoute && previousRoute.isCurrent) {
      onRouteReturned();
    }
  }
}

class MeditationPage extends StatefulWidget {
  const MeditationPage({super.key});

  @override
  State<MeditationPage> createState() => _MeditationPageState();
}

class _MeditationPageState extends State<MeditationPage> {
  int _point = 0;
  int _ownedCards = 0;
  List<Map<String, dynamic>> _inventory = [];

  @override
  void initState() {
    super.initState();
    _load();
    // 定期的にリロード（5秒ごと）して最新状態を取得
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _load();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 画面に戻ってきたときにリロード
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _load();
        }
      });
    });
  }

  Future<void> _load() async {
    final p = await Storage.getPoint();
    final allInv = await CloudService.getInventory(type: 'meditation_card');
    // ガチャで獲得したカードのみをフィルタリング
    final gachaCards = allInv.where((card) {
      final source = card['source'] as String?;
      return source == 'gacha';
    }).toList();
    // デバッグ: 取得したカード数を確認
    print('[MeditationPage] Loaded ${allInv.length} total cards, ${gachaCards.length} from gacha');
    if (gachaCards.isNotEmpty) {
      print('[MeditationPage] First gacha card: ${gachaCards.first}');
    }
    setState(() {
      _point = p;
      _ownedCards = gachaCards.length;
      _inventory = gachaCards;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('瞑想')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: Colors.purpleAccent.withOpacity(0.2),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ポイント', style: TextStyle(fontSize: 12, color: Colors.white70)),
                          Text('$_point', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Card(
                    color: Colors.purpleAccent.withOpacity(0.2),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('瞑想カード', style: TextStyle(fontSize: 12, color: Colors.white70)),
                          Text('$_ownedCards 枚', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_inventory.isEmpty) ...[
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 64,
                        color: Colors.white38,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '瞑想カードがありません',
                        style: TextStyle(fontSize: 18, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ガチャで瞑想カードを獲得できます',
                        style: TextStyle(fontSize: 14, color: Colors.white54),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.casino),
                        label: const Text('ガチャへ'),
                        onPressed: () {
                          Navigator.pop(context);
                          // ホームページでガチャボタンを押してもらう
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purpleAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const Text('ガチャで獲得した瞑想カード一覧:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _inventory.length,
                  itemBuilder: (_, i) {
                    final card = _inventory[i];
                    final cardDeityId = card['deityId'] as String?;

                    // 神の情報を取得
                    Deity? deity;
                    if (cardDeityId != null) {
                      try {
                        deity = deities.firstWhere((d) => d.id == cardDeityId);
                      } catch (e) {
                        // 神が見つからない場合はnullのまま
                      }
                    }

                    // 神の色を取得
                    final color = deity != null
                        ? Color(int.parse(deity.colorHex.replaceFirst('#', '0xff')))
                        : Colors.purpleAccent;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: color.withOpacity(0.5), width: 2),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              color.withOpacity(0.2),
                              color.withOpacity(0.05),
                            ],
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withOpacity(0.2),
                              border: Border.all(color: color.withOpacity(0.5), width: 2),
                            ),
                            child: deity != null
                                ? ClipOval(
                                    child: Image.asset(
                                      deity.symbolAsset,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.auto_awesome,
                                        color: color,
                                        size: 32,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.self_improvement,
                                    color: color,
                                    size: 32,
                                  ),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                deity != null ? '【${deity.nameJa}】' : '瞑想カード',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: color,
                                ),
                              ),
                              if (deity != null)
                                Text(
                                  deity.role,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.timer, size: 16, color: Colors.white70),
                                const SizedBox(width: 4),
                                Text(
                                  '${card['minutes'] ?? 5}分',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('開始'),
                            onPressed: () async {
                              // カードに紐づいた神を使用（必須）
                              if (deity == null && cardDeityId == null) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('エラー: カードに神の情報がありません'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }

                              // 神が取得できない場合はエラー
                              if (deity == null && cardDeityId != null) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('エラー: 神の情報が見つかりません'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                                return;
                              }

                              // カードを使用（削除）
                              await CloudService.removeInventoryItem(card['id'] as String);

                              if (mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MeditationScene(
                                      deity: deity!,
                                      durationMinutes: card['minutes'] ?? 5,
                                    ),
                                  ),
                                ).then((_) => _load());
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            // 1分無料瞑想機能（Tenmiraを使用）
            if (_inventory.isEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                '1分無料瞑想',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Tenmira（未来の神）の瞑想を体験できます',
                style: TextStyle(fontSize: 14, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                onPressed: () {
                  // Tenmiraを取得
                  final tenmira = deities.firstWhere((d) => d.id == 'tenmira');
                  // MeditationSceneに遷移（1分間）
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MeditationScene(
                        deity: tenmira,
                        durationMinutes: 1,
                      ),
                    ),
                  );
                },
                label: const Text('1分瞑想を開始（無料）'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Color(int.parse(deities.firstWhere((d) => d.id == 'tenmira').colorHex.replaceFirst('#', '0xff'))),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
