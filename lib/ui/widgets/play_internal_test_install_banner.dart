import 'package:flutter/material.dart';
import 'package:kami_face_oracle/services/play_store_launcher.dart';
import 'package:kami_face_oracle/services/store_subscription_flow.dart';

/// ADB 直インストール（release）向け: Play 内部テスト版のインストールを案内する。
class PlayInternalTestInstallBanner extends StatelessWidget {
  const PlayInternalTestInstallBanner({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Material(
        color: Colors.orange.shade900.withValues(alpha: 0.35),
        child: ListTile(
          leading: const Icon(Icons.shop, color: Colors.orangeAccent),
          title: const Text(
            'Google Play 課金には内部テスト版が必要です',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: const Text(
            'ADB 直インストールでは購入画面は開きません。Play Console の内部テストリンクから入れ直してください。',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          trailing: TextButton(
            onPressed: () => _openPlay(context),
            child: const Text('Play を開く'),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade900.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orangeAccent, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Google Play 課金を使うには内部テスト版が必要です',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'このアプリは PC から直接インストールされています。'
            '購入ボタンで Google Play の課金画面を開くには、Play Console の内部テスト参加リンクからインストールし直してください。',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _openPlay(context),
            icon: const Icon(Icons.shop),
            label: const Text('Play ストアを開く'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orangeAccent,
              side: const BorderSide(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPlay(BuildContext context) async {
    final ok = await StoreSubscriptionFlow.offerPlayStoreInstall(context);
    if (!ok && context.mounted) {
      await PlayStoreLauncher.openAppListing();
    }
  }
}
