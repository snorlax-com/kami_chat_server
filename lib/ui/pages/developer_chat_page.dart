import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/services/auraface_chat_mail_service.dart';
import 'package:kami_face_oracle/services/bridge_thread_local_store.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/consultation_identity.dart';
import 'package:kami_face_oracle/services/consultation_mail_new_send.dart';
import 'package:kami_face_oracle/services/consultation_access_service.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/config/consultation_mail_types.dart';
import 'package:kami_face_oracle/config/consultation_send_contract.dart';
import 'package:kami_face_oracle/ui/pages/store_page.dart';
import 'package:kami_face_oracle/services/billing_log.dart';
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
import 'package:kami_face_oracle/services/sideload_billing_service.dart';
import 'package:kami_face_oracle/config/store_billing_config.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/testing/e2e_diagnostics.dart';

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

  /// 送信済み・スレッド確定後は、サーバー GET が空でもメッセージ画面を維持する。
  bool _preferConsultationThreadUi = false;

  /// 端末キャッシュ反映前に一覧へ出す送信直後のユーザー発言。
  BridgeChatMessage? _optimisticUserBubble;

  /// 初回相談前: 柱／チュートリアル用の先頭メッセージ
  List<PillarInteractionSeed> _pillarSeeds = [];

  int get _userMessageCount => _visibleMessages.where((m) => m.role == 'user').length;

  bool get _hasConsultationThread => _chatId != null && _chatId!.isNotEmpty;

  List<BridgeChatMessage> get _visibleMessages {
    if (_messages.isNotEmpty) return _messages;
    final optimistic = _optimisticUserBubble;
    if (optimistic != null) return [optimistic];
    return _messages;
  }

  /// 相談スレッドあり、または送信後にメッセージ画面へ切り替え済み。
  bool get _showConsultationChat =>
      _hasConsultationThread &&
      (_visibleMessages.isNotEmpty || _preferConsultationThreadUi);

  void _log(String message) => developer.log(message, name: 'DeveloperChat');

  void _setOptimisticUserMessage({
    required String text,
    required String consultationType,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    _optimisticUserBubble = BridgeChatMessage(
      id: ts,
      role: 'user',
      text: text,
      createdAt: ts,
      consultationType: consultationType,
    );
  }

  void _clearOptimisticIfMerged(Iterable<BridgeChatMessage> list) {
    final optimistic = _optimisticUserBubble;
    if (optimistic == null) return;
    final norm = optimistic.text.trim();
    if (list.any((m) => m.role == 'user' && m.text.trim() == norm)) {
      _optimisticUserBubble = null;
    }
  }

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadAccessState());
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (_showConsultationChat && _visibleMessages.isNotEmpty) {
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
    _optimisticUserBubble = null;
    setState(() {
      _chatId = chatId;
      _messages = local;
      _error = null;
      if (local.isNotEmpty) _preferConsultationThreadUi = true;
    });
    if (local.isNotEmpty) _scrollToBottom(animated: false);
  }

  Future<void> _reloadActiveThread({bool scrollAfterLoad = true}) async {
    final pinned = await DeveloperChatPref.getPinnedChatId();
    final activeId = await DeveloperChatPref.getActiveChatId();
    final targetId = (pinned != null && pinned.isNotEmpty) ? pinned : activeId;
    if (targetId == null || targetId.isEmpty) return;
    if (targetId != _chatId) {
      await _switchToChatId(targetId);
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

  /// ローカル残高のみ（Play 同期なし・送信ボタン直後の判定用）。
  Future<ConsultationAccessState> _loadLocalAccessState() async {
    await ConsultationTicketPacksService.ensureLoaded();
    var subscribed = await ConsultationSubscriptionService.isActive();
    if (StoreBillingConfig.requirePlayVerifiedAccess) {
      final iap = IAPService.instance;
      await iap.ensureReady();
      final sideloadOk = await SideloadBillingService.isSideloadTestSubscriptionValid();
      subscribed = subscribed && (iap.hasVerifiedPlaySubscription || sideloadOk);
    }
    final normal = await ConsultationTicketService.normalTickets();
    final urgent = await ConsultationTicketService.priorityTickets();
    final state = ConsultationAccessState(
      isSubscribed: subscribed,
      normalTickets: normal,
      urgentTickets: urgent,
    );
    if (mounted) {
      setState(() {
        _isSubscribed = state.isSubscribed;
        _normalTickets = state.normalTickets;
        _urgentTickets = state.urgentTickets;
      });
    }
    return state;
  }

  /// Play 同期後の状態を反映（加入フローは呼び出し元で送信時のみ）。
  Future<ConsultationAccessState> _syncAccessState() async {
    await ConsultationTicketPacksService.ensureLoaded();
    final state = await ConsultationAccessService.loadState();
    if (mounted) {
      setState(() {
        _isSubscribed = state.isSubscribed;
        _normalTickets = state.normalTickets;
        _urgentTickets = state.urgentTickets;
      });
    }
    BillingLog.info(
      'consultationAccess subscribed=${state.isSubscribed} '
      'normal=${state.normalTickets} urgent=${state.urgentTickets}',
    );
    return state;
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
    final visible = _visibleMessages;
    if (_loading && visible.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (visible.isEmpty) {
      return Center(
        child: Text(
          _loading
              ? 'メッセージを読み込み中…'
              : 'この相談スレッドにはまだメッセージがありません。\n右上の更新をお試しください。',
          textAlign: TextAlign.center,
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
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final m = _chatListReversed
            ? visible[visible.length - 1 - index]
            : visible[index];
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
    final sendDisabled = _sendingFirst;
    final canSend = !sendDisabled;

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
              if (!_loading && _isSubscribed) ...[
                Text(
                  'サブスク: 加入中',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.lightGreenAccent,
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
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('consultation_message_input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !sendDisabled,
                      decoration: const InputDecoration(
                        hintText: 'メッセージを入力（送信時に券1枚）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('consultation_send_button'),
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
    final hadSend = await ConsultationSendHistoryService.hasCompletedFirstConsultation();
    if (!mounted) return;
    setState(() {
      _pillarSeeds = seeds;
      if (local.isNotEmpty) {
        _messages = local;
        _preferConsultationThreadUi = true;
      } else if (hadSend) {
        _preferConsultationThreadUi = true;
      }
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
        if (!_preferConsultationThreadUi) {
          _messages = [];
        }
      });
      final preview = await BridgeThreadLocalStore.load(cid);
      if (mounted && preview.isNotEmpty) {
        _clearOptimisticIfMerged(preview);
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
        _clearOptimisticIfMerged(offline);
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
    _clearOptimisticIfMerged(sorted);
    final keepMessagesOnEmptyFetch =
        _preferConsultationThreadUi && sorted.isEmpty && _visibleMessages.isNotEmpty;
    setState(() {
      if (!keepMessagesOnEmptyFetch) {
        _messages = sorted;
      }
      if (sorted.isNotEmpty) _preferConsultationThreadUi = true;
      _loading = false;
      _error = null;
    });
    _log(
      'loadThread chatId=$cid silent=$silent count=${_messages.length} '
      'visible=${_visibleMessages.length} prefer=$_preferConsultationThreadUi show=$_showConsultationChat',
    );
    if (_messages.isNotEmpty &&
        (scrollToLatest || !silent || sorted.length > previousCount)) {
      _scrollToBottom(animated: scrollToLatest || !silent);
    }
  }

  /// 送信完了後に占い相談のメッセージ画面へ戻す（ストア／サブスク画面からの復帰も含む）。
  Future<bool> _isSideloadTestSubscriptionActive() =>
      SideloadBillingService.isSideloadTestSubscriptionValid();

  Future<void> _establishLocalConsultationThread({
    required String chatId,
    required String bodyText,
    required String consultationType,
    required String bridgeUrl,
    int? messageId,
  }) async {
    _chatId = chatId;
    _bridgeBaseUrl = bridgeUrl;
    _setOptimisticUserMessage(text: bodyText, consultationType: consultationType);
    await BridgeThreadLocalStore.appendUserMessage(
      chatId: chatId,
      text: bodyText,
      consultationType: consultationType,
      messageId: messageId,
    );
    await DeveloperChatPref.setActiveChatId(chatId, consultationType: consultationType, pin: true);
    final cached = await BridgeThreadLocalStore.load(chatId);
    _clearOptimisticIfMerged(cached);
    if (mounted) {
      setState(() {
        _preferConsultationThreadUi = true;
        _loading = false;
        if (cached.isNotEmpty) _messages = cached;
      });
      if (_visibleMessages.isNotEmpty) _scrollToBottom(animated: false);
    }
  }

  /// 本番加入・テスト加入共通: 送信完了後に占い相談のメッセージ画面へ遷移する。
  Future<void> _showConsultationMessageScreenAfterSend() async {
    if (!mounted) return;
    if (_chatId == null || _chatId!.isEmpty) {
      _log('showConsultationMessageScreen: no chatId');
      return;
    }

    setState(() {
      _preferConsultationThreadUi = true;
      _loading = false;
      _sendingFirst = false;
      _error = null;
    });

    if (widget.embedInShell) {
      AppNavigation.switchMainTab(AppNavigation.tabConsultation);
    }

    await _focusMessageScreenAfterSend(refreshThread: true);

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showConsultationChat) {
        _scrollToBottom(animated: true);
      }
    });
  }

  Future<void> _completeConsultationSendAndShowMessageScreen({
    required ConsultationSendTicketKind ticketKind,
    bool markFirstSendHistory = true,
    bool startPolling = true,
  }) async {
    final access = await ConsultationAccessService.loadState();
    if (!access.isSubscribed) {
      if (mounted) await _loadAccessState();
      return;
    }
    if (markFirstSendHistory) {
      await ConsultationSendHistoryService.markFirstConsultationCompleted();
    }
    if (ticketKind == ConsultationSendTicketKind.urgent) {
      await ConsultationTicketService.consumeUrgentTicket();
    } else {
      await ConsultationTicketService.consumeNormalTicket();
    }
    await _loadAccessState();
    await DeveloperChatPref.clearConsultationDraft();
    await _showConsultationMessageScreenAfterSend();
    if (startPolling) {
      _startThreadPolling();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('送信しました'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _focusMessageScreenAfterSend({bool refreshThread = true}) async {
    if (!mounted) return;

    final cid = _chatId;
    if (cid == null || cid.isEmpty) {
      _log('focusMessageScreen: no chatId');
      return;
    }

    if (widget.embedInShell && !ConsultationTabVisibility.tabSelected) {
      AppNavigation.switchMainTab(AppNavigation.tabConsultation);
    }

    setState(() {
      _preferConsultationThreadUi = true;
      _loading = false;
      _error = null;
    });

    final local = await BridgeThreadLocalStore.load(cid);
    if (mounted) {
      _clearOptimisticIfMerged(local);
      setState(() {
        if (local.isNotEmpty) _messages = local;
      });
      if (_visibleMessages.isNotEmpty) _scrollToBottom(animated: false);
    }

    if (refreshThread) {
      await _loadThread(silent: true, scrollToLatest: true);
    }

    if (!mounted) return;
    _log(
      'focusMessageScreen done chatId=$cid count=${_messages.length} '
      'visible=${_visibleMessages.length} show=$_showConsultationChat',
    );
    _scrollToBottom(animated: true);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// 質問券不足時にストア（購入画面）へ即時遷移する。
  Future<void> _navigateToStoreForTicketPurchase({
    ConsultationAccessState? accessState,
  }) async {
    if (!mounted) return;

    final access = accessState ?? await _loadLocalAccessState();
    if (!mounted) return;
    if (!access.isSubscribed) {
      await _persistConsultationDraft();
      await _promptSubscriptionRequiredAfterSend();
      return;
    }

    BillingLog.info('navigateToStoreForTicketPurchase embed=${widget.embedInShell}');

    if (widget.embedInShell) {
      AppNavigation.openStoreForTicketsImmediate();
    } else {
      final rootNav = appNavigatorKey.currentState;
      if (rootNav != null) {
        await rootNav.push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const StorePage(
              embedInShell: false,
              forTicketPurchase: true,
            ),
          ),
        );
      } else {
        BillingLog.warn('navigateToStoreForTicketPurchase: no rootNav, try shell notifier');
        AppNavigation.openStoreForTicketsImmediate();
      }
    }

    unawaited((() async {
      await _persistConsultationDraft();
      if (!mounted) return;
      await _restoreConsultationDraft();
      await _loadAccessState();
    })());
  }

  Future<void> _startSubscriptionPurchase() async {
    await StoreSubscriptionFlow.purchase(context);
    await _loadAccessState();
    if (mounted) {
      await _focusMessageScreenAfterSend(refreshThread: _chatId != null && _chatId!.isNotEmpty);
    }
  }

  /// 送信ボタン共通（サブスク + 券で1回送信）。
  Future<void> _onSendPressed() async {
    if (_input.text.trim().isEmpty) return;
    if (_sendingFirst) return;
    if (kDebugMode) E2EDiagnostics.sendPressed++;

    BillingLog.info(
      'consultationSendPressed thread=$_showConsultationChat '
      'normal=$_normalTickets urgent=$_urgentTickets',
    );

    final state = await _loadLocalAccessState();
    if (!mounted) return;
    if (!state.isSubscribed) {
      if (kDebugMode) E2EDiagnostics.subscriptionPrompt++;
      await _promptSubscriptionRequiredAfterSend();
      return;
    }

    ConsultationSendTicketKind? ticketKind;
    if (_showConsultationChat) {
      final mailType = await _followUpConsultationTypeFor(_visibleMessages);
      ticketKind = ConsultationAccessService.resolveFollowUpTicketKind(state, mailType);
    } else {
      ticketKind = ConsultationAccessService.resolveSendTicketKind(state);
    }

    if (ticketKind == null) {
      if (kDebugMode) E2EDiagnostics.insufficientTickets++;
      BillingLog.info('insufficientTickets: no ticketKind -> store');
      await _navigateToStoreForTicketPurchase(accessState: state);
      return;
    }

    if (ticketKind == ConsultationSendTicketKind.normal) {
      final err = await ConsultationTicketService.validateNormalSend();
      if (err != null) {
        BillingLog.info('insufficientTickets: $err -> store');
        await _navigateToStoreForTicketPurchase(accessState: state);
        return;
      }
    } else {
      final err = await ConsultationTicketService.validateUrgentTicketSend();
      if (err != null) {
        BillingLog.info('insufficientTickets: $err -> store');
        await _navigateToStoreForTicketPurchase(accessState: state);
        return;
      }
    }

    final playState = await _syncAccessState();
    if (!mounted) return;
    if (!playState.isSubscribed) {
      await _promptSubscriptionRequiredAfterSend();
      return;
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

  /// 送信ボタン押下後のみ：ダイアログで加入を案内（全画面の加入ページは使わない）。
  Future<void> _promptSubscriptionRequiredAfterSend() async {
    if (!mounted) return;
    BillingLog.info('consultationSubscriptionPrompt afterSend');
    await _persistConsultationDraft();
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('サブスクが必要です'),
        content: const Text(
          '質問を送信するには、月額サブスクへの加入が必要です。\n'
          '初回加入特典で通常質問券が付与されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('あとで'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('加入する'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await _restoreConsultationDraft();
    if (go != true) return;

    await StoreSubscriptionFlow.purchase(context);
    if (!mounted) return;
    await _loadAccessState();
    final accessOk = await StoreSubscriptionFlow.refreshSubscribed();
    if (!mounted) return;
    await _loadAccessState();
    if (!mounted) return;
    if (accessOk && _isSubscribed && _input.text.trim().isNotEmpty) {
      await _onSendPressed();
    }
  }

  Future<void> _sendFirstConsultation({
    required bool urgent,
    required ConsultationSendTicketKind ticketKind,
  }) async {
    if (_input.text.trim().isEmpty) return;
    if (_sendingFirst) return;
    final access = await _syncAccessState();
    if (!access.isSubscribed) return;

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
    final String bridgeForCatch = bridgeUrl;
    final chatId = 'consultation_${userId}_${DateTime.now().millisecondsSinceEpoch}';
    final mailCt = ConsultationMailNewSend.consultationTypeForPref(urgent: urgent);
    final accessState = await ConsultationAccessService.loadState();
    final subscribed = accessState.isSubscribed;
    final sideloadTest = await _isSideloadTestSubscriptionActive();
    _log('sendFirstConsultation subscribed=$subscribed sideloadTest=$sideloadTest chatId=$chatId');

    try {
      final mailService = AuraFaceChatMailService(baseUrl: bridgeUrl);
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
      if (res.success) {
        await _establishLocalConsultationThread(
          chatId: chatId,
          bodyText: bodyText,
          consultationType: mailCt,
          bridgeUrl: bridgeUrl,
          messageId: res.messageId,
        );
        mailSuccess = true;
        unawaited(PushNotificationService.instance.syncTokenNow());
      } else if (subscribed) {
        await _establishLocalConsultationThread(
          chatId: chatId,
          bodyText: bodyText,
          consultationType: mailCt,
          bridgeUrl: bridgeUrl,
        );
        mailSuccess = true;
        _log('sendFirstConsultation: mail failed, subscribed local thread saved');
      }
      if (res.success && res.mailSent == false && mounted && !sideloadTest) {
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
      if (!res.success && mounted && !mailSuccess) {
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
      if (subscribed) {
        await _establishLocalConsultationThread(
          chatId: chatId,
          bodyText: bodyText,
          consultationType: mailCt,
          bridgeUrl: bridgeUrl,
        );
        mailSuccess = true;
        _log('sendFirstConsultation: exception, subscribed local thread saved');
      } else if (mounted) {
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
      await _completeConsultationSendAndShowMessageScreen(ticketKind: ticketKind);
      return;
    }
    _log('sendFirstConsultation: not completed chatId=$_chatId');
  }

  Future<void> _sendFollowUp({required ConsultationSendTicketKind ticketKind}) async {
    final text = _input.text.trim();
    if (text.isEmpty || _chatId == null || _loading) return;
    final access = await _syncAccessState();
    if (!access.isSubscribed) return;

    final fbUser = await ConsultationIdentity.requireFirebaseUserForConsultation(context);
    if (fbUser == null) return;

    setState(() => _loading = true);
    try {
      final mailConsultationType = await _followUpConsultationTypeFor(_visibleMessages);
      _setOptimisticUserMessage(text: text, consultationType: mailConsultationType);
      if (mounted) {
        setState(() => _preferConsultationThreadUi = true);
      }
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
      final subscribed = (await ConsultationAccessService.loadState()).isSubscribed;

      Future<void> persistFollowUpLocally({int? messageId}) async {
        await BridgeThreadLocalStore.appendUserMessage(
          chatId: _chatId!,
          text: text,
          consultationType: mailConsultationType,
          messageId: messageId,
        );
        final cached = await BridgeThreadLocalStore.load(_chatId!);
        _clearOptimisticIfMerged(cached);
        await DeveloperChatPref.setActiveChatId(
          _chatId!,
          consultationType: mailConsultationType,
          pin: true,
        );
        if (mounted) {
          setState(() {
            _preferConsultationThreadUi = true;
            if (cached.isNotEmpty) _messages = cached;
          });
        }
      }

      if (!res.success) {
        if (subscribed && _chatId != null) {
          await persistFollowUpLocally();
          _input.clear();
          if (mounted) setState(() => _loading = false);
          await _completeConsultationSendAndShowMessageScreen(ticketKind: ticketKind);
          return;
        }
        setState(() {
          _loading = false;
          _optimisticUserBubble = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信に失敗しました: ${res.error ?? ""}')),
        );
        return;
      }

      await persistFollowUpLocally(messageId: res.messageId);
      _input.clear();
      if (mounted) setState(() => _loading = false);
      await _completeConsultationSendAndShowMessageScreen(ticketKind: ticketKind);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _optimisticUserBubble = null;
        });
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
            _visibleMessages.isNotEmpty &&
            _threadOpensWithPriority(_visibleMessages))
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
