// lib/ui/pages/consultation_mail_bridge_test_page.dart
// メール返信テスト: 送信 → Gmailの返信ページで返信 → アプリでポーリングして表示

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ConsultationMailBridgeTestPage extends StatefulWidget {
  const ConsultationMailBridgeTestPage({super.key});

  @override
  State<ConsultationMailBridgeTestPage> createState() => _ConsultationMailBridgeTestPageState();
}

class _ConsultationMailBridgeTestPageState extends State<ConsultationMailBridgeTestPage> {
  final _controller = TextEditingController();
  final _replyLinkController = TextEditingController();
  final _serverUrlController = TextEditingController();
  List<BridgeChatMessage> _messages = [];
  Timer? _pollTimer;
  String? _chatId;
  String _userId = 'user_unknown';
  String? _savedBaseUrl;
  bool _isLoading = false;
  int? _lastCreatedAt;

  AuraFaceChatMailService get _service =>
      AuraFaceChatMailService(baseUrl: _savedBaseUrl);

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _loadSavedBaseUrl();
    _chatId ??= 'app_test_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _controller.dispose();
    _replyLinkController.dispose();
    _serverUrlController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(AuraFaceChatMailService.prefKeyBaseUrl);
    if (mounted) {
      setState(() {
        _savedBaseUrl = url;
        if (url != null && url.isNotEmpty) _serverUrlController.text = url;
      });
    }
  }

  Future<void> _saveBaseUrl() async {
    String url = _serverUrlController.text.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    final prefs = await SharedPreferences.getInstance();
    if (url.isEmpty) {
      await prefs.remove(AuraFaceChatMailService.prefKeyBaseUrl);
      if (mounted) setState(() => _savedBaseUrl = null);
    } else {
      await prefs.setString(AuraFaceChatMailService.prefKeyBaseUrl, url);
      if (mounted) setState(() => _savedBaseUrl = url);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('サーバーURLを保存しました'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _testConnection() async {
    final url = _serverUrlController.text.trim();
    if (url.isNotEmpty) {
      await _saveBaseUrl();
      if (!mounted) return;
    }
    setState(() => _isLoading = true);
    final ok = await _service.testConnection();
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '接続できました' : '接続できません。通信環境をご確認ください。（初回は数十秒かかることがあります）'),
        backgroundColor: ok ? Colors.green : Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// 疎通確認: health → send(test-user, test-chat, テスト送信) → thread(test-chat)
  Future<void> _runConnectivityTest() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final logs = <String>[];
    try {
      final ok = await _service.testConnection();
      logs.add('health: ${ok ? "OK" : "NG"}');
      if (!ok) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('health NG'), backgroundColor: Colors.red),
        );
        return;
      }
      const testChatId = 'test-chat';
      final sendRes = await _service.send(
        userId: 'test-user',
        chatId: testChatId,
        message: 'テスト送信',
        userName: 'テストユーザー',
      );
      logs.add('send: ${sendRes.success ? "OK" : "NG ${sendRes.error}"}');
      if (!sendRes.success) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('send NG: ${sendRes.error}'), backgroundColor: Colors.red),
        );
        return;
      }
      final threadRes = await _service.getThread(chatId: testChatId);
      logs.add('thread: ${threadRes.success ? "OK ${threadRes.messages.length}件" : "NG ${threadRes.error}"}');
      if (mounted) {
        for (final line in logs) debugPrint('[疎通テスト] $line');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(threadRes.success
                ? '疎通OK: health→send→thread ${threadRes.messages.length}件'
                : 'thread NG: ${threadRes.error}'),
            backgroundColor: threadRes.success ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
        if (threadRes.success && threadRes.messages.isNotEmpty) {
          setState(() {
            _chatId = testChatId;
            _messages = List.from(threadRes.messages);
            _lastCreatedAt = threadRes.messages.map((e) => e.createdAt).fold<int>(0, (int a, int b) => a > b ? a : b);
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('user_id') ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    if (!prefs.containsKey('user_id')) await prefs.setString('user_id', id);
    if (mounted) setState(() => _userId = id);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (_chatId == null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchThread());
  }

  Future<void> _fetchThread() async {
    if (_chatId == null || !mounted) return;
    final res = await _service.getThread(chatId: _chatId!, since: _lastCreatedAt);
    if (!mounted) return;
    if (res.success && res.messages.isNotEmpty) {
      setState(() {
        for (final m in res.messages) {
          if (!_messages.any((e) => e.id == m.id)) _messages.add(m);
        }
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final maxTs = res.messages.map((e) => e.createdAt).fold<int>(0, (a, b) => a > b ? a : b);
        if (maxTs > 0) _lastCreatedAt = maxTs;
        final last = res.messages.last;
        if (last.isFromDev && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('開発者からの返信が届きました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _isLoading = true);

    final res = await _service.send(
      userId: _userId,
      chatId: _chatId!,
      message: text,
      userName: 'テストユーザー',
      userEmail: 'test@example.com',
    );

    setState(() => _isLoading = false);
    if (!mounted) return;

    if (res.success) {
      setState(() {
        _messages.add(BridgeChatMessage(
          id: res.messageId ?? 0,
          role: 'user',
          text: text,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        _lastCreatedAt = DateTime.now().millisecondsSinceEpoch;
      });
      _controller.clear();
      _startPolling();
      if (res.mailSent == false) {
        final detail = res.mailError != null && res.mailError!.isNotEmpty
            ? ' 詳細: ${res.mailError}'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'チャットはサーバーに保存しましたが、Gmail通知に失敗しました。'
              'Render に RESEND_API_KEY / ADMIN_EMAIL / MAIL_FROM / BASE_URL を設定して再デプロイしてください。$detail',
            ),
            backgroundColor: Colors.deepOrange,
            duration: const Duration(seconds: 10),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('送信しました。開発者Gmailに通知が届き、返信はこの画面に反映されます。'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      final err = res.error ?? '';
      String message;
      if (err.contains('タイムアウト')) {
        message = '応答が遅れています。Render 無料枠は初回に数十秒かかることがあります。しばらくして再度お試しください。';
      } else if (err.contains('通信不可') || err.contains('Connection') || err.contains('Failed host')) {
        message = 'サーバーに接続できません。通信環境をご確認のうえ、しばらくして再度お試しください。';
      } else {
        message = '送信失敗: $err';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _openReplyLinkOnPc() async {
    final url = _replyLinkController.text.trim();
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('メールの「返信ページを開く」のリンクを貼り付けてください')),
        );
      }
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('有効なURLを入力してください')),
        );
      }
      return;
    }
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ブラウザで開きました'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('このURLを開けませんでした')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('開けませんでした: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('メール返信テスト'),
        backgroundColor: const Color(0xFF8B5CF6),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // サーバーURL入力は開発時のみ表示。本番では kMailBridgeProductionUrl で接続先が決まるためユーザー入力不要。
            if (kDebugMode) ...[
              Card(
                color: Colors.blue.shade900.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '開発者用: サーバーURL（デバッグ時のみ表示）',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade200,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '現在の接続先: ${_savedBaseUrl ?? AuraFaceChatMailService.effectiveDefaultBaseUrl}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _serverUrlController,
                        decoration: const InputDecoration(
                          hintText: '例: http://192.168.1.10:3000',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 13),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isLoading ? null : _testConnection,
                              icon: const Icon(Icons.wifi_tethering, size: 18),
                              label: const Text('接続テスト'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saveBaseUrl,
                              icon: const Icon(Icons.save, size: 18),
                              label: const Text('保存'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _runConnectivityTest,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('疎通テスト (health→send→thread)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.cyanAccent,
                          side: BorderSide(color: Colors.cyanAccent.withOpacity(0.7)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 開発者用: メールの返信リンクをこのPCのブラウザで開く
            Card(
              color: Colors.grey.shade900,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '開発者用: このPCのブラウザで返信ページを開く',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade300),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _replyLinkController,
                      decoration: const InputDecoration(
                        hintText: 'メールの「返信ページを開く」のリンクを貼り付け',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _openReplyLinkOnPc,
                      icon: const Icon(Icons.open_in_browser, size: 20),
                      label: const Text('このPCで開く'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.cyanAccent,
                        side: BorderSide(color: Colors.cyanAccent.withOpacity(0.7)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'chatId: ${_chatId ?? "—"}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Text(
                        'メッセージを送信すると開発者Gmailに通知されます。\nメールの「返信ページを開く」から返信すると、ここに表示されます。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final isUser = m.role == 'user';
                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isUser ? Colors.blue.shade300 : Colors.green.shade300,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isUser ? 'あなた' : '開発者',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(m.text, style: const TextStyle(color: Colors.black87)),
                                if (m.createdAt > 0)
                                  Text(
                                    _formatTs(m.createdAt),
                                    style: TextStyle(fontSize: 10, color: Colors.black54),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'メッセージを入力',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton.icon(
                onPressed: _send,
                icon: const Icon(Icons.send),
                label: const Text('送信（Gmailに通知）'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTs(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
