import 'package:flutter/material.dart';
import 'package:kami_face_oracle/features/consent/consent_service.dart';
import 'package:kami_face_oracle/ui/pages/legal_document_page.dart';

/// Mandatory biometric consent modal before image upload/camera.
/// Requires: explicit biometric consent, "image is self or permission", "not medical/professional advice".
class BiometricConsentModal extends StatefulWidget {
  const BiometricConsentModal({super.key});

  /// Returns true if user agreed, false if cancelled.
  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
      builder: (ctx) => const BiometricConsentModal(),
    );
    return result ?? false;
  }

  @override
  State<BiometricConsentModal> createState() => _BiometricConsentModalState();
}

class _BiometricConsentModalState extends State<BiometricConsentModal> {
  bool _ageConfirmed = false;
  bool _biometric = false;
  bool _imageSelfOrPermission = false;
  bool _understandNotAdvice = false;

  bool get _canAgree => _ageConfirmed && _biometric && _imageSelfOrPermission && _understandNotAdvice;

  void _openPrivacy() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LegalDocumentPage(
          title: 'Privacy Policy',
          assetPath: 'assets/legal/privacy_en.txt',
        ),
      ),
    );
  }

  void _openTerms() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LegalDocumentPage(
          title: 'Terms of Service',
          assetPath: 'assets/legal/terms_en.txt',
        ),
      ),
    );
  }

  void _openBiometric() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LegalDocumentPage(
          title: 'Biometric Policy & Release',
          assetPath: 'assets/legal/biometric_en.txt',
        ),
      ),
    );
  }

  void _openAiNotice() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LegalDocumentPage(
          title: 'AI Transparency Notice',
          assetPath: 'assets/legal/ai_transparency_en.txt',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 1,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Semantics(
              label: '生体データの利用に同意してください。4つすべてにチェックを入れると同意できます。',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Biometric Data Consent',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Before using face analysis, you must read and agree to the following. No pre-checked boxes.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  // 1) Age 18+
                  CheckboxListTile(
                    value: _ageConfirmed,
                    onChanged: (v) => setState(() => _ageConfirmed = v ?? false),
                    title: const Text('I confirm I am 18 years or older.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  // 2) Explicit biometric consent
                  CheckboxListTile(
                    value: _biometric,
                    onChanged: (v) => setState(() => _biometric = v ?? false),
                    title: const Text(
                      'I explicitly consent to the processing of my biometric data (facial image) for AuraFace analysis.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  // 3) Image is self or permission
                  CheckboxListTile(
                    value: _imageSelfOrPermission,
                    onChanged: (v) => setState(() => _imageSelfOrPermission = v ?? false),
                    title: const Text(
                      'I confirm this image is of myself or I have explicit permission to use it.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  // 4) Not medical/professional advice
                  CheckboxListTile(
                    value: _understandNotAdvice,
                    onChanged: (v) => setState(() => _understandNotAdvice = v ?? false),
                    title: const Text(
                      'I understand the outputs are AI-generated and are not medical or professional advice.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: _openPrivacy,
                        child: const Text('Privacy Policy'),
                      ),
                      TextButton(
                        onPressed: _openTerms,
                        child: const Text('Terms'),
                      ),
                      TextButton(
                        onPressed: _openBiometric,
                        child: const Text('Biometric Policy'),
                      ),
                      TextButton(
                        onPressed: _openAiNotice,
                        child: const Text('AI Notice'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const minHeight = 52.0;
                      final useColumn = constraints.maxWidth < 360;
                      if (useColumn) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: minHeight,
                              child: FilledButton(
                                key: const Key('e2e-consent-accept'),
                                onPressed: _canAgree
                                    ? () async {
                                        await ConsentService.instance.setBiometricConsent(
                                          consent: true,
                                          ageConfirmedInModal: _ageConfirmed,
                                          imageIsSelfOrPermission: _imageSelfOrPermission,
                                          understandNotAdvice: _understandNotAdvice,
                                        );
                                        if (context.mounted) Navigator.of(context).pop(true);
                                      }
                                    : null,
                                child: const Text('I Agree'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: minHeight,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: minHeight,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SizedBox(
                              height: minHeight,
                              child: FilledButton(
                                key: const Key('e2e-consent-accept'),
                                onPressed: _canAgree
                                    ? () async {
                                        await ConsentService.instance.setBiometricConsent(
                                          consent: true,
                                          ageConfirmedInModal: _ageConfirmed,
                                          imageIsSelfOrPermission: _imageSelfOrPermission,
                                          understandNotAdvice: _understandNotAdvice,
                                        );
                                        if (context.mounted) Navigator.of(context).pop(true);
                                      }
                                    : null,
                                child: const Text('I Agree'),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
