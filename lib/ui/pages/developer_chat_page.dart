import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/currency_service.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';

/// メールブリッジ（kami_chat_server）上のスレッドで、開発者返信の確認・追記。
class DeveloperChatPage extends StatefulWidget {
  const DeveloperChatPage({super.key});

  @override
  State<DeveloperChatPage> createState() => _DeveloperChatPageState();
}

class _DeveloperChatPageState extends State<DeveloperChatPage> {
  final _input = TextEditingController();
  List<BridgeChatMessage> _messages = [];
  String? _chatId;
  String _userId = '';
  /// メールブリッジの実効 URL（リリースでは本番固定。consultation_page と同じ）
  String? _bridgeBaseUrl;
  bool _loading = true;
  String? _error;
  Timer? _poll;
  int _coins = 0;

  static const int _kFollowUpCoinCost = 20;

  int get _userMessageCount => _messages.where((m) => m.role == 'user').length;

  bool get _requiresCoinForNextSend => _userMessageCount >= 1;

  /// 先頭のユーザー発言の種別（サーバー保存値）。無い場合は至急ではない。
  bool _threadOpensWithPriority(List<BridgeChatMessage> list) {
    for (final m in list) {
      if (m.role != 'user') continue;
      return m.consultationType?.trim() == ConsultationMailType.priorityGuidance;
    }
    return false;
  }

  /// 追記メールの consultationType: **スレッド上の先頭 user を最優先**（プリファだけだと未設定で常に通常になるのが繰り返しの原因）
  Future<String> _followUpConsultationTypeFor(List<BridgeChatMessage> list) async {
    for (final m in list) {
      if (m.role != 'user') continue;
      final c = m.consultationType?.trim();
      if (c == ConsultationMailType.priorityGuidance) {
        return ConsultationMailType.priorityGuidance;
      }
      if (c == ConsultationMailType.normal) {
        return ConsultationMailType.normal;
      }
      break;
    }
    return await DeveloperChatPref.getActiveConsultationType() ?? ConsultationMailType.normal;
  }

  AuraFaceChatMailService get _service =>
      AuraFaceChatMailService(baseUrl: _bridgeBaseUrl);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id') ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    if (!prefs.containsKey('user_id')) await prefs.setString('user_id', _userId);
    final saved = prefs.getString(AuraFaceChatMailService.prefKeyBaseUrl);
    _bridgeBaseUrl = AuraFaceChatMailService.consultationSendBaseUrl(saved);
    _chatId = await DeveloperChatPref.getActiveChatId();
    if (!mounted) return;
    if (_chatId == null || _chatId!.isEmpty) {
      setState(() {
        _loading = false;
        _messages = [];
      });
      return;
    }
    await _loadThread(markRead: true, silent: false);
    _poll?.cancel();
    _poll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadThread(markRead: true, silent: true),
    );
  }

  int _maxDevCreatedAt(Iterable<BridgeChatMessage> list) {
    var max = 0;
    for (final m in list) {
      if (m.isFromDev && m.createdAt > max) max = m.createdAt;
    }
    return max;
  }

  Future<void> _loadThread({required bool markRead, bool silent = false}) async {
    if (_chatId == null || _chatId!.isEmpty) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await _service.getThread(chatId: _chatId!);
    if (!mounted) return;
    if (!res.success) {
      final wallet = await CurrencyService.load();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = res.error ?? '取得に失敗しました';
        _coins = wallet['coins'] ?? 0;
      });
      return;
    }
    final sorted = List<BridgeChatMessage>.from(res.messages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (markRead) {
      final maxDev = _maxDevCreatedAt(sorted);
      if (maxDev > 0) await DeveloperChatPref.setLastSeenDevCreatedAt(maxDev);
    }
    if (_chatId != null && _chatId!.isNotEmpty) {
      final syncType = await _followUpConsultationTypeFor(sorted);
      await DeveloperChatPref.setActiveChatId(_chatId!, consultationType: syncType);
    }
    final wallet = await CurrencyService.load();
    if (!mounted) return;
    setState(() {
      _messages = sorted;
      _loading = false;
      _error = null;
      _coins = wallet['coins'] ?? 0;
    });
  }

  Future<void> _sendFollowUp() async {
    final text = _input.text.trim();
    if (text.isEmpty || _chatId == null || _loading) return;

    final needsPay = _requiresCoinForNextSend;
    if (needsPay) {
      final w = await CurrencyService.load();
      _coins = w['coins'] ?? 0;
      if (!mounted) return;
      if (_coins < _kFollowUpCoinCost) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_kFollowUpCoinCostコインが必要です（現在: $_coins）'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        return;
      }
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('コイン消費の確認'),
              content: Text(
                '2通目以降の送信には $_kFollowUpCoinCost コインがかかります。\n'
                '（残高: $_coins コイン）\n\n送信しますか？',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('送信する')),
              ],
            ),
          ) ??
          false;
      if (!ok || !mounted) return;
    }

    setState(() => _loading = true);
    int charged = 0;
    try {
      if (needsPay) {
        await CurrencyService.useCoins(_kFollowUpCoinCost);
        charged = _kFollowUpCoinCost;
        final w = await CurrencyService.load();
        if (mounted) setState(() => _coins = w['coins'] ?? 0);
      }

      final mailConsultationType = await _followUpConsultationTypeFor(_messages);
      final res = await _service.send(
        userId: _userId,
        chatId: _chatId!,
        message: text,
        userName: '占い相談ユーザー',
        userEmail: '',
        consultationType: mailConsultationType,
      );
      if (!mounted) return;
      if (!res.success) {
        if (charged > 0) {
          await CurrencyService.addCoins(charged);
          final w = await CurrencyService.load();
          if (mounted) setState(() => _coins = w['coins'] ?? 0);
        }
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信に失敗しました: ${res.error ?? ""}')),
        );
        return;
      }
      _input.clear();
      await _loadThread(markRead: true, silent: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              needsPay ? '送信しました（$_kFollowUpCoinCostコイン消費）' : '送信しました',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (charged > 0) {
        await CurrencyService.addCoins(charged);
        final w = await CurrencyService.load();
        if (mounted) setState(() => _coins = w['coins'] ?? 0);
      }
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('開発者とのやりとり'),
        actions: [
          IconButton(
            tooltip: '更新',
            onPressed: _chatId == null ? null : () => _loadThread(markRead: true, silent: false),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _chatId == null || _chatId!.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mark_chat_unread_outlined, size: 64, color: Colors.grey.shade600),
                    const SizedBox(height: 16),
                    Text(
                      'まだ相談を送信していません。',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '「占い相談」から内容を送ると、開発者からの返信をここで確認できます。',
                      style: TextStyle(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(_error!, style: TextStyle(color: Colors.orange.shade200)),
                        ),
                        TextButton(
                          onPressed: () => _loadThread(markRead: true, silent: false),
                          child: const Text('再試行'),
                        ),
                      ],
                    ),
                  ),
                if (!_loading &&
                    _messages.isNotEmpty &&
                    _threadOpensWithPriority(_messages))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade900.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade700),
                      ),
                      child: Text(
                        'このスレッドは占い相談の「至急」で始まっています。'
                        '追記メールも【至急占い】件名で届きます（サーバーに保存された種別に従います）。',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade100,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: _loading && _messages.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) {
                            final m = _messages[i];
                            final isDev = m.isFromDev;
                            return Align(
                              alignment: isDev ? Alignment.centerLeft : Alignment.centerRight,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
                                decoration: BoxDecoration(
                                  color: isDev
                                      ? Colors.teal.shade800.withOpacity(0.35)
                                      : Colors.deepPurple.withOpacity(0.35),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(14),
                                    topRight: const Radius.circular(14),
                                    bottomLeft: Radius.circular(isDev ? 4 : 14),
                                    bottomRight: Radius.circular(isDev ? 14 : 4),
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.12),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isDev ? '開発者' : 'あなた',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withOpacity(0.7),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      m.text,
                                      style: const TextStyle(fontSize: 15, height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_loading)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _requiresCoinForNextSend
                                  ? '2通目以降の送信: $_kFollowUpCoinCost コイン（残高 $_coins）'
                                  : '初回の追記は無料です（残高 $_coins コイン）',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade100.withOpacity(0.9),
                              ),
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                minLines: 1,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  hintText: _requiresCoinForNextSend
                                      ? '追記・返信（送信時に $_kFollowUpCoinCost コイン）'
                                      : '追記・返信を入力',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _loading ? null : () => _sendFollowUp(),
                              child: Icon(
                                _requiresCoinForNextSend ? Icons.send : Icons.send_outlined,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
