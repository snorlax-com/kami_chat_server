import 'package:flutter/material.dart';
import 'package:kami_face_oracle/services/consultation_access_service.dart';
import 'package:kami_face_oracle/services/consultation_send_history_service.dart';

/// ストアタブ・ストア画面へのアクセス可否（定期購入サブスク加入が条件）。
class StoreAccessService {
  StoreAccessService._();

  /// @deprecated 互換用。[canOpenStore] と同じ（解約後は false）。
  static Future<bool> canOpenStoreRelaxed() => canOpenStore();

  /// Play 同期後、有効な定期購入サブスクがあるときのみ true（解約済みは false）。
  static Future<bool> canOpenStore() async {
    final state = await ConsultationAccessService.loadState();
    return state.isSubscribed;
  }

  /// 通常券・至急券の購入可否（サブスク加入済みかつ初回相談送信済み = 2回目以降）。
  static Future<bool> canPurchaseConsultationTickets() async {
    if (!await canOpenStore()) return false;
    await ConsultationSendHistoryService.migrateIfNeeded();
    return ConsultationSendHistoryService.hasCompletedFirstConsultation();
  }

  /// [Navigator.push] 前など、ストアを開く直前に呼ぶ。
  static Future<bool> guardStoreRoute(BuildContext context) async {
    if (await canOpenStore()) return true;
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'ストアはサブスクご加入中のみご利用いただけます。'
          '解約済みの方は、占い相談から再度ご加入ください。',
        ),
      ),
    );
    return false;
  }

  /// 券購入前に呼ぶ。
  static Future<bool> guardTicketPurchase(BuildContext context) async {
    if (await canPurchaseConsultationTickets()) return true;
    if (!context.mounted) return false;
    final subscribed = await canOpenStore();
    final message = subscribed
        ? '初回相談はサブスク特典の通常券をご利用ください。2回目以降、ストアで券を購入できます。'
        : 'ストアで券を購入するには、先に定期購入サブスクへ加入してください。';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    return false;
  }
}
