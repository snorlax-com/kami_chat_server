/// Google Play 課金商品 ID の単一ソース（Play Console と完全一致させる）。
///
/// Play Console に旧 ID で登録済みの場合は [legacy*] もクエリに含め、
/// 購入イベントは [resolveCanonicalProductId] で正規 ID に統一する。
class PlayBillingProducts {
  PlayBillingProducts._();

  // --- 正規商品 ID（本番・内部テストで登録する ID） ---
  static const String subscriptionMonthly500 = 'subscription_monthly_500';
  static const String ticketNormal600 = 'ticket_normal_600';
  static const String ticketUrgent10000 = 'ticket_urgent_10000';

  /// 旧リリースで Play Console に登録していた ID（移行期間用）。
  static const String legacySubscriptionMonthly500 = 'monthly_subscription_500';
  static const String legacyTicketNormal600 = 'normal_ticket_600';
  static const String legacyTicketUrgent10000 = 'urgent_ticket_10000';

  static const Set<String> allQueryProductIds = {
    subscriptionMonthly500,
    ticketNormal600,
    ticketUrgent10000,
    legacySubscriptionMonthly500,
    legacyTicketNormal600,
    legacyTicketUrgent10000,
  };

  static const Set<String> subscriptionProductIds = {
    subscriptionMonthly500,
    legacySubscriptionMonthly500,
  };

  static const Set<String> consumableProductIds = {
    ticketNormal600,
    ticketUrgent10000,
    legacyTicketNormal600,
    legacyTicketUrgent10000,
  };

  static bool isSubscriptionProduct(String productId) =>
      subscriptionProductIds.contains(productId);

  static bool isConsumableProduct(String productId) =>
      consumableProductIds.contains(productId);

  static bool isNormalTicket(String productId) =>
      productId == ticketNormal600 || productId == legacyTicketNormal600;

  static bool isUrgentTicket(String productId) =>
      productId == ticketUrgent10000 || productId == legacyTicketUrgent10000;

  /// Play / ローカルキャッシュから返る ID を正規 ID に揃える。
  static String resolveCanonicalProductId(String productId) {
    if (isSubscriptionProduct(productId)) return subscriptionMonthly500;
    if (isUrgentTicket(productId)) return ticketUrgent10000;
    if (isNormalTicket(productId)) return ticketNormal600;
    return productId;
  }
}
