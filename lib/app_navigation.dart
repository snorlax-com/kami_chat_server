import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/services/billing_log.dart';
import 'package:kami_face_oracle/services/consultation_ticket_store_return_prefs.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/services/tutorial_diagnosis_local_store.dart';
import 'package:kami_face_oracle/ui/pages/main_tab_shell.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_intro_page.dart';

/// プッシュ通知タップ等から占い相談タブへ遷移するためのグローバル Navigator。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// [MainTabShell] がマウントされたときに占い相談タブへ切り替える。
class AppNavigation {
  AppNavigation._();

  static void Function({String? chatId})? _openConsultationInShell;
  static void Function(int tabIndex)? _switchMainTab;
  static Future<void> Function({bool forTicketPurchase})? _openStoreInShell;
  static void Function()? _openStoreForTicketsImmediate;
  static void Function()? _switchToConsultationImmediate;
  static void Function(int tabIndex)? _setMainTabIndexDirect;
  static void Function()? _saveConsultationDraft;

  /// 自動復帰中に [_onBarTap] が pending をキャンセルしないよう抑止する。
  static bool suppressCancelPendingWhenOpeningConsultation = false;
  static Future<void> Function()? _restoreConsultationDraft;
  static String? _pendingChatId;

  /// 通知タップ等で占い相談チャットを開く必要があるか。
  static bool get hasPendingConsultationChat =>
      _pendingChatId != null && _pendingChatId!.trim().isNotEmpty;

  /// [MainTabShell] タブ index（0=ホーム, 1=占い相談, 2=ストア, 3=瞑想, 4=他の人の相談）
  static const int tabStore = 2;
  static const int tabMeditation = 3;

  /// 通知タップ等で占い相談画面の再読み込みを促す。
  static final ValueNotifier<int> refreshConsultationChat = ValueNotifier(0);

  /// 占い相談タブ表示時にチャットを最新へスクロールする。
  static final ValueNotifier<int> scrollConsultationToLatest = ValueNotifier(0);

  /// 占い相談タブ index（[MainTabShell] と一致）
  static const int tabConsultation = 1;

  /// ストアタブ表示時に残高・商品を再読み込みする。
  static final ValueNotifier<int> refreshStoreTab = ValueNotifier(0);

  /// 券不足時に [MainTabShell] が即ストアタブへ切り替える（コールバック未登録時のフォールバック兼用）。
  static final ValueNotifier<int> requestOpenStoreForTickets = ValueNotifier(0);

  /// 券購入後に [MainTabShell] が占い相談タブへ切り替える（postFrame 不発時のフォールバック兼用）。
  static final ValueNotifier<int> requestReturnToConsultationAfterPurchase = ValueNotifier(0);

  /// 占い相談の券不足からストアを開いた（UI 用・タブ切替でリセット可）。
  static final ValueNotifier<bool> storeOpenedForTicketPurchase = ValueNotifier(false);

  /// 券購入完了まで維持（占い相談タブへ戻るまでクリアしない）。
  static bool pendingReturnToConsultationAfterTicketStore = false;

  /// サブスク加入・解除後に [MainTabShell] のストアアクセス状態を更新する。
  static final ValueNotifier<int> refreshStoreAccess = ValueNotifier(0);

  static void notifyStoreAccessChanged() {
    refreshStoreAccess.value++;
    refreshStoreTab.value++;
  }

  static void stagePendingConsultationChat(String? chatId) {
    if (chatId == null || chatId.trim().isEmpty) return;
    _pendingChatId = chatId.trim();
  }

  static void registerShellOpener(void Function({String? chatId}) opener) {
    _openConsultationInShell = opener;
    if (_pendingChatId != null) {
      final cid = _pendingChatId;
      _pendingChatId = null;
      // initState 完了後に実行（_index 未初期化の LateInitializationError 防止）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        opener(chatId: cid);
        refreshConsultationChat.value++;
        scrollConsultationToLatest.value++;
      });
    }
  }

  static void unregisterShellOpener() {
    _openConsultationInShell = null;
  }

  static void registerMainTabSwitcher(void Function(int tabIndex) switcher) {
    _switchMainTab = switcher;
  }

  static void unregisterMainTabSwitcher() {
    _switchMainTab = null;
  }

  static void registerStoreTabOpener(
    Future<void> Function({bool forTicketPurchase}) opener,
  ) {
    _openStoreInShell = opener;
  }

  static void unregisterStoreTabOpener() {
    _openStoreInShell = null;
    _openStoreForTicketsImmediate = null;
  }

  static void unregisterConsultationTabImmediate() {
    _switchToConsultationImmediate = null;
    _setMainTabIndexDirect = null;
  }

  static void registerMainTabIndexDirect(void Function(int tabIndex) setter) {
    _setMainTabIndexDirect = setter;
  }

  /// 券不足時：Play 同期を待たずストアタブへ切り替え（同期・即時）。
  static void registerStoreForTicketsImmediate(void Function() opener) {
    _openStoreForTicketsImmediate = opener;
  }

  static void registerConsultationTabImmediate(void Function() opener) {
    _switchToConsultationImmediate = opener;
  }

  /// integration_test 用: 券不足ストア遷移が呼ばれた回数。
  static int storeForTicketsNavigateCount = 0;

  static void openStoreForTicketsImmediate() {
    storeForTicketsNavigateCount++;
    markStoreOpenedForTicketPurchase();
    final hadCallback = _openStoreForTicketsImmediate != null;
    void navigate() {
      if (hadCallback) {
        _openStoreForTicketsImmediate?.call();
      } else {
        requestOpenStoreForTickets.value++;
      }
      refreshStoreTab.value++;
    }

    unawaited(() async {
      await ConsultationTicketStoreReturnPrefs.setPending(true);
      if (hadCallback) {
        navigate();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
      }
      BillingLog.info(
        'openStoreForTicketsImmediate callback=$hadCallback '
        'notifier=${requestOpenStoreForTickets.value}',
      );
    }());
  }

  /// 下部ナビのタブを切り替える（[MainTabShell] 表示中のみ有効）。
  static void switchMainTab(int tabIndex) {
    _switchMainTab?.call(tabIndex);
  }

  static void markStoreOpenedForTicketPurchase() {
    storeOpenedForTicketPurchase.value = true;
    pendingReturnToConsultationAfterTicketStore = true;
    unawaited(ConsultationTicketStoreReturnPrefs.setPending(true));
    BillingLog.info('markStoreOpenedForTicketPurchase pending=true persisted=true');
  }

  static void clearStoreOpenedForTicketPurchase() {
    if (!storeOpenedForTicketPurchase.value) return;
    storeOpenedForTicketPurchase.value = false;
    BillingLog.info('clearStoreOpenedForTicketPurchase');
  }

  static Future<void> _clearAllReturnPendingFlags() async {
    pendingReturnToConsultationAfterTicketStore = false;
    storeOpenedForTicketPurchase.value = false;
    await ConsultationTicketStoreReturnPrefs.clear();
  }

  /// ストアから手動で占い相談へ戻ったとき（購入後の自動復帰をキャンセル）。
  static void cancelPendingReturnToConsultationAfterTicketStore() {
    if (!pendingReturnToConsultationAfterTicketStore &&
        !storeOpenedForTicketPurchase.value) {
      return;
    }
    unawaited(_clearAllReturnPendingFlags());
    BillingLog.info('cancelPendingReturnToConsultationAfterTicketStore');
  }

  static bool get shouldReturnToConsultationAfterTicketStorePurchase =>
      pendingReturnToConsultationAfterTicketStore || storeOpenedForTicketPurchase.value;

  static Future<bool> shouldReturnToConsultationAfterTicketStorePurchaseAsync() async {
    if (shouldReturnToConsultationAfterTicketStorePurchase) return true;
    return ConsultationTicketStoreReturnPrefs.isPending();
  }

  /// 券パック購入完了時（テスト購入・Play 共通）に占い相談へ戻す。
  static Future<void> completeTicketPackPurchaseFromStore() async {
    var shouldReturn = shouldReturnToConsultationAfterTicketStorePurchase;
    if (!shouldReturn) {
      shouldReturn = await ConsultationTicketStoreReturnPrefs.isPending();
    }
    if (!shouldReturn) {
      BillingLog.info('completeTicketPackPurchaseFromStore: skip (not from consultation)');
      return;
    }
    if (!pendingReturnToConsultationAfterTicketStore) {
      pendingReturnToConsultationAfterTicketStore = true;
      storeOpenedForTicketPurchase.value = true;
    }
    _returnToConsultationAfterStorePurchaseImpl();
  }

  static int _returnToConsultationAttempt = 0;

  /// ストアで券購入後、占い相談タブへ戻す（下書き復元・スクロール込み）。
  static void returnToConsultationAfterStorePurchase() {
    if (pendingReturnToConsultationAfterTicketStore ||
        storeOpenedForTicketPurchase.value) {
      _returnToConsultationAfterStorePurchaseImpl();
      return;
    }
    unawaited(() async {
      if (await ConsultationTicketStoreReturnPrefs.isPending()) {
        pendingReturnToConsultationAfterTicketStore = true;
        storeOpenedForTicketPurchase.value = true;
      }
      _returnToConsultationAfterStorePurchaseImpl();
    }());
  }

  static void _returnToConsultationAfterStorePurchaseImpl() {
    if (!pendingReturnToConsultationAfterTicketStore &&
        !storeOpenedForTicketPurchase.value) {
      BillingLog.warn('returnToConsultationAfterStorePurchase: no pending');
      return;
    }
    if (!pendingReturnToConsultationAfterTicketStore) {
      pendingReturnToConsultationAfterTicketStore = true;
    }
    BillingLog.info('returnToConsultationAfterStorePurchase');
    _returnToConsultationAttempt = 0;
    _tryReturnToConsultationAfterStorePurchase();
  }

  static void _tryReturnToConsultationAfterStorePurchase() {
    if (!pendingReturnToConsultationAfterTicketStore &&
        !storeOpenedForTicketPurchase.value) {
      return;
    }

    final direct = _setMainTabIndexDirect;
    final immediate = _switchToConsultationImmediate;
    final hasSwitcher = _switchMainTab != null;
    BillingLog.info(
      'returnToConsultation attempt=$_returnToConsultationAttempt '
      'direct=${direct != null} immediate=${immediate != null} switcher=$hasSwitcher',
    );

    suppressCancelPendingWhenOpeningConsultation = true;
    var navigated = false;
    try {
      if (immediate != null) {
        immediate();
        navigated = true;
      } else if (direct != null) {
        direct(tabConsultation);
        navigated = true;
      } else if (hasSwitcher) {
        _switchMainTab!(tabConsultation);
        navigated = true;
      } else if (_returnToConsultationAttempt < 40) {
        _returnToConsultationAttempt++;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tryReturnToConsultationAfterStorePurchase();
        });
        return;
      } else {
        BillingLog.warn('returnToConsultationAfterStorePurchase: no handlers after retries');
        requestReturnToConsultationAfterPurchase.value++;
        return;
      }
    } finally {
      suppressCancelPendingWhenOpeningConsultation = false;
    }

    if (!navigated) return;

    requestReturnToConsultationAfterPurchase.value++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_clearAllReturnPendingFlags());
      unawaited(restoreConsultationDraftNow());
      scrollConsultationToLatest.value++;
    });
  }

  /// ストアタブへ。[forTicketPurchase] は占い相談の券不足時（加入済みならロックを回避）。
  static Future<bool> openStoreTab({bool forTicketPurchase = false}) async {
    if (forTicketPurchase) {
      openStoreForTicketsImmediate();
      if (_openStoreInShell != null || _switchMainTab != null) {
        return true;
      }
      BillingLog.warn('openStoreTab: forTicketPurchase waiting for shell notifier');
      return true;
    }
    final opener = _openStoreInShell;
    if (opener != null) {
      await opener(forTicketPurchase: forTicketPurchase);
      refreshStoreTab.value++;
      return true;
    }
    final switcher = _switchMainTab;
    if (switcher != null) {
      BillingLog.info('openStoreTab: fallback switchMainTab');
      switcher(tabStore);
      refreshStoreTab.value++;
      return true;
    }
    BillingLog.warn('openStoreTab: no shell');
    return false;
  }

  static void registerConsultationDraftHandlers({
    required void Function() save,
    required Future<void> Function() restore,
  }) {
    _saveConsultationDraft = save;
    _restoreConsultationDraft = restore;
  }

  static void unregisterConsultationDraftHandlers() {
    _saveConsultationDraft = null;
    _restoreConsultationDraft = null;
  }

  static void saveConsultationDraftNow() {
    _saveConsultationDraft?.call();
  }

  static Future<void> restoreConsultationDraftNow() async {
    await _restoreConsultationDraft?.call();
  }

  /// 通知タップ時: 占い相談（統合チャット）へ遷移。Navigator 準備までリトライ。
  static Future<void> openConsultationChat({String? chatId}) async {
    final cid = (chatId?.trim().isNotEmpty == true ? chatId!.trim() : null) ?? _pendingChatId;
    if (cid != null && cid.isNotEmpty) {
      _pendingChatId = cid;
      await DeveloperChatPref.setActiveChatId(cid, pin: true);
    }

    for (var attempt = 0; attempt < 50; attempt++) {
      final opener = _openConsultationInShell;
      if (opener != null) {
        opener(chatId: cid);
        refreshConsultationChat.value++;
        scrollConsultationToLatest.value++;
        _pendingChatId = null;
        debugPrint('[AppNavigation] openConsultationChat via shell chatId=$cid');
        return;
      }

      final nav = appNavigatorKey.currentState;
      if (nav != null) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => const MainTabShell(initialIndex: 1),
          ),
          (route) => false,
        );
        debugPrint('[AppNavigation] openConsultationChat push MainTabShell attempt=$attempt');
        await Future<void>.delayed(const Duration(milliseconds: 80));
        continue;
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    debugPrint('[AppNavigation] openConsultationChat gave up chatId=$cid');
  }

  /// サブスク加入直後など、グローバル Navigator から性格診断チュートリアルを開く。
  static void launchTutorialPersonalityDiagnosis({String? message}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(pushTutorialPersonalityDiagnosisWhenReady(message: message));
    });
  }

  /// Navigator の準備を待ってチュートリアルを push する。成功時 true。
  /// [force] が false のとき、チュートリアル診断を既に消費済みなら起動しない。
  static Future<bool> pushTutorialPersonalityDiagnosisWhenReady({
    String? message,
    bool force = false,
  }) async {
    if (!force) {
      final skip = await TutorialDiagnosisLocalStore.shouldSkipAutoTutorialLaunch();
      if (skip) {
        debugPrint('[AppNavigation] skip tutorial: diagnosis chance already used');
        return false;
      }
    }
    for (var attempt = 0; attempt < 120; attempt++) {
      final nav = appNavigatorKey.currentState;
      if (nav != null && nav.mounted) {
        final ctx = nav.context;
        if (message != null && message.isNotEmpty && ctx.mounted) {
          ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
        await nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const TutorialIntroPage(key: Key('e2e-tutorial')),
          ),
        );
        debugPrint('[AppNavigation] launchTutorialPersonalityDiagnosis ok attempt=$attempt');
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    debugPrint('[AppNavigation] launchTutorialPersonalityDiagnosis: navigator not ready');
    return false;
  }
}
