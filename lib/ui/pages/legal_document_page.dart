import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kami_face_oracle/core/legal_config.dart';

/// Displays a legal document from assets with placeholders replaced.
class LegalDocumentPage extends StatefulWidget {
  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.assetPath,
  });

  final String title;
  final String assetPath;

  @override
  State<LegalDocumentPage> createState() => _LegalDocumentPageState();
}

class _LegalDocumentPageState extends State<LegalDocumentPage> {
  String _text = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await rootBundle.loadString(widget.assetPath);
      final replaced = _replacePlaceholders(s);
      if (mounted) {
        setState(() {
          _text = replaced;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _text = '';
          _error = e.toString();
        });
      }
    }
  }

  static String _replacePlaceholders(String raw) {
    return raw
        .replaceAll('[YYYY-MM-DD]', LegalConfig.lastUpdated)
        .replaceAll('[Company Legal Name]', LegalConfig.companyLegalName)
        .replaceAll('[Registered Address]', LegalConfig.registeredAddress)
        .replaceAll('[your-domain]', LegalConfig.domain)
        .replaceAll('legal@[your-domain]', LegalConfig.legalEmail)
        .replaceAll('privacy@[your-domain]', LegalConfig.privacyEmail)
        .replaceAll('support@[your-domain]', LegalConfig.supportEmail)
        .replaceAll('ai@[your-domain]', LegalConfig.aiEmail)
        .replaceAll('[State/Country]', 'Japan')
        .replaceAll('[X days]', '30');
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${widget.title}。法的文書を表示しています。',
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _text.isEmpty ? 'Loading...' : _text,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
      ),
    );
  }
}
