import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/currency_service.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/ui/pages/consultation_mail_bridge_test_page.dart';
import 'package:kami_face_oracle/ui/pages/developer_chat_page.dart';

class ConsultationPage extends StatefulWidget {
  const ConsultationPage({super.key});

  @override
  State<ConsultationPage> createState() => _ConsultationPageState();
}

class _ConsultationPageState extends State<ConsultationPage> {
  final _controller = TextEditingController();
  int _point = 0;
  int _coins = 0;
  int _gems = 0;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
    // リアルタイム更新をリッスン（回答が来たときに自動更新）
    _setupListener();
  }

  void _setupListener() {
    CloudService.watchConsultations().listen((history) {
      if (mounted) {
        setState(() {
          _history = history;
        });
      }
    });
  }

  Future<void> _load() async {
    final p = await Storage.getPoint();
    final wallet = await CurrencyService.load();
    final hist = await CloudService.getConsultations();
    setState(() {
      _point = p;
      _coins = wallet['coins']!;
      _gems = wallet['gems']!;
      _history = hist;
    });
  }

  static bool _isLocalhostUrl(String url) {
    final u = url.trim().toLowerCase();
    return u.startsWith('http://127.0.0.1') || u.startsWith('http://localhost') ||
        u.startsWith('https://127.0.0.1') || u.startsWith('https://localhost');
  }

  Future<void> _send({required bool urgent, required int coinCost, int? gemCost}) async {
    if (_controller.text.trim().isEmpty) return;

    final useFirestore = CloudService.isAvailable;

    // Firestore が使える場合のみコイン/ジェムを消費してFirestoreに保存
    if (useFirestore) {
    if (urgent && gemCost != null) {
      if (_gems < gemCost) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ジェムが不足しています')),
          );
        }
        return;
      }
      await CurrencyService.useGems(gemCost);
    } else {
      if (_coins < coinCost) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('コインが不足しています')),
          );
        }
        return;
      }
      await CurrencyService.useCoins(coinCost);
    }
    await CloudService.addConsultation(
      _controller.text.trim(),
      urgent: urgent,
      cost: urgent ? (gemCost ?? 0) : coinCost,
    );
    }

    // 相談ボタンを押したら必ず開発者へGmail通知（メールブリッジ）
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    if (!prefs.containsKey('user_id')) await prefs.setString('user_id', userId);
    final savedUrl = prefs.getString(AuraFaceChatMailService.prefKeyBaseUrl);
    final effectiveUrl = savedUrl ?? AuraFaceChatMailService.effectiveDefaultBaseUrl;
    debugPrint('[Consultation] mail bridge savedUrl=$savedUrl effectiveUrl=$effectiveUrl');

    var mailSuccess = false;
    bool? mailSentReport;
    try {
      final mailService = AuraFaceChatMailService(baseUrl: savedUrl);
      final chatId = 'consultation_${userId}_${DateTime.now().millisecondsSinceEpoch}';
      final res = await mailService.send(
        userId: userId,
        chatId: chatId,
        message: _controller.text.trim(),
        userName: '占い相談ユーザー',
        userEmail: '',
        consultationType:
            urgent ? ConsultationMailType.priorityGuidance : ConsultationMailType.normal,
      );
      debugPrint(
        '[Consultation] mail send success=${res.success} mailSent=${res.mailSent} error=${res.error} mailError=${res.mailError}',
      );
      mailSuccess = res.success;
      mailSentReport = res.mailSent;
      if (res.success) {
        await DeveloperChatPref.setActiveChatId(chatId);
      }
      if (res.success && res.mailSent == false && mounted) {
        final detail = res.mailError != null && res.mailError!.isNotEmpty
            ? '\n${res.mailError}'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'サーバーには保存されましたが、開発者へのGmail通知に失敗しました。'
              'Render の環境変数（RESEND_API_KEY, ADMIN_EMAIL, MAIL_FROM, BASE_URL）を確認してください。$detail',
            ),
            backgroundColor: Colors.deepOrange,
            duration: const Duration(seconds: 10),
          ),
        );
      }
      if (!res.success && mounted) {
        final isLocalhostRefused = _isLocalhostUrl(mailService.baseUrl) &&
            (res.error?.contains('Connection refused') ?? false);
        final message = isLocalhostRefused
            ? '実機では 127.0.0.1 に接続できません。「接続先を設定」で同じWi-Fiの開発PCのIP（例: http://192.168.1.10:3000）を入力してください。'
            : (useFirestore
                ? '相談は保存されましたが、開発者への通知メールの送信に失敗しました。通信設定をご確認ください。'
                : '開発者への通知メールの送信に失敗しました。通信設定をご確認ください。');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
            action: kDebugMode
                ? SnackBarAction(
                    label: '接続先を設定',
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ConsultationMailBridgeTestPage()));
                    },
                  )
                : null,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[Consultation] mail exception: $e');
      debugPrint('[Consultation] $st');
      if (mounted) {
        final isConfigError = e is StateError && e.message.contains('MAIL_BRIDGE_URL');
        final isLocalhostRefused = e.toString().contains('Connection refused') &&
            _isLocalhostUrl(effectiveUrl);
        final message = isConfigError
            ? '開発者通知の接続先が設定されていません。本番ビルドでは要設定です。'
            : isLocalhostRefused
                ? '実機では 127.0.0.1 に接続できません。「接続先を設定」で同じWi-Fiの開発PCのIP（例: http://192.168.1.10:3000）を入力してください。'
                : (useFirestore
                    ? '相談は保存されましたが、開発者への通知メールの送信に失敗しました。通信設定をご確認ください。'
                    : '開発者への通知メールの送信に失敗しました。通信設定をご確認ください。');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
            action: kDebugMode
                ? SnackBarAction(
                    label: '接続先を設定',
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ConsultationMailBridgeTestPage()));
                    },
                  )
                : null,
          ),
        );
      }
    }

    await _load();
    if (mounted && mailSuccess) {
      final coinLine =
          '${urgent ? '至急相談' : '通常相談'}を送信しました（消費: ${urgent ? (gemCost ?? 0) : coinCost} ${urgent ? 'ジェム' : 'コイン'}）';
      if (useFirestore) {
        if (mailSentReport == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$coinLine。開発者に通知しました。'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (mailSentReport == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$coinLine。メール通知の成否はサーバーから返っていません。'
                'Render の kami-chat-server を最新版にデプロイし、Resend 環境変数を設定してください。',
              ),
              backgroundColor: Colors.amber.shade800,
              duration: const Duration(seconds: 10),
            ),
          );
        }
      } else if (mailSentReport == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('相談内容を開発者にメールで送りました。'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mailSentReport == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'サーバーには送信できましたが、メール通知の実施は応答では確認できません。'
              '本番のチャットサーバーが古い可能性があります。Render で最新コードをデプロイし、Resend 用の環境変数を設定してください。',
            ),
            backgroundColor: Colors.amber.shade800,
            duration: Duration(seconds: 10),
          ),
        );
      }
    }
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('占い相談'),
        actions: [
          IconButton(
            tooltip: '開発者とのやりとり',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeveloperChatPage()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ポイント: $_point'),
            Text('コイン: $_coins / ジェム: $_gems'),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('コイン+100'),
                  onPressed: () async {
                    final v = await CurrencyService.addCoins(100);
                    await _load();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('コインを付与しました（現在: $v）'), backgroundColor: Colors.green),
                      );
                    }
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.diamond_outlined, size: 18),
                  label: const Text('ジェム+10'),
                  onPressed: () async {
                    final v = await CurrencyService.addGems(10);
                    await _load();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('ジェムを付与しました（現在: $v）'), backgroundColor: Colors.green),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.email_outlined, size: 20),
              label: const Text('開発者にメールで相談（Gmail通知・返信が届く）'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConsultationMailBridgeTestPage()),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '相談内容を入力してください',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.chat),
                    onPressed: (_coins >= 20 || !CloudService.isAvailable)
                        ? () => _send(urgent: false, coinCost: 20, gemCost: null)
                        : null,
                    label: const Text('通常相談(20コイン)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.priority_high),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                    ),
                    onPressed: (_gems >= 5 || !CloudService.isAvailable)
                        ? () => _send(urgent: true, coinCost: 0, gemCost: 5)
                        : null,
                    label: const Text('至急相談(5ジェム)'),
                  ),
                ),
              ],
            ),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('送信履歴:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _history.length,
                  itemBuilder: (_, i) {
                    final item = _history[i];
                    final text = item['text'] ?? '';
                    final urgent = item['urgent'] == true;
                    final cost = item['cost'] ?? 0;
                    final status = item['status'] ?? 'pending';
                    final answer = item['answer'] as String?;
                    final answeredAt = item['answeredAt'];
                    final createdAt = item['createdAt'];

                    Color statusColor;
                    IconData statusIcon;
                    String statusText;
                    if (status == 'answered') {
                      statusColor = Colors.green;
                      statusIcon = Icons.check_circle;
                      statusText = '回答済み';
                    } else if (status == 'expired') {
                      statusColor = Colors.grey;
                      statusIcon = Icons.access_time;
                      statusText = '期限切れ';
                    } else {
                      statusColor = Colors.orange;
                      statusIcon = Icons.pending;
                      statusText = '回答待ち';
                    }

                    return ExpansionTile(
                      leading: Icon(urgent ? Icons.priority_high : Icons.chat, color: urgent ? Colors.red : null),
                      title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${urgent ? "至急" : "通常"} ($cost ${urgent ? "ジェム" : "コイン"}) - $statusText'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, color: statusColor, size: 20),
                          if (createdAt != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              createdAt.toString().length > 10 ? createdAt.toString().substring(0, 10) : '',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                      children: [
                        if (answer != null && answer.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '回答:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(answer),
                                if (answeredAt != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      '回答日時: ${answeredAt.toString().substring(0, 19)}',
                                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ] else if (status == 'pending') ...[
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              '回答をお待ちください...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
