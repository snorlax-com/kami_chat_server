import 'package:flutter/material.dart';
import 'package:kami_face_oracle/features/consent/consent_service.dart';
import 'package:kami_face_oracle/ui/pages/legal_document_page.dart';

/// Privacy / consent settings: withdraw biometric consent, links to legal docs.
class PrivacySettingsPage extends StatelessWidget {
  const PrivacySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Consent')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            title: Text(
              'Withdraw Biometric Consent',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Stop processing your facial data. You will need to consent again to use face analysis.',
            ),
          ),
          Semantics(
            button: true,
            label: '生体データの同意を取り下げる。ダブルタップで実行。',
            child: FilledButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Withdraw consent?'),
                    content: const Text(
                      'Your biometric consent will be withdrawn. Face analysis (camera/upload) will be blocked until you consent again.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Withdraw'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ConsentService.instance.withdrawBiometricConsent();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Biometric consent withdrawn.')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.fingerprint),
              label: const Text('Withdraw Biometric Consent'),
            ),
          ),
          const Divider(height: 32),
          const ListTile(title: Text('Legal documents', style: TextStyle(fontWeight: FontWeight.w600))),
          ListTile(
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LegalDocumentPage(
                  title: 'Privacy Policy',
                  assetPath: 'assets/legal/privacy_en.txt',
                ),
              ),
            ),
          ),
          ListTile(
            title: const Text('Biometric Policy & Release'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LegalDocumentPage(
                  title: 'Biometric Policy & Release',
                  assetPath: 'assets/legal/biometric_en.txt',
                ),
              ),
            ),
          ),
          ListTile(
            title: const Text('Data Requests (Access / Delete)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LegalDocumentPage(
                  title: 'Data Requests',
                  assetPath: 'assets/legal/data_requests_en.txt',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
