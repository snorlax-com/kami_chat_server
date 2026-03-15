// lib/ui/pages/consultation_page_new.dart
// メールベースのサポートチャット（Firestore無し）

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/services/support_chat_service.dart';
import 'package:kami_face_oracle/services/currency_service.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/ui/pages/consultation_mail_bridge_test_page.dart';

class ConsultationPageNew extends StatefulWidget {
  final Map<String, dynamic>? diagnosis; // 診断結果（オプション）

  const ConsultationPageNew({super.key, this.diagnosis});

  @override
  State<ConsultationPageNew> createState() => _ConsultationPageNewState();
}

class _ConsultationPageNewState extends State<ConsultationPageNew> {
  final _controller = TextEditingController();
  final _supportService = SupportChatService();
  int _coins = 0;
  int _gems = 0;

  // チャット状態
  String? _currentCid;
  List<ChatMessage> _messages = [];
  Timer? _pollTimer;
  int? _lastMessageId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final wallet = await CurrencyService.load();
    setState(() {
      _coins = wallet['coins']!;
      _gems = wallet['gems']!;
    });
  }

  /// 定期ポーリングを開始
  void _startPolling(String cid) {
    _currentCid = cid;
    _pollTimer?.cancel();

    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_currentCid == null) return;

      final response = await _supportService.getChat(
        cid: _currentCid!,
        sinceId: _lastMessageId,
      );

      if (response.success && response.messages.isNotEmpty) {
        setState(() {
          _messages.addAll(response.messages);
          _lastMessageId = response.messages.last.id;
        });

        // 運営からの返信（role=admin）が来たら通知
        final adminReplies = response.messages.where((m) => m.role == 'admin');
        if (adminReplies.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('運営からの返信が届きました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    });
  }

  /// 定期ポーリングを停止
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _send({required bool urgent, required int coinCost, int? gemCost}) async {
    if (_controller.text.trim().isEmpty) return;

    // コイン/ジェムの残高チェック
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

    setState(() => _isLoading = true);

    // ユーザーIDを取得（簡易実装、実際は認証から取得）
    final prefs = await SharedPreferences.getInstance();
    String userId = prefs.getString('user_id') ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    if (!prefs.containsKey('user_id')) {
      await prefs.setString('user_id', userId);
    }

    // 診断結果を取得（渡されていない場合は空の辞書）
    final diagnosis = widget.diagnosis ?? {};

    // チャットメッセージを作成
    final chat = [
      ChatMessage(role: 'user', text: _controller.text.trim()),
    ];

    // 既存のメッセージも含める
    chat.addAll(_messages);

    // サーバーに送信
    final response = await _supportService.sendSupport(
      userId: userId,
      diagnosis: diagnosis,
      chat: chat,
      cid: _currentCid,
      meta: {
        'urgent': urgent,
        'cost': urgent ? (gemCost ?? 0) : coinCost,
      },
    );

    setState(() => _isLoading = false);

    if (response.success && response.cid != null) {
      // 送信したメッセージをUIに追加
      setState(() {
        _messages.add(ChatMessage(role: 'user', text: _controller.text.trim()));
        _currentCid = response.cid;
      });

      // 定期ポーリングを開始
      _startPolling(response.cid!);

      // 開発者へGmail通知（メールブリッジ）。URL未設定時は本番URL or ローカルを使用
      final savedUrl = prefs.getString(AuraFaceChatMailService.prefKeyBaseUrl);
      try {
        final mailService = AuraFaceChatMailService(baseUrl: savedUrl);
        final chatId = 'consultation_new_${userId}_${DateTime.now().millisecondsSinceEpoch}';
        await mailService.send(
          userId: userId,
          chatId: chatId,
          message: _controller.text.trim(),
          userName: '占い相談ユーザー',
          userEmail: '',
        );
      } catch (_) {}

      _controller.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(urgent ? '至急相談を送信しました（消費: ${gemCost ?? 0} ジェム）' : '通常相談を送信しました（消費: $coinCost コイン）'),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('送信に失敗しました: ${response.error ?? "不明なエラー"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('占い相談')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.email_outlined, size: 20),
              label: const Text('開発者にメールで相談（Gmail通知・返信が届く）'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConsultationMailBridgeTestPage()),
              ),
            ),
            const SizedBox(height: 16),

            // チャット表示エリア
            if (_messages.isNotEmpty) ...[
              Expanded(
                child: Card(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg.role == 'user';
                      final isAdmin = msg.role == 'admin';

                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Colors.blue.shade300
                                : (isAdmin ? Colors.green.shade300 : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg.text,
                                style: const TextStyle(color: Colors.black87),
                              ),
                              if (msg.createdAt != null)
                                Text(
                                  msg.createdAt!.substring(0, 19),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.black54,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 入力エリア
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

            // 送信ボタン
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.chat),
                      onPressed: _coins >= 20 ? () => _send(urgent: false, coinCost: 20, gemCost: null) : null,
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
                      onPressed: _gems >= 5 ? () => _send(urgent: true, coinCost: 0, gemCost: 5) : null,
                      label: const Text('至急相談(5ジェム)'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
