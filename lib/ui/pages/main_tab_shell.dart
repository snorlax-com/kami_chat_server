import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/ui/pages/home_page.dart';
import 'package:kami_face_oracle/ui/pages/kami_chat_page.dart';
import 'package:kami_face_oracle/ui/pages/store_page.dart';
import 'package:kami_face_oracle/ui/pages/store_locked_page.dart';
import 'package:kami_face_oracle/ui/pages/meditation_page.dart';
import 'package:kami_face_oracle/ui/pages/public_consultations_page.dart';
import 'package:kami_face_oracle/ui/pages/home_account_settings_page.dart';
import 'package:kami_face_oracle/services/developer_chat_unread_service.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/services/developer_reply_notification_watchdog.dart';
import 'package:kami_face_oracle/services/developer_reply_notify_service.dart';
import 'package:kami_face_oracle/services/consultation_tab_visibility.dart';
import 'package:kami_face_oracle/services/notification_permission_prompt.dart';
import 'package:kami_face_oracle/services/consultation_access_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_packs_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_store_return_prefs.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/store_ui_helper.dart';
import 'package:kami_face_oracle/services/store_access_service.dart';
import 'package:kami_face_oracle/services/store_subscription_flow.dart';
import 'package:kami_face_oracle/services/billing_log.dart';
import 'package:kami_face_oracle/services/iap_service.dart';
import 'package:kami_face_oracle/bootstrap/deferred_startup.dart';

const Color _kNavSelected = Color(0xFF8B5CF6);
const Color _kNavUnselected = Color(0xFF9CA3AF);

/// 下部固定で5タブ切替。各タブの状態は [IndexedStack] で保持。
class MainTabShell extends StatefulWidget {
  const MainTabShell({super.key, this.initialIndex = 0});

  /// 起動時に開くタブ（0=ホーム, 1=占い相談, …）
  final int initialIndex;

  @override
  State<MainTabShell> createState() => _MainTabShellState();
}

class _MainTabShellState extends State<MainTabShell> with WidgetsBindingObserver {
  late int _index;
  bool _consultationUnread = false;
  bool _storeAccessAllowed = false;
  bool _openedStoreForTicketPurchase = false;
  Timer? _unreadPollTimer;
  Timer? _devReplyNotifyTimer;
  VoidCallback? _storeAccessListener;
  VoidCallback? _storeForTicketsListener;
  VoidCallback? _consultationReturnListener;
  void Function(int tickets, String productId, {bool isUrgent})? _shellTicketsGrantedHandler;

  static const _titles = [
    'ホーム',
    '占い相談',
    'ストア',
    '瞑想',
    '他の人の相談',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialIndex.clamp(0, _titles.length - 1);
    ConsultationTabVisibility.tabSelected = _index == 1;
    AppNavigation.registerShellOpener(_openConsultationTab);
    AppNavigation.registerMainTabSwitcher(_onBarTap);
    AppNavigation.registerStoreTabOpener(_goToStoreTab);
    AppNavigation.registerStoreForTicketsImmediate(_switchToStoreForTicketPurchaseImmediate);
    AppNavigation.registerConsultationTabImmediate(_switchToConsultationTabImmediate);
    AppNavigation.registerMainTabIndexDirect(_setMainTabIndexDirect);
    _shellTicketsGrantedHandler = _onShellTicketsGranted;
    IAPService.instance.onTicketsGranted = _shellTicketsGrantedHandler;
    ConsultationTabVisibility.appResumed = true;
    _refreshConsultationUnread();
    unawaited(_refreshStoreAccess());
    _storeAccessListener = () => unawaited(_refreshStoreAccess());
    AppNavigation.refreshStoreAccess.addListener(_storeAccessListener!);
    _storeForTicketsListener = _switchToStoreForTicketPurchaseImmediate;
    AppNavigation.requestOpenStoreForTickets.addListener(_storeForTicketsListener!);
    _consultationReturnListener = _onConsultationReturnRequested;
    AppNavigation.requestReturnToConsultationAfterPurchase.addListener(_consultationReturnListener!);
    _unreadPollTimer = Timer.periodic(const Duration(seconds: 45), (_) => _refreshConsultationUnread());
    _devReplyNotifyTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(DeveloperReplyNotifyService.pollAndNotify()),
    );
    unawaited(DeveloperReplyNotifyService.pollAndNotify());
    if (_index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNavigation.scrollConsultationToLatest.value++;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await DeferredStartup.awaitReady(timeout: const Duration(seconds: 10));
      if (!mounted) return;
      // 占い相談タブでは送信操作を遮らない（通知案内はホーム表示時のみ）
      if (_index == 0) {
        await NotificationPermissionPrompt.maybeShow(context);
      }
    });
    if (_index == 3) {
      unawaited(_playMeditationForTab());
    }
    if (_index == AppNavigation.tabStore) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refreshStoreAccess()));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_resumeConsultationTabIfTicketPurchased());
    });
  }

  /// 購入完了後にアプリがバックグラウンドから戻った場合の復帰。
  Future<void> _resumeConsultationTabIfTicketPurchased() async {
    if (!await ConsultationTicketStoreReturnPrefs.isPending()) return;
    final normal = await ConsultationTicketService.normalTickets();
    final urgent = await ConsultationTicketService.priorityTickets();
    if (normal <= 0 && urgent <= 0) return;
    if (!mounted) return;
    BillingLog.info('resumeConsultationTabIfTicketPurchased normal=$normal urgent=$urgent');
    AppNavigation.returnToConsultationAfterStorePurchase();
  }

  void _setMainTabIndexDirect(int index) {
    if (!mounted) return;
    final next = index.clamp(0, _titles.length - 1);
    if (_index == next) {
      if (next == AppNavigation.tabConsultation) {
        unawaited(AppNavigation.restoreConsultationDraftNow());
        AppNavigation.scrollConsultationToLatest.value++;
      }
      return;
    }
    setState(() => _index = next);
    ConsultationTabVisibility.tabSelected = next == AppNavigation.tabConsultation;
    BillingLog.info('setMainTabIndexDirect index=$next');
    if (next == AppNavigation.tabConsultation) {
      unawaited(AppNavigation.restoreConsultationDraftNow());
      AppNavigation.scrollConsultationToLatest.value++;
    }
  }

  void _onConsultationReturnRequested() {
    if (!mounted) return;
    if (_index == AppNavigation.tabConsultation) {
      unawaited(AppNavigation.restoreConsultationDraftNow());
      AppNavigation.scrollConsultationToLatest.value++;
      return;
    }
    _switchToConsultationTabImmediate();
  }

  @override
  void dispose() {
    AppNavigation.unregisterShellOpener();
    AppNavigation.unregisterMainTabSwitcher();
    AppNavigation.unregisterStoreTabOpener();
    AppNavigation.unregisterConsultationTabImmediate();
    final iap = IAPService.instance;
    if (iap.onTicketsGranted == _shellTicketsGrantedHandler) {
      iap.onTicketsGranted = null;
    }
    if (_storeAccessListener != null) {
      AppNavigation.refreshStoreAccess.removeListener(_storeAccessListener!);
    }
    if (_storeForTicketsListener != null) {
      AppNavigation.requestOpenStoreForTickets.removeListener(_storeForTicketsListener!);
    }
    if (_consultationReturnListener != null) {
      AppNavigation.requestReturnToConsultationAfterPurchase.removeListener(_consultationReturnListener!);
    }
    WidgetsBinding.instance.removeObserver(this);
    _unreadPollTimer?.cancel();
    _devReplyNotifyTimer?.cancel();
    super.dispose();
  }

  void _openConsultationTab({String? chatId}) {
    if (chatId != null && chatId.trim().isNotEmpty) {
      unawaited(DeveloperChatPref.setActiveChatId(chatId.trim()));
    }
    _onBarTap(1);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ConsultationTabVisibility.appResumed = state == AppLifecycleState.resumed;
    DeveloperReplyNotificationWatchdog.instance.onLifecycleChange(state);
    if (state == AppLifecycleState.resumed) {
      _refreshConsultationUnread();
      unawaited(_refreshStoreAccess());
      unawaited(DeveloperReplyNotifyService.pollAndNotify());
      unawaited(_resumeConsultationTabIfTicketPurchased());
    }
  }

  Future<bool> _refreshStoreAccess() async {
    final access = await ConsultationAccessService.loadState();
    final allowed = access.isSubscribed;
    final keepStoreDuringTicketFlow =
        AppNavigation.pendingReturnToConsultationAfterTicketStore ||
        AppNavigation.storeOpenedForTicketPurchase.value ||
        await ConsultationTicketStoreReturnPrefs.isPending();
    if (!mounted) return false;
    setState(() => _storeAccessAllowed = allowed || keepStoreDuringTicketFlow);
    return allowed || keepStoreDuringTicketFlow;
  }

  /// Play 課金完了時（StorePage の mount に依存しない）。
  void _onShellTicketsGranted(int tickets, String productId, {bool isUrgent = false}) {
    BillingLog.info(
      'shellTicketsGranted tickets=$tickets product=$productId '
      'pending=${AppNavigation.pendingReturnToConsultationAfterTicketStore} '
      'storeFlag=${AppNavigation.storeOpenedForTicketPurchase.value} index=$_index',
    );
    AppNavigation.refreshStoreTab.value++;
    if (tickets <= 0) return;
    if (mounted && _index == AppNavigation.tabStore) {
      final label = ConsultationTicketPacksService.getPackById(productId)?.name ?? '相談券';
      final kind = isUrgent ? '至急券' : '通常券';
      StoreUiHelper.showSnack('$label を購入しました（+$tickets $kind）', backgroundColor: Colors.green);
    }
    unawaited(AppNavigation.completeTicketPackPurchaseFromStore());
  }

  /// 占い相談などからストアタブへ。
  Future<void> _goToStoreTab({bool forTicketPurchase = false}) async {
    if (forTicketPurchase) {
      await _goToStoreTabForTicketPurchase();
      return;
    }
    final allowed = await _refreshStoreAccess();
    if (!mounted) return;
    if (!allowed) {
      await _promptSubscribeBeforeStore();
      return;
    }
    _switchToStoreTabIndex();
  }

  /// 券不足時：UI を即時切り替え（Play 同期なし）。
  void _switchToStoreForTicketPurchaseImmediate() {
    if (!mounted) return;
    if (_index == AppNavigation.tabConsultation) {
      AppNavigation.saveConsultationDraftNow();
    }
    setState(() {
      _openedStoreForTicketPurchase = true;
      _storeAccessAllowed = true;
      _index = AppNavigation.tabStore;
    });
    ConsultationTabVisibility.tabSelected = false;
    AppNavigation.refreshStoreTab.value++;
    BillingLog.info('switchToStoreForTicketPurchaseImmediate index=${AppNavigation.tabStore}');
  }

  /// ストア購入後：占い相談タブへ即時切り替え。
  void _switchToConsultationTabImmediate() {
    if (!mounted) return;
    _openedStoreForTicketPurchase = false;
    BillingLog.info('switchToConsultationTabImmediate from=$_index');
    _setMainTabIndexDirect(AppNavigation.tabConsultation);
  }

  /// 券購入誘導（非同期・加入未加入時はダイアログ）。
  Future<void> _goToStoreTabForTicketPurchase() async {
    _switchToStoreForTicketPurchaseImmediate();
    final subscribed = await ConsultationSubscriptionService.isActive();
    if (!mounted) return;
    if (!subscribed) {
      await _promptSubscribeBeforeStore();
      return;
    }
  }

  void _switchToStoreTabIndex() {
    if (_index == AppNavigation.tabConsultation) {
      AppNavigation.saveConsultationDraftNow();
    }
    if (!mounted) return;
    setState(() {
      _index = AppNavigation.tabStore;
      _storeAccessAllowed = true;
    });
    ConsultationTabVisibility.tabSelected = false;
    AppNavigation.refreshStoreTab.value++;
    BillingLog.info('switchToStoreTabIndex index=$_index storeAllowed=$_storeAccessAllowed');
  }

  Future<void> _refreshConsultationUnread() async {
    final u = await DeveloperChatUnreadService.hasUnreadReply();
    if (!mounted) return;
    if (_consultationUnread != u) {
      setState(() => _consultationUnread = u);
      if (u && _index != 1) {
        unawaited(DeveloperReplyNotificationWatchdog.instance.checkNow());
      }
    }
  }

  /// 瞑想トラックは下部ナビの「瞑想」アイコンのみで再生（他タブで通常BGMに戻す）
  Future<void> _onBarTap(int i) async {
    if (i == AppNavigation.tabStore) {
      await _goToStoreTab();
      return;
    }

    final wasMeditation = _index == 3;
    final previousIndex = _index;
    final tabChanged = _index != i;
    if (_index == 1 && i != 1) {
      AppNavigation.saveConsultationDraftNow();
    }
    setState(() => _index = i);
    ConsultationTabVisibility.tabSelected = i == 1;
    if (i == AppNavigation.tabConsultation) {
      if (previousIndex == AppNavigation.tabStore &&
          !AppNavigation.suppressCancelPendingWhenOpeningConsultation) {
        _openedStoreForTicketPurchase = false;
        AppNavigation.cancelPendingReturnToConsultationAfterTicketStore();
      } else {
        AppNavigation.clearStoreOpenedForTicketPurchase();
      }
      if (tabChanged) {
        unawaited(AppNavigation.restoreConsultationDraftNow());
        AppNavigation.scrollConsultationToLatest.value++;
      }
      unawaited(_refreshConsultationUnread());
    }
    if (i == 3) {
      unawaited(_playMeditationForTab());
    } else if (wasMeditation) {
      unawaited(BackgroundMusicService().stopMeditationMusic());
    }
  }

  Future<void> _promptSubscribeBeforeStore() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('サブスク加入が必要です'),
        content: const Text(
          'ストアはサブスクご加入中のみご利用いただけます。\n'
          '解約済みの方は、占い相談タブから再度サブスクへご加入ください。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('閉じる')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('サブスクに加入'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await StoreSubscriptionFlow.purchase(context);
    if (!mounted) return;
    if (await StoreAccessService.canOpenStore()) {
      await _goToStoreTab();
    }
  }

  Future<void> _playMeditationForTab() async {
    final id = await Storage.getTutorialDeity();
    final pillar = (id != null && id.isNotEmpty) ? id : 'tenmira';
    await BackgroundMusicService().playMeditationMusic(pillar);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          _titles[_index],
          key: ValueKey<String>('main_tab_title_${_titles[_index]}'),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                const Color(0xFF06B6D4).withValues(alpha: 0.2),
                const Color(0xFF0A0E1A),
              ],
            ),
          ),
        ),
        actions: _index == 0
            ? [
                Semantics(
                  label: '利用規約とプライバシー、同意設定を開く',
                  child: IconButton(
                    icon: const Icon(Icons.description_outlined),
                    tooltip: 'Legal & Privacy',
                    onPressed: () => showHomeLegalMenu(context),
                  ),
                ),
                Semantics(
                  label: '設定（ログイン・ログアウト）を開く',
                  child: IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: '設定',
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const HomeAccountSettingsPage(),
                        ),
                      );
                      if (mounted) await _refreshStoreAccess();
                    },
                  ),
                ),
              ]
            : null,
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const HomePage(embedInShell: true),
          const KamiChatPage(),
          _storeAccessAllowed
              ? StorePage(
                  embedInShell: true,
                  forTicketPurchase: _openedStoreForTicketPurchase,
                )
              : const StoreLockedPage(embedInShell: true),
          const MeditationPage(embedInShell: true),
          const PublicConsultationsPage(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Material(
          color: const Color(0xFF0A0E1A),
          elevation: 8,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0x22FFFFFF), width: 0.5),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _index,
              onTap: _onBarTap,
              type: BottomNavigationBarType.fixed,
              backgroundColor: const Color(0xFF0A0E1A),
              selectedItemColor: _kNavSelected,
              unselectedItemColor: _kNavUnselected,
              showSelectedLabels: false,
              showUnselectedLabels: false,
              selectedFontSize: 0,
              unselectedFontSize: 0,
              iconSize: 26,
              elevation: 0,
              items: [
                for (var i = 0; i < 5; i++)
                  BottomNavigationBarItem(
                    icon: Semantics(
                      label: _titles[i],
                      button: true,
                      child: _navIcon(i, i == _index),
                    ),
                    label: '',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navIcon(int i, bool selected) {
    final lockedStore = i == AppNavigation.tabStore && !_storeAccessAllowed;
    final icon = Icon(
      lockedStore ? Icons.lock_outline : _iconFor(i, selected),
      color: lockedStore ? _kNavUnselected.withValues(alpha: 0.5) : null,
    );
    if (i != 1 || !_consultationUnread) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF0A0E1A), width: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconFor(int i, bool selected) {
    switch (i) {
      case 0:
        return selected ? Icons.home : Icons.home_outlined;
      case 1:
        return selected ? Icons.support_agent : Icons.support_agent_outlined;
      case 2:
        return selected ? Icons.shopping_bag : Icons.shopping_bag_outlined;
      case 3:
        return Icons.self_improvement;
      case 4:
        return selected ? Icons.groups : Icons.groups_outlined;
      default:
        return Icons.circle;
    }
  }
}
