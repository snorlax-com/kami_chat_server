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
import 'package:kami_face_oracle/services/store_access_service.dart';
import 'package:kami_face_oracle/services/store_subscription_flow.dart';
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
  Timer? _unreadPollTimer;
  Timer? _devReplyNotifyTimer;

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
    ConsultationTabVisibility.appResumed = true;
    _refreshConsultationUnread();
    unawaited(_refreshStoreAccess());
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
      await NotificationPermissionPrompt.maybeShow(context);
    });
    if (_index == 3) {
      unawaited(_playMeditationForTab());
    }
    if (_index == AppNavigation.tabStore) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refreshStoreAccess()));
    }
  }

  @override
  void dispose() {
    AppNavigation.unregisterShellOpener();
    AppNavigation.unregisterMainTabSwitcher();
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
    }
  }

  Future<void> _refreshStoreAccess() async {
    final allowed = await StoreAccessService.canOpenStore();
    if (!mounted) return;
    if (!allowed && _index == AppNavigation.tabStore) {
      setState(() => _index = 0);
    }
    if (_storeAccessAllowed != allowed) {
      setState(() => _storeAccessAllowed = allowed);
    }
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
      await _refreshStoreAccess();
      if (!_storeAccessAllowed) {
        if (!mounted) return;
        await _promptSubscribeBeforeStore();
        return;
      }
    }

    final wasMeditation = _index == 3;
    if (_index == 1 && i != 1) {
      AppNavigation.saveConsultationDraftNow();
    }
    setState(() => _index = i);
    ConsultationTabVisibility.tabSelected = i == 1;
    if (i == 1) {
      unawaited(AppNavigation.restoreConsultationDraftNow());
      AppNavigation.scrollConsultationToLatest.value++;
      unawaited(_refreshConsultationUnread());
    }
    if (i == AppNavigation.tabStore) {
      AppNavigation.refreshStoreTab.value++;
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
          'ストアは定期購入サブスク加入後にご利用いただけます。\n'
          '占い相談タブから月額サブスクに加入してください。',
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
      await _refreshStoreAccess();
      if (!mounted) return;
      setState(() => _index = AppNavigation.tabStore);
      AppNavigation.refreshStoreTab.value++;
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
        title: Text(_titles[_index]),
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
              ? const StorePage(embedInShell: true)
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
