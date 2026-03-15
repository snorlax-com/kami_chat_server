import 'package:flutter/material.dart';
import 'package:kami_face_oracle/features/consent/consent_service.dart';
import 'package:kami_face_oracle/ui/pages/legal_document_page.dart';

/// EU/UK strict: cookie consent banner. Show on first page view when region is EU/UK or unknown.
class CookieConsentBanner extends StatefulWidget {
  const CookieConsentBanner({
    super.key,
    required this.onComplete,
    this.regionGroup = 'EU',
  });

  final VoidCallback onComplete;
  final String regionGroup;

  static Future<bool> needToShow() async {
    final shown = await ConsentService.instance.hasCookieBannerBeenShown();
    return !shown;
  }

  @override
  State<CookieConsentBanner> createState() => _CookieConsentBannerState();
}

class _CookieConsentBannerState extends State<CookieConsentBanner> {
  bool _expanded = false;

  Future<void> _acceptAll() async {
    try {
      await ConsentService.instance.setCookiePreferences({
        'strictly_necessary': true,
        'analytics': true,
        'functional': true,
      });
      await ConsentService.instance.setCookieBannerShown();
    } catch (e) {
      debugPrint('CookieConsentBanner: _acceptAll failed $e');
    } finally {
      if (mounted) widget.onComplete();
    }
  }

  Future<void> _rejectNonEssential() async {
    try {
      await ConsentService.instance.setCookiePreferences({
        'strictly_necessary': true,
        'analytics': false,
        'functional': false,
      });
      await ConsentService.instance.setCookieBannerShown();
    } catch (e) {
      debugPrint('CookieConsentBanner: _rejectNonEssential failed $e');
    } finally {
      if (mounted) widget.onComplete();
    }
  }

  void _openCookiePolicy() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LegalDocumentPage(
          title: 'Cookie Policy',
          assetPath: 'assets/legal/cookie_policy_en.txt',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'We use cookies to operate the Service.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can accept all, reject non-essential cookies, or manage preferences.',
              style: TextStyle(fontSize: 14),
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _openCookiePolicy,
                child: const Text('Cookie Policy'),
              ),
            ],
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                const minHeight = 48.0;
                final useColumn = constraints.maxWidth < 400;
                if (useColumn) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: minHeight,
                        child: FilledButton(
                          onPressed: () async => await _acceptAll(),
                          child: const Text('Accept all'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: minHeight,
                        child: OutlinedButton(
                          onPressed: () async => await _rejectNonEssential(),
                          child: const Text('Reject non-essential'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: minHeight,
                        child: TextButton(
                          onPressed: () {
                            setState(() => _expanded = !_expanded);
                          },
                          child: Text(_expanded ? 'Less' : 'Manage preferences'),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() => _expanded = !_expanded);
                      },
                      child: Text(_expanded ? 'Less' : 'Manage preferences'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async => await _rejectNonEssential(),
                      child: const Text('Reject non-essential'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async => await _acceptAll(),
                      child: const Text('Accept all'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
