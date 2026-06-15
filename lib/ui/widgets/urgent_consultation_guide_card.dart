import 'package:flutter/material.dart';
import 'package:kami_face_oracle/config/urgent_consultation_guide.dart';

/// 至急質問券の購入前確認（注意書き + はい／いいえ）。
class UrgentConsultationPurchaseConfirm {
  UrgentConsultationPurchaseConfirm._();

  static Future<bool> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        title: Text(
          '【${UrgentConsultationGuide.title}】',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Text(
            '${UrgentConsultationGuide.body.trim()}\n\n'
            '${UrgentConsultationGuide.purchaseConfirmQuestion}',
            style: const TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('いいえ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('はい'),
          ),
        ],
      ),
    ).then((v) => v == true);
  }
}

/// 【至急相談について】の説明カード。
class UrgentConsultationGuideCard extends StatelessWidget {
  final bool initiallyExpanded;

  const UrgentConsultationGuideCard({
    super.key,
    this.initiallyExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2A1F1F),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.45)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          iconColor: Colors.redAccent.shade100,
          collapsedIconColor: Colors.redAccent.shade100,
          title: Row(
            children: [
              Icon(Icons.bolt, color: Colors.redAccent.shade200, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '【${UrgentConsultationGuide.title}】',
                  style: TextStyle(
                    color: Colors.redAccent.shade100,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                UrgentConsultationGuide.body.trim(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
