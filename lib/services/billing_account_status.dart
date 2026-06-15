/// サーバー同期後の課金アカウント状態。
class BillingAccountStatus {
  const BillingAccountStatus({
    required this.normal,
    required this.urgent,
    required this.subscribed,
  });

  final int normal;
  final int urgent;
  final bool subscribed;

  factory BillingAccountStatus.fromJson(Map<String, dynamic> json) {
    return BillingAccountStatus(
      normal: (json['normal'] as num?)?.toInt() ?? 0,
      urgent: (json['urgent'] as num?)?.toInt() ?? 0,
      subscribed: json['subscribed'] == true,
    );
  }
}
