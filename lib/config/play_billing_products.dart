/// Google Play 課金商品 ID の単一ソース（Play Console と完全一致させる）。
///
/// 正規 ID（Play Console 内部テスト登録名）:
/// - subscription_monthly_500
/// - normal_ticket_600
/// - urgent_ticket_10000
///
/// 旧 ID は query 互換のため [legacy*] も含める。
class PlayBillingProducts {
  PlayBillingProducts._();

  static const String subscriptionMonthly500 = 'subscription_monthly_500';
  static const String ticketNormal600 = 'normal_ticket_600';
  static const String ticketUrgent10000 = 'urgent_ticket_10000';

  static const String legacySubscriptionMonthly500 = 'monthly_subscription_500';
  static const String legacyTicketNormal600 = 'ticket_normal_600';
  static const String legacyTicketUrgent10000 = 'ticket_urgent_10000';

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

  static String resolveCanonicalProductId(String productId) {
    if (productId == legacySubscriptionMonthly500) return subscriptionMonthly500;
    if (productId == legacyTicketNormal600) return ticketNormal600;
    if (productId == legacyTicketUrgent10000) return ticketUrgent10000;
    if (isSubscriptionProduct(productId)) return subscriptionMonthly500;
    if (isUrgentTicket(productId)) return ticketUrgent10000;
    if (isNormalTicket(productId)) return ticketNormal600;
    return productId;
  }

  /// Google Play API / サーバー検証に渡す ID（Play Console 上の実 ID を優先）。
  static String playStoreProductId(String productId) {
    final id = productId.trim();
    if (allQueryProductIds.contains(id)) return resolveCanonicalProductId(id);
    return resolveCanonicalProductId(id);
  }
}
