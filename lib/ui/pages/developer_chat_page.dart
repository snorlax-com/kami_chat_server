import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/bridge_thread_local_store.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/consultation_identity.dart';
import 'package:kami_face_oracle/services/consultation_mail_new_send.dart';
import 'package:kami_face_oracle/services/consultation_access_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/config/consultation_send_contract.dart';
import 'package:kami_face_oracle/ui/pages/store_page.dart';
import 'package:kami_face_oracle/services/pillar_interaction_seed_store.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/services/push_notification_service.dart';
import 'package:kami_face_oracle/services/consultation_tab_visibility.dart';
import 'package:kami_face_oracle/services/developer_reply_notify_service.dart';
import 'package:kami_face_oracle/services/consultation_active_thread_resolver.dart';
import 'package:kami_face_oracle/services/store_access_service.dart';
import 'package:kami_face_oracle/services/store_subscription_flow.dart';
import 'package:kami_face_oracle/services/consultation_send_history_service.dart';
import 'package:kami_face_oracle/services/store_ui_helper.dart';

String? _resolvedTierFromBridge(SendChatResponse? bridge) {
  final d = bridge?.sendDebug?['debugResolvedConsultationType']?.toString().trim();
  if (d != null && d.isNotEmpty) return d;
  return bridge?.consultationType?.trim();
}

void _showMailSentFeedback(
  BuildContext context, {
  required bool useFirestore,
  required String coinLine,
  required bool urgent,
  required bool mailSent,
  SendChatResponse? bridge,
}) {
  if (!mailSent) return;

  final resolvedTier = _resolvedTierFromBridge(bridge);
  if (urgent && resolvedTier == ConsultationMailType.normal) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$coinLine\n'
          '【不整合】サーバーは「通常相談」として処理した応答を返しています。'
          'Gmail 件名も【通常相談】の可能性があります。kami_chat_server のデプロイを確認してください。',
        ),
        backgroundColor: Colors.red.shade900,
        duration: const Duration(seconds: 16),
      ),
    );
    return;
  }

  final buildTag = (bridge?.mailApiBuild ?? '').trim();
  final v2 = buildTag.contains('v2-consultation-tier');
  final ct = (bridge?.consultationType ?? '').trim();
  final serverPriority = bridge?.mailUrgent == true || ct == ConsultationMailType.priorityGuidance;
  final explicitServerNormal = bridge?.mailUrgent == false ||
      (ct == ConsultationMailType.normal && bridge?.mailUrgent != true);

  if (urgent && v2 && explicitServerNormal && !serverPriority) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$coinLine。\n'
          '【要確認】サーバーは「通常メール」として送信した応答です。Render の kami_chat_server を最新版にしてください。',
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
          '$coinLine。メールは送信されました。'
          'Gmail 件名が至急用か、サーバーを最新化して確認してください。',
        ),
        backgroundColor: Colors.amber.shade800,
        duration: const Duration(seconds: 12),
      ),
    );
    return;
  }

  final extraUrgent = urgent && serverPriority
      ? ' Gmail 通知は至急用の分類で処理された応答です。'
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
        content: Text('$coinLine。開発者にメールで通知しました。$extraUrgent'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: urgent ? 8 : 4),
      ),
    );
  }
}

/// 占い相談（初回＝相談券）と開発者返信（メールブリッジ）のチャット。
class DeveloperChatPage extends StatefulWidget {
  const DeveloperChatPage({super.key, this.embedInShell = false});

  final bool embedInShell;

  @override
  State<DeveloperChatPage> createState() => _DeveloperChatPageState();
}

class _DeveloperChatPageState extends State<DeveloperChatPage> with WidgetsBindingObserver {
  final _input = TextEditingController();
  /// 占い相談スレッド用（reverse: true で最新が下＝offset 0）
  final ScrollController _scrollController = ScrollController();
  final _pillarScrollController = ScrollController();

  /// 通常のメッセージアプリ同様、最新が画面下に来る
  static const bool _chatListReversed = true;
  List<BridgeChatMessage> _messages = [];
  String? _chatId;
  String _userId = '';
  String? _bridgeBaseUrl;
  bool _loading = true;
  bool _bootstrapped = false;
  String? _error;
  Timer? _poll;
  int _normalTickets = 0;
  int _urgentTickets = 0;
  bool _isSubscribed = false;

  bool _sendingFirst = false;

  /// 初回相談前: 柱／チュートリアル用の先頭メッセージ
  List<PillarInteractionSeed> _pillarSeeds = [];

  int get _userMessageCount => _messages.where((m) => m.role == 'user').length;

  bool get _hasConsultationThread => _chatId != null && _chatId!.isNotEmpty;

  /// サーバーにメッセージがあるスレッドのみ開発者チャット表示（読込中は柱画面のまま）。
  bool get _showConsultationChat => _hasConsultationThread && _messages.isNotEmpty;

  bool _threadOpensWithPriority(List<BridgeChatMessage> list) {
    for (final m in list) {
      if (m.role != 'user') continue;
      return m.consultationType?.trim() == ConsultationMailType.priorityGuidance;
    }
    return false;
  }

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

  AuraFaceChatMailService get _service => AuraFaceChatMailService(baseUrl: _bridgeBaseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppNavigation.refreshConsultationChat.addListener(_onPushOpenRefresh);
    AppNavigation.scrollConsultationToLatest.addListener(_onConsultationTabShown);
    AppNavigation.registerConsultationDraftHandlers(
      save: () => unawaited(_persistConsultationDraft()),
      restore: () async {
        await _restoreConsultationDraft();
        await _loadAccessState();
      },
    );
    _bootstrap();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (_showConsultationChat && _messages.isNotEmpty) {
      _scrollToBottom(animated: false);
    }
  }

  void _onPushOpenRefresh() {
    if (!mounted) return;
    unawaited(_refreshThreadAndPillar(resolveLatest: false));
  }

  void _onConsultationTabShown() {
    if (!mounted) return;
    unawaited(_restoreConsultationDraft());
    unawaited(_loadAccessState());
    unawaited(_reloadActiveThread(scrollAfterLoad: true));
  }

  Future<void> _persistConsultationDraft() async {
    await DeveloperChatPref.saveConsultationDraft(_input.text);
  }

  Future<void> _restoreConsultationDraft() async {
    final draft = await DeveloperChatPref.getConsultationDraft();
    if (!mounted || draft == null) return;
    if (_input.text == draft) return;
    _input.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  /// 最新メッセージ付近へスクロール（reverse リストでは offset 0 が最下部）。
  void _scrollToBottom({bool animated = true, int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        if (attempt < 24) {
          _scrollToBottom(animated: animated, attempt: attempt + 1);
        }
        return;
      }

      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 32 + attempt * 24));
      }
      if (!mounted || !_scrollController.hasClients) return;

      final position = _scrollController.position;
      final target = _chatListReversed ? position.minScrollExtent : position.maxScrollExtent;

      try {
        if (animated && (target - position.pixels).abs() > 2) {
          await position.animateTo(
            target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          position.jumpTo(target);
        }
      } catch (_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(target);
        }
      }

      // レイアウト確定後にもう一度（長いスレッドで maxExtent が遅れて伸びる場合）
      if (attempt < 4) {
        _scrollToBottom(animated: false, attempt: attempt + 1);
      }
    });
  }

  /// 送信・ピン留め済みのスレッドを表示（古いスレッドへ切り替えない）。
  Future<void> _switchToChatId(
    String chatId, {
    bool pin = false,
    String? consultationType,
  }) async {
    final type = consultationType ??
        await DeveloperChatPref.getActiveConsultationType() ??
        ConsultationMailType.normal;
    await DeveloperChatPref.setActiveChatId(
      chatId,
      consultationType: type,
      pin: pin,
    );
    final local = await BridgeThreadLocalStore.load(chatId);
    if (!mounted) return;
    setState(() {
      _chatId = chatId;
      _messages = local;
      _error = null;
    });
    if (local.isNotEmpty) _scrollToBottom(animated: false);
  }

  Future<void> _reloadActiveThread({bool scrollAfterLoad = true}) async {
    final activeId = await DeveloperChatPref.getActiveChatId();
    if (activeId == null || activeId.isEmpty) return;
    if (activeId != _chatId) {
      await _switchToChatId(activeId);
    }
    await _loadThread(silent: true, scrollToLatest: scrollAfterLoad);
  }

  /// 柱のみのリスト末尾へ。
  void _scrollPillarToLatest({bool animated = true, int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_pillarScrollController.hasClients) {
        if (attempt < 4) _scrollPillarToLatest(animated: animated, attempt: attempt + 1);
        return;
      }
      final position = _pillarScrollController.position;
      final target = position.maxScrollExtent;
      if (animated) {
        unawaited(
          position.animateTo(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        position.jumpTo(target);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppNavigation.refreshConsultationChat.removeListener(_onPushOpenRefresh);
    AppNavigation.scrollConsultationToLatest.removeListener(_onConsultationTabShown);
    AppNavigation.unregisterConsultationDraftHandlers();
    _poll?.cancel();
    _scrollController.dispose();
    _pillarScrollController.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadAccessState() async {
    await ConsultationTicketPacksService.ensureLoaded();
    final state = await ConsultationAccessService.loadState();
    if (!mounted) return;
    setState(() {
      _isSubscribed = state.isSubscribed;
      _normalTickets = state.normalTickets;
      _urgentTickets = state.urgentTickets;
    });
  }

  Future<void> _reloadPillarSeeds() async {
    final seeds = await PillarInteractionSeedStore.loadForDisplay();
    if (!mounted) return;
    setState(() => _pillarSeeds = seeds);
    debugPrint('[DeveloperChat] pillar seeds loaded: ${seeds.length} showThread=$_showConsultationChat');
  }

  Future<void> _refreshThreadAndPillar({bool resolveLatest = false}) async {
    if (resolveLatest) {
      await ConsultationActiveThreadResolver.applyLatestAsActive(bridgeUserId: _userId);
      final id = await DeveloperChatPref.getActiveChatId();
      if (id != null && id.isNotEmpty) await _switchToChatId(id);
    }
    await _reloadPillarSeeds();
    if (!mounted) return;
    await _loadThread(silent: false, scrollToLatest: true);
  }

  /// チャット行（開発者／柱／あなた）
  Widget _chatMessageBubble({
    required bool isLeft,
    required String roleLabel,
    required String text,
    required bool pillarLeftStyle,
  }) {
    return Align(
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        decoration: BoxDecoration(
          color: isLeft
              ? (pillarLeftStyle
                  ? const Color(0xFF5B21B6).withValues(alpha: 0.38)
                  : Colors.teal.shade800.withValues(alpha: 0.35))
              : Colors.deepPurple.withValues(alpha: 0.35),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isLeft ? 4 : 14),
            bottomRight: Radius.circular(isLeft ? 14 : 4),
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roleLabel,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              text,
              style: const TextStyle(fontSize: 15, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  /// 開発者とのやり取り（時系列・開いたら末尾＝最新へスクロール）
  Widget _buildActiveThreadMessages() {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'この相談スレッドにはまだメッセージがありません。',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    }
    return ListView.builder(
      key: ValueKey<String>('chat_${_chatId ?? "none"}'),
      controller: _scrollController,
      reverse: _chatListReversed,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final m = _chatListReversed
            ? _messages[_messages.length - 1 - index]
            : _messages[index];
        return _chatMessageBubble(
          isLeft: m.isFromDev,
          roleLabel: m.isFromDev ? '開発者' : 'あなた',
          text: m.text,
          pillarLeftStyle: false,
        );
      },
    );
  }

  /// 相談前: 柱との会話のみ
  Widget _buildPillarOnlyScroll() {
    final showOnlySpinner = _loading && _pillarSeeds.isEmpty;
    if (showOnlySpinner) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      controller: _pillarScrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _pillarSeeds.length,
      itemBuilder: (_, i) {
        final s = _pillarSeeds[i];
        return _chatMessageBubble(
          isLeft: !s.isUser,
          roleLabel: s.isUser ? 'あなた' : '柱',
          text: s.text,
          pillarLeftStyle: !s.isUser,
        );
      },
    );
  }

  Widget _buildThreadScrollBody() {
    if (_showConsultationChat) {
      return _buildActiveThreadMessages();
    }
    return _buildPillarOnlyScroll();
  }

  /// 初回相談前・スレッド追記で共通の入力欄（通常チャットと同じ見た目）。
  Widget _buildMessageComposer(double viewInsetsBottom) {
    final inThread = _showConsultationChat;
    final sendDisabled = inThread ? _loading : _sendingFirst;
    final canSend = _isSubscribed && !sendDisabled;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsetsBottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_loading) ...[
                Text(
                  _isSubscribed ? 'サブスク: 加入中' : 'サブスク: 未加入',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isSubscribed ? Colors.lightGreenAccent : Colors.orange.shade200,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '通常券: $_normalTickets 枚 / 至急券: $_urgentTickets 枚',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber.shade100.withValues(alpha: 0.9),
                  ),
                ),
                if (!_isSubscribed) ...[
                  const SizedBox(height: 8),
                  Text(
                    '質問するには月額500円のサブスク加入が必要です',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade100),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: () => unawaited(_startSubscriptionPurchase()),
                      child: const Text('サブスクに加入'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      enabled: _isSubscribed,
                      decoration: InputDecoration(
                        hintText: _isSubscribed
                            ? 'メッセージを入力（送信時に券1枚）'
                            : 'サブスク加入後に質問できます',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: canSend ? () => unawaited(_onSendPressed()) : null,
                    child: const Icon(Icons.send, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = await ConsultationIdentity.bridgeUserIdOrLegacy();
    await prefs.setString('user_id', _userId);
    final saved = prefs.getString(AuraFaceChatMailService.prefKeyBaseUrl);
    _bridgeBaseUrl = AuraFaceChatMailService.consultationSendBaseUrl(saved);
    // 相談スレッド有無に関わらず、柱／チュートリアル用の先頭行は常に読み込む
    await _loadAccessState();
    final seeds = await PillarInteractionSeedStore.loadForDisplay();
    await ConsultationActiveThreadResolver.applyLatestAsActive(bridgeUserId: _userId);
    _chatId = await DeveloperChatPref.getActiveChatId();
    if (!mounted) return;
    if (_chatId == null || _chatId!.isEmpty) {
      setState(() {
        _bootstrapped = true;
        _loading = false;
        _messages = [];
        _pillarSeeds = seeds;
      });
      _scrollPillarToLatest(animated: false);
      await _restoreConsultationDraft();
      return;
    }
    final local = await BridgeThreadLocalStore.load(_chatId!);
    if (!mounted) return;
    setState(() {
      _pillarSeeds = seeds;
      if (local.isNotEmpty) _messages = local;
    });
    if (local.isNotEmpty) _scrollToBottom(animated: false);
    await _loadThread(silent: false, scrollToLatest: true);
    if (!mounted) return;
    setState(() => _bootstrapped = true);
    _scrollToBottom(animated: true);
    _startThreadPolling();
    unawaited(PushNotificationService.instance.syncTokenNow());
    await _restoreConsultationDraft();
  }

  void _startThreadPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadThread(silent: true),
    );
  }

  static bool _isLocalhostUrl(String url) {
    final u = url.trim().toLowerCase();
    return u.startsWith('http://127.0.0.1') ||
        u.startsWith('http://localhost') ||
        u.startsWith('https://127.0.0.1') ||
        u.startsWith('https://localhost');
  }

  int _maxDevCreatedAt(Iterable<BridgeChatMessage> list) {
    var max = 0;
    for (final m in list) {
      if (m.isFromDev && m.createdAt > max) max = m.createdAt;
    }
    return max;
  }

  static String _retentionNoticePrefsKey(String chatId) => 'bridge_retention_notice_shown_v1_$chatId';

  Future<void> _maybeShowRetentionNotice(ThreadResponse res) async {
    if (!res.retentionExpired) return;
    if (_chatId == null || _chatId!.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _retentionNoticePrefsKey(_chatId!);
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('メッセージの保存期間'),
        content: const Text(
          '90日が経過したため、サーバー上の以前のメッセージは削除されました。\n'
          '別の端末に変えた場合や、しばらくログインしていなかった場合にも同様です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadThread({bool silent = false, bool scrollToLatest = false}) async {
    if (_chatId == null || _chatId!.isEmpty) return;
    final previousCount = _messages.length;
    final cid = _chatId!;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
        _messages = [];
      });
      final preview = await BridgeThreadLocalStore.load(cid);
      if (mounted && preview.isNotEmpty) {
        setState(() => _messages = preview);
        _scrollToBottom(animated: false);
      }
    }
    final local = await BridgeThreadLocalStore.load(cid);
    final res = await _service.getThread(chatId: cid);
    if (!mounted) return;
    if (!res.success) {
      final offline = BridgeThreadLocalStore.merge(local, []);
      await _loadAccessState();
      if (!mounted) return;
      if (offline.isNotEmpty) {
        setState(() {
          _messages = offline;
          _loading = false;
          _error = res.error ?? '取得に失敗しました（端末に保存された分のみ表示）';
        });
        _scrollToBottom(animated: scrollToLatest || !silent);
        return;
      }
      setState(() {
        _loading = false;
        _error = res.error ?? '取得に失敗しました';
      });
      return;
    }
    final sorted = BridgeThreadLocalStore.merge(local, res.messages);
    await BridgeThreadLocalStore.save(cid, sorted);
    await _maybeShowRetentionNotice(res);
    final maxDev = _maxDevCreatedAt(sorted);
    await DeveloperReplyNotifyService.notifyIfNeeded(
      chatId: cid,
      maxDevCreatedAt: maxDev,
    );
    if (ConsultationTabVisibility.userIsViewingConsultation && maxDev > 0) {
      await DeveloperChatPref.setLastSeenDevCreatedAt(maxDev);
    }
    if (_chatId != null && _chatId!.isNotEmpty) {
      final syncType = await _followUpConsultationTypeFor(sorted);
      await DeveloperChatPref.setActiveChatId(_chatId!, consultationType: syncType);
    }
    await _loadAccessState();
    if (!mounted) return;
    setState(() {
      _messages = sorted;
      _loading = false;
      _error = null;
    });
    if (_messages.isNotEmpty &&
        (scrollToLatest || !silent || sorted.length > previousCount)) {
      _scrollToBottom(animated: scrollToLatest || !silent);
    }
  }

  void _navigateToStoreTab() {
    if (!mounted) return;
    unawaited(_openStoreIfSubscribed());
  }

  Future<void> _openStoreIfSubscribed() async {
    if (!await StoreAccessService.canOpenStore()) {
      await _startSubscriptionPurchase();
      return;
    }
    if (!mounted) return;
    if (widget.embedInShell) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNavigation.switchMainTab(AppNavigation.tabStore);
        AppNavigation.refreshStoreTab.value++;
      });
      return;
    }
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(builder: (_) => const StorePage()),
    );
    await _restoreConsultationDraft();
    await _loadAccessState();
  }

  Future<void> _startSubscriptionPurchase() async {
    await StoreSubscriptionFlow.purchase(context);
    await _loadAccessState();
  }

  /// 送信ボタン共通（サブスク + 券で1回送信）。
  Future<void> _onSendPressed() async {
    if (_input.text.trim().isEmpty) return;
    if (_sendingFirst) return;
    if (_showConsultationChat && _loading) return;

    final state = await ConsultationAccessService.loadState();
    if (!mounted) return;
    setState(() {
      _isSubscribed = state.isSubscribed;
      _normalTickets = state.normalTickets;
      _urgentTickets = state.urgentTickets;
    });

    if (!state.isSubscribed) {
      await _promptSubscriptionRequired();
      return;
    }

    ConsultationSendTicketKind? ticketKind;
    if (_showConsultationChat) {
      final mailType = await _followUpConsultationTypeFor(_messages);
      ticketKind = ConsultationAccessService.resolveFollowUpTicketKind(state, mailType);
    } else {
      ticketKind = ConsultationAccessService.resolveSendTicketKind(state);
    }

    if (ticketKind == null) {
      await _promptPurchaseTicketChoice();
      return;
    }

    if (ticketKind == ConsultationSendTicketKind.normal) {
      final err = await ConsultationTicketService.validateNormalSend();
      if (err != null) {
        await _promptPurchaseTicketChoice();
        return;
      }
    } else {
      final err = await ConsultationTicketService.validateUrgentTicketSend();
      if (err != null) {
        await _promptPurchaseTicketChoice();
        return;
      }
    }

    if (_showConsultationChat) {
      await _sendFollowUp(ticketKind: ticketKind);
    } else {
      await _sendFirstConsultation(
        urgent: ticketKind == ConsultationSendTicketKind.urgent,
        ticketKind: ticketKind,
      );
    }
  }

  Future<void> _promptSubscriptionRequired() async {
    if (!mounted) return;
    final go = await StoreUiHelper.confirm(
      title: 'サブスク加入が必要です',
      body: '質問するには月額500円のサブスク加入が必要です。\n初回加入時に通常質問1回券をプレゼントします。',
      confirmLabel: 'サブスクに加入',
      cancelLabel: '閉じる',
      fallbackContext: context,
    );
    if (!go || !mounted) return;
    await _persistConsultationDraft();
    await _startSubscriptionPurchase();
  }

  Future<void> _promptPurchaseTicketChoice() async {
    if (!mounted) return;
    if (!await StoreAccessService.canPurchaseConsultationTickets()) {
      await StoreAccessService.guardTicketPurchase(context);
      return;
    }
    await ConsultationTicketPacksService.ensureLoaded();
    final normal = ConsultationTicketPacksService.normalTicketProduct;
    final urgent = ConsultationTicketPacksService.urgentTicketProduct;
    final normalPrice = normal?.referencePriceYen != null ? '¥${normal!.referencePriceYen}' : '¥600';
    final urgentPrice = urgent?.referencePriceYen != null ? '¥${urgent!.referencePriceYen}' : '¥10,000';

    final choice = await showDialog<String>(
          context: StoreUiHelper.rootContext ?? context,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            title: const Text('質問券が必要です'),
            content: Text(
              '通常券または至急券を購入してください。\n\n'
              '1. ${normal?.name ?? '通常質問券'}: $normalPrice\n'
              '2. ${urgent?.name ?? '至急質問券'}: $urgentPrice',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'normal'),
                child: Text('通常券 $normalPrice'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'urgent'),
                child: Text('至急券 $urgentPrice'),
              ),
            ],
          ),
        );

    if (!mounted || choice == null) return;
    await _persistConsultationDraft();
    _navigateToStoreTab();
  }

  Future<void> _openStoreAfterOffer({required String title, required String body}) async {
    if (!mounted) return;
    final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('閉じる'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ストアを開く'),
              ),
            ],
          ),
        ) ??
        false;
    if (!go || !mounted) return;
    await _persistConsultationDraft();
    await _openStoreIfSubscribed();
  }

  Future<void> _sendFirstConsultation({
    required bool urgent,
    required ConsultationSendTicketKind ticketKind,
  }) async {
    if (_input.text.trim().isEmpty) return;
    if (_sendingFirst) return;

    final fbUser = await ConsultationIdentity.requireFirebaseUserForConsultation(context);
    if (fbUser == null) return;

    final useFirestore = CloudService.isAvailable;

    setState(() => _sendingFirst = true);

    final trimmedBody = _input.text.trim();
    final bodyText =
        AuraFaceChatMailService.applyNewUrgentConsultationPrefix(urgent: urgent, message: trimmedBody);

    if (useFirestore) {
      await CloudService.addConsultation(bodyText, urgent: urgent, cost: 1);
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = fbUser.uid;
    await prefs.setString('user_id', userId);
    final savedUrl = prefs.getString(AuraFaceChatMailService.prefKeyBaseUrl);
    final bridgeUrl = AuraFaceChatMailService.consultationSendBaseUrl(savedUrl);
    debugPrint('[DeveloperChat] mail bridge url=$bridgeUrl');

    var mailSuccess = false;
    bool? mailSentReport;
    SendChatResponse? mailBridgeRes;
    final String bridgeForCatch = bridgeUrl;

    try {
      final mailService = AuraFaceChatMailService(baseUrl: bridgeUrl);
      final chatId = 'consultation_${userId}_${DateTime.now().millisecondsSinceEpoch}';
      final mailCt = ConsultationMailNewSend.consultationTypeForPref(urgent: urgent);
      final fcmToken = await PushNotificationService.instance.getCachedFcmToken();
      final res = await ConsultationMailNewSend.send(
        mailService: mailService,
        userId: userId,
        chatId: chatId,
        message: bodyText,
        sendSource: ConsultationSendSource.consultationPage,
        urgent: urgent,
        userName: '占い相談ユーザー',
        userEmail: '',
        fcmToken: fcmToken,
        fcmPlatform: 'android',
      );
      mailBridgeRes = res;
      mailSuccess = res.success;
      mailSentReport = res.mailSent;
      if (res.success) {
        await BridgeThreadLocalStore.appendUserMessage(
          chatId: chatId,
          text: bodyText,
          consultationType: mailCt,
          messageId: res.messageId,
        );
        await DeveloperChatPref.setActiveChatId(chatId, consultationType: mailCt, pin: true);
        if (mounted) {
          setState(() {
            _chatId = chatId;
            _bridgeBaseUrl = bridgeUrl;
          });
        }
        unawaited(PushNotificationService.instance.syncTokenNow());
      }
      if (res.success && res.mailSent == false && mounted) {
        final detail = res.mailError != null && res.mailError!.isNotEmpty ? '\n${res.mailError}' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'サーバーには保存されましたが、開発者へのGmail通知に失敗した可能性があります。$detail',
            ),
            backgroundColor: Colors.deepOrange,
            duration: const Duration(seconds: 10),
          ),
        );
      }
      if (!res.success && mounted) {
        final isLocal = _isLocalhostUrl(mailService.baseUrl) &&
            (res.error?.contains('Connection refused') ?? false);
        final message = isLocal
            ? '実機では 127.0.0.1 に接続できません。同じWi-Fi上の開発PCのIPを mail bridge の URL として指定してください。'
            : (useFirestore
                ? '相談は保存されましたが、通知メールの送信に失敗した可能性があります。'
                : '通知メールの送信に失敗した可能性があります。');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[DeveloperChat] mail exception: $e');
      debugPrint('[DeveloperChat] $st');
      if (mounted) {
        final isConfigError = e is StateError && e.message.contains('MAIL_BRIDGE_URL');
        final isLocal = e.toString().contains('Connection refused') && _isLocalhostUrl(bridgeForCatch);
        final message = isConfigError
            ? '開発者通知の接続先が設定されていない可能性があります。'
            : isLocal
                ? 'ローカルURLには接続できません。本番用URLを指定してください。'
                : (useFirestore
                    ? '相談の保存に成功したが、通知でエラーが出た可能性があります。'
                    : '通知の送信に失敗した可能性があります。');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingFirst = false);
      }
    }

    _input.clear();
    if (mailSuccess) {
      await ConsultationSendHistoryService.markFirstConsultationCompleted();
      if (ticketKind == ConsultationSendTicketKind.urgent) {
        await ConsultationTicketService.consumeUrgentTicket();
      } else {
        await ConsultationTicketService.consumeNormalTicket();
      }
      await _loadAccessState();
      await DeveloperChatPref.clearConsultationDraft();
    }
    if (mailSuccess && _chatId != null) {
      await _loadThread(silent: false, scrollToLatest: true);
      _scrollToBottom(animated: true);
      _startThreadPolling();
    }

    if (mounted && mailSuccess) {
      const coinLine = '送信しました';
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
                '$coinLine。メール通知の成否はサーバーから返っていないため、Gmailをご確認ください。',
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
            content: const Text('送信は記録されました。メール通知の詳細はサーバーにご確認ください。'),
            backgroundColor: Colors.amber.shade800,
            duration: Duration(seconds: 10),
          ),
        );
      }
    }
  }

  Future<void> _sendFollowUp({required ConsultationSendTicketKind ticketKind}) async {
    final text = _input.text.trim();
    if (text.isEmpty || _chatId == null || _loading) return;

    final fbUser = await ConsultationIdentity.requireFirebaseUserForConsultation(context);
    if (fbUser == null) return;

    setState(() => _loading = true);
    try {
      final mailConsultationType = await _followUpConsultationTypeFor(_messages);
      final res = await _service.send(
        userId: fbUser.uid,
        chatId: _chatId!,
        message: text,
        sendSource: ConsultationSendSource.developerChatFollowUp,
        userName: '占い相談ユーザー',
        userEmail: '',
        consultationType: mailConsultationType,
      );
      if (!mounted) return;
      if (!res.success) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信に失敗しました: ${res.error ?? ""}')),
        );
        return;
      }
      if (ticketKind == ConsultationSendTicketKind.urgent) {
        await ConsultationTicketService.consumeUrgentTicket();
      } else {
        await ConsultationTicketService.consumeNormalTicket();
      }
      await ConsultationSendHistoryService.markFirstConsultationCompleted();
      await _loadAccessState();
      await BridgeThreadLocalStore.appendUserMessage(
        chatId: _chatId!,
        text: text,
        consultationType: mailConsultationType,
        messageId: res.messageId,
      );
      await DeveloperChatPref.setActiveChatId(
        _chatId!,
        consultationType: mailConsultationType,
        pin: true,
      );
      _input.clear();
      await DeveloperChatPref.clearConsultationDraft();
      await _loadThread(silent: false, scrollToLatest: true);
      _scrollToBottom(animated: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ticketKind == ConsultationSendTicketKind.urgent
                  ? '送信しました（至急券1枚）'
                  : '送信しました（通常券1枚）',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
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
    if (!_bootstrapped) {
      return Scaffold(
        appBar: widget.embedInShell
            ? null
            : AppBar(title: const Text('占い相談')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final viewInsets = MediaQuery.viewInsetsOf(context);

    final mainBody = Column(
      children: [
        if (_sendingFirst && !_showConsultationChat) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(_error!, style: TextStyle(color: Colors.orange.shade200)),
                ),
                TextButton(
                  onPressed: _refreshThreadAndPillar,
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        if (_showConsultationChat &&
            !_loading &&
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
                'このスレッドは「至急」で始まっています。'
                '追記メールも至急扱いで届きます（サーバー保存の種別に従います）。',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade100,
                ),
              ),
            ),
          ),
        Expanded(child: _buildThreadScrollBody()),
        const Divider(height: 1),
        _buildMessageComposer(viewInsets.bottom),
      ],
    );

    if (widget.embedInShell) {
      return Column(
        key: const Key('e2e-consultation'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: const Color(0xFF0A0E1A).withValues(alpha: 0.95),
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: '会話を更新',
                    onPressed: _sendingFirst
                        ? null
                        : () async {
                            if (_showConsultationChat) {
                              await _refreshThreadAndPillar();
                            } else {
                              await _reloadPillarSeeds();
                              _scrollPillarToLatest();
                            }
                          },
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: mainBody),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('占い相談'),
        actions: [
          IconButton(
            tooltip: '会話を更新',
            onPressed: _sendingFirst
                ? null
                : () async {
                    if (_showConsultationChat) {
                      await _refreshThreadAndPillar();
                    } else {
                      await _reloadPillarSeeds();
                      _scrollPillarToLatest();
                    }
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: mainBody,
    );
  }
}
