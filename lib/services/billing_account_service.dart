import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:kami_face_oracle/app_navigation.dart';
import 'package:kami_face_oracle/services/billing_account_status.dart';
import 'package:kami_face_oracle/services/billing_log.dart';
import 'package:kami_face_oracle/services/billing_server_sync_service.dart';
import 'package:kami_face_oracle/services/consultation_subscription_service.dart';
import 'package:kami_face_oracle/services/consultation_ticket_service.dart';
import 'package:kami_face_oracle/services/iap_service.dart';

/// Firebase アカウントごとに券・サブスク状態を分離し、サーバーと同期する。
class BillingAccountService {
  BillingAccountService._();

  static String? _boundAccountKey;
  static StreamSubscription<User?>? _authSub;

  static String? get boundAccountKey => _boundAccountKey;

  static Future<void> init() async {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(bindUser(user));
    });
    await bindUser(FirebaseAuth.instance.currentUser);
  }

  static String accountKeyForUser(User? user) {
    if (user == null || user.isAnonymous) return 'guest';
    return user.uid;
  }

  static bool get canUseServerBilling {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && !user.isAnonymous;
  }

  static Future<void> bindUser(User? user) async {
    final nextKey = accountKeyForUser(user);
    if (_boundAccountKey == nextKey) return;
    BillingLog.info('billing account switch: $_boundAccountKey -> $nextKey');
    _boundAccountKey = nextKey;
    await ConsultationTicketService.bindAccountKey(nextKey);
    await ConsultationSubscriptionService.bindAccountKey(nextKey);

    if (!canUseServerBilling) {
      await ConsultationTicketService.setBalances(normal: 0, priority: 0);
      await ConsultationSubscriptionService.setActive(false);
      AppNavigation.notifyStoreAccessChanged();
      return;
    }

    await syncFromServer();
    await IAPService.instance.syncSubscriptionStatusFromPlay();
    await syncFromServer();
  }

  static Future<bool> syncFromServer() async {
    if (!canUseServerBilling) return false;
    final status = await BillingServerSyncService.fetchStatus();
    if (status == null) return false;
    await applyStatus(status);
    return true;
  }

  static Future<void> applyStatus(BillingAccountStatus status) async {
    await ConsultationTicketService.setBalances(
      normal: status.normal,
      priority: status.urgent,
    );
    await ConsultationSubscriptionService.setActive(status.subscribed);
    AppNavigation.notifyStoreAccessChanged();
    BillingLog.info(
      'billing status applied normal=${status.normal} urgent=${status.urgent} subscribed=${status.subscribed}',
    );
  }

  /// 相談送信時: ログイン中はサーバーで消費してからローカルへ反映。
  static Future<String?> consumeNormalForSend() async {
    if (!canUseServerBilling) {
      final err = await ConsultationTicketService.validateNormalSend();
      if (err != null) return err;
      await ConsultationTicketService.consumeNormalTicket();
      return null;
    }
    final status = await BillingServerSyncService.consumeTickets(
      type: 'normal',
      amount: 1,
    );
    if (status == null) {
      return '券の消費に失敗しました。通信環境を確認してください。';
    }
    await applyStatus(status);
    return null;
  }

  static Future<String?> consumeUrgentForSend() async {
    if (!canUseServerBilling) {
      final err = await ConsultationTicketService.validateUrgentTicketSend();
      if (err != null) return err;
      await ConsultationTicketService.consumeUrgentTicket();
      return null;
    }
    final status = await BillingServerSyncService.consumeTickets(
      type: 'urgent',
      amount: 1,
    );
    if (status == null) {
      return '券の消費に失敗しました。通信環境を確認してください。';
    }
    await applyStatus(status);
    return null;
  }

  static Future<void> dispose() async {
    await _authSub?.cancel();
    _authSub = null;
  }
}
