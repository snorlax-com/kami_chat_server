import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/ui/pages/consultation_mail_bridge_test_page.dart';
import 'package:kami_face_oracle/ui/pages/developer_chat_page.dart';

/// Firestore 等で bool が混在しても履歴の「至急」表示を安定させる
bool _coerceUrgentFlag(dynamic v) {
  if (v == true) return true;
  if (v == false) return false;
  if (v == 1) return true;
  if (v == 0) return false;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return false;
}

/// サーバー応答と至急ボタンの一致をユーザーに示す（Render 未更新時の切り分け用）
void _showMailSentFeedback(
  BuildContext context, {
  required bool useFirestore,
  required String coinLine,
  required bool urgent,
  required bool mailSent,
  SendChatResponse? bridge,
}) {
  if (!mailSent) return;

  final v2 = (bridge?.mailApiBuild ?? '').trim().startsWith('v2-consultation-tier');
  final ct = (bridge?.consultationType ?? '').trim();
  final serverPriority =
      bridge?.mailUrgent == true || ct == ConsultationMailType.priorityGuidance;
  final explicitServerNormal = bridge?.mailUrgent == false ||
      (ct == ConsultationMailType.normal && bridge?.mailUrgent != true);

  if (urgent && v2 && explicitServerNormal && !serverPriority) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$coinLine。\n'
          '【要確認】サーバーは「通常メール」として送信しました。至急なのに Gmail で区別が付かない原因はこれです。\n'
          'Render の kami_chat_server をこのリポジトリの最新版で再デプロイし、consultationType が届くか確認してください。',
        ),
        backgroundColor: Colors.deepOrange,
        duration: const Duration(seconds: 14),
      ),
    );
    return;
  }

  if (urgent && mailSent && !v2) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$coinLine。メールは送信されました。\n'
          'サーバーが古い応答形式のため、Gmail に「至急占い」件名になっているか自動では確認できません。'
          '件名が「【至急占い・緊急】」で始まらない場合は kami-chat-server（Render）を最新コードで再デプロイしてください。',
        ),
        backgroundColor: Colors.amber.shade800,
        duration: const Duration(seconds: 12),
      ),
    );
    return;
  }

  final extraUrgent = urgent && serverPriority
      ? ' Gmailでは件名が「【至急占い・緊急】」で始まり、差出人は「至急占い相談｜…」です（通常の「[AuraFace] 新しい相談」と一覧が別になります）。'
      : '';

  if (useFirestore) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$coinLine。開発者に通知しました。$extraUrgent'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: urgent ? 8 : 4),
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('相談内容を開発者にメールで送りました。$extraUrgent'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: urgent ? 8 : 4),
      ),
    );
  }
}

class ConsultationPage extends StatefulWidget {
  const ConsultationPage({super.key});

  @override
  State<ConsultationPage> createState() => _ConsultationPageState();
}

class _ConsultationPageState extends State<ConsultationPage> {
  final _controller = TextEditingController();
  int _point = 0;
  int _normalTickets = 0;
  int _priorityTickets = 0;
  int _urgentSlotsLeft = 5;
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
    final n = await ConsultationTicketService.normalTickets();
    final pr = await ConsultationTicketService.priorityTickets();
    final left = await ConsultationTicketService.urgentSlotsRemainingToday();
    final hist = await CloudService.getConsultations();
    setState(() {
      _point = p;
      _normalTickets = n;
      _priorityTickets = pr;
      _urgentSlotsLeft = left;
      _history = hist;
    });
  }

  static bool _isLocalhostUrl(String url) {
    final u = url.trim().toLowerCase();
    return u.startsWith('http://127.0.0.1') || u.startsWith('http://localhost') ||
        u.startsWith('https://127.0.0.1') || u.startsWith('https://localhost');
  }

  Future<void> _send({required bool urgent}) async {
    if (_controller.text.trim().isEmpty) return;

    final useFirestore = CloudService.isAvailable;

    if (urgent) {
      final ticketErr = await ConsultationTicketService.validateUrgentSend();
      if (ticketErr != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ticketErr), backgroundColor: Colors.orange.shade800),
          );
        }
        return;
      }
    } else {
      final ticketErr = await ConsultationTicketService.validateNormalSend();
      if (ticketErr != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ticketErr), backgroundColor: Colors.orange.shade800),
          );
        }
        return;
      }
    }

    if (useFirestore) {
      await CloudService.addConsultation(
        _controller.text.trim(),
        urgent: urgent,
        cost: 1,
      );
    }

    if (urgent) {
      await ConsultationTicketService.consumeUrgentSend();
    } else {
      await ConsultationTicketService.consumeNormalTicket();
    }

    // 相談ボタンを押したら必ず開発者へGmail通知（メールブリッジ）
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    if (!prefs.containsKey('user_id')) await prefs.setString('user_id', userId);
    final savedUrl = prefs.getString(AuraFaceChatMailService.prefKeyBaseUrl);
    final bridgeUrl = AuraFaceChatMailService.consultationSendBaseUrl(savedUrl);
    debugPrint('[Consultation] mail bridge savedPref=$savedUrl actualBridgeUrl=$bridgeUrl');

    var mailSuccess = false;
    bool? mailSentReport;
    SendChatResponse? mailBridgeRes;
    try {
      final mailService = AuraFaceChatMailService(baseUrl: bridgeUrl);
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
      mailBridgeRes = res;
      debugPrint(
        '[Consultation] mail send success=${res.success} mailSent=${res.mailSent} mailUrgent=${res.mailUrgent} '
        'consultationType=${res.consultationType} subject=${res.mailSubject} build=${res.mailApiBuild} error=${res.error} mailError=${res.mailError}',
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
            _isLocalhostUrl(bridgeUrl);
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
      // 画面上の種別は「押したボタン」基準（至急で押したなら常に至急表記。Gmail文言はサーバー応答で SnackBar 追記）
      final coinLine = urgent
          ? '至急相談を送信しました（優先券1枚・本日の至急枠を1回使用）'
          : '通常相談を送信しました（通常相談券1枚）';
      if (useFirestore) {
        if (mailSentReport == true) {
          _showMailSentFeedback(
            context,
            useFirestore: true,
            coinLine: coinLine,
            urgent: urgent,
            mailSent: true,
            bridge: mailBridgeRes,
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
        _showMailSentFeedback(
          context,
          useFirestore: false,
          coinLine: coinLine,
          urgent: urgent,
          mailSent: true,
          bridge: mailBridgeRes,
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
    final canUrgent = _urgentSlotsLeft > 0 &&
        _priorityTickets >= ConsultationTicketService.priorityCostPerSend;

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
            Text('通常相談券: $_normalTickets 枚 / 優先券: $_priorityTickets 枚'),
            Text(
              '至急枠（本日・日本時間）: 残り $_urgentSlotsLeft / ${ConsultationTicketService.maxUrgentSlotsPerDay}（24時間受付・1日5回まで）',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('通常券+3'),
                  onPressed: () async {
                    await ConsultationTicketService.addNormalTickets(3);
                    await _load();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('通常相談券を3枚付与しました'), backgroundColor: Colors.green),
                      );
                    }
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.stars_outlined, size: 18),
                  label: const Text('優先券+1'),
                  onPressed: () async {
                    await ConsultationTicketService.addPriorityTickets(1);
                    await _load();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('優先券を1枚付与しました'), backgroundColor: Colors.green),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.chat),
                    onPressed: _normalTickets >= ConsultationTicketService.normalCostPerSend
                        ? () => _send(urgent: false)
                        : null,
                    label: const Text('通常相談（通常相談券1枚）'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Tooltip(
                    message: canUrgent
                        ? '開発者へのメールは「至急占い」件名・専用差出人で届きます（優先券1枚・本日枠1回）'
                        : (_urgentSlotsLeft <= 0
                            ? '本日の至急枠（5回）を使い切りました。'
                            : '優先券が不足しています。'),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      ),
                      onPressed: canUrgent ? () => _send(urgent: true) : null,
                      icon: const Icon(Icons.priority_high, size: 22),
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '至急相談',
                            style: TextStyle(fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '本日残り $_urgentSlotsLeft / ${ConsultationTicketService.maxUrgentSlotsPerDay} 枠',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            '（優先券 $_priorityTickets 枚）',
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                    ),
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
                    final urgent = _coerceUrgentFlag(item['urgent']);
                    final rawCost = item['cost'];
                    final ticketCount = rawCost is int ? rawCost : 1;
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
                      subtitle: Text(
                        '${urgent ? "至急" : "通常"}（${urgent ? "優先券" : "通常相談券"} $ticketCount枚）- $statusText',
                      ),
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
