import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/services/developer_chat_pref.dart';
import 'package:kami_face_oracle/ui/pages/main_tab_shell.dart';

/// プッシュ通知タップ等から占い相談タブへ遷移するためのグローバル Navigator。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// [MainTabShell] がマウントされたときに占い相談タブへ切り替える。
class AppNavigation {
  AppNavigation._();

  static void Function({String? chatId})? _openConsultationInShell;
  static void Function(int tabIndex)? _switchMainTab;
  static void Function()? _saveConsultationDraft;
  static Future<void> Function()? _restoreConsultationDraft;
  static String? _pendingChatId;

  /// [MainTabShell] タブ index（0=ホーム, 1=占い相談, 2=ストア, 3=瞑想, 4=他の人の相談）
  static const int tabStore = 2;
  static const int tabMeditation = 3;

  /// 通知タップ等で占い相談画面の再読み込みを促す。
  static final ValueNotifier<int> refreshConsultationChat = ValueNotifier(0);

  /// 占い相談タブ表示時にチャットを最新へスクロールする。
  static final ValueNotifier<int> scrollConsultationToLatest = ValueNotifier(0);

  /// ストアタブ表示時に残高・商品を再読み込みする。
  static final ValueNotifier<int> refreshStoreTab = ValueNotifier(0);

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

  /// 下部ナビのタブを切り替える（[MainTabShell] 表示中のみ有効）。
  static void switchMainTab(int tabIndex) {
    _switchMainTab?.call(tabIndex);
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
}
