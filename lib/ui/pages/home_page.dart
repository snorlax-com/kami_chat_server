import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_intro_page.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/ui/pages/meditation_page.dart';
import 'package:kami_face_oracle/ui/pages/store_page.dart';
import 'package:kami_face_oracle/services/store_access_service.dart';
import 'package:kami_face_oracle/services/store_subscription_flow.dart';
import 'package:kami_face_oracle/services/currency_service.dart';
import 'package:kami_face_oracle/ui/pages/legal_document_page.dart';
import 'package:kami_face_oracle/ui/pages/privacy_settings_page.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/services/tutorial_diagnosis_local_store.dart';
import 'package:kami_face_oracle/ui/pages/personality_diagnosis_result_page.dart';
import 'package:kami_face_oracle/ui/pages/home_account_settings_page.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';
import 'package:kami_face_oracle/models/personality_type_detail.dart';

void showHomeLegalMenu(BuildContext context) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const ListTile(
            title: Text('Legal & Privacy', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Privacy & Consent (Withdraw)'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => const PrivacySettingsPage(),
                  ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Terms of Service'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        const LegalDocumentPage(title: 'Terms of Service', assetPath: 'assets/legal/terms_en.txt'),
                  ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        const LegalDocumentPage(title: 'Privacy Policy', assetPath: 'assets/legal/privacy_en.txt'),
                  ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Biometric Policy & Release'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => const LegalDocumentPage(
                        title: 'Biometric Policy & Release', assetPath: 'assets/legal/biometric_en.txt'),
                  ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('AI Transparency Notice'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => const LegalDocumentPage(
                        title: 'AI Transparency Notice', assetPath: 'assets/legal/ai_transparency_en.txt'),
                  ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.cookie_outlined),
            title: const Text('Cookie Policy'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => const LegalDocumentPage(
                        title: 'Cookie Policy', assetPath: 'assets/legal/cookie_policy_en.txt'),
                  ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.data_object),
            title: const Text('Data Requests (Access / Delete)'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => const LegalDocumentPage(
                        title: 'Data Requests', assetPath: 'assets/legal/data_requests_en.txt'),
                  ));
            },
          ),
        ],
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.embedInShell = false});

  /// タブシェル内では [false]。独自の [AppBar] を出さない。
  final bool embedInShell;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _point = 0; // 既存ポイント
  int _coins = 0;
  int _gems = 0;
  int _fragments = 0;
  Deity? _tutorialDeity; // チュートリアルで選ばれた神
  PersonalityTypeDetail? _tutorialPillarDetail; // 柱に紐づく性格説明（JSON）
  late AnimationController _glowController;
  bool _hasCachedTutorialDiagnosis = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _loadCachedDiagnosisFlag();
  }

  Future<void> _loadCachedDiagnosisFlag() async {
    final v = await TutorialDiagnosisLocalStore.hasStoredResult();
    if (mounted) setState(() => _hasCachedTutorialDiagnosis = v);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _glowController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCachedDiagnosisFlag();
      _loadTutorialDeity();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTutorialDeity();
  }

  Future<void> _load() async {
    final p = await Storage.getPoint();
    final w = await CurrencyService.load();
    setState(() {
      _point = p;
      _coins = w['coins']!;
      _gems = w['gems']!;
      _fragments = w['fragments']!;
    });
  }

  Future<void> _openStore() async {
    if (!await StoreAccessService.canOpenStore()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ストアはサブスク加入後にご利用いただけます。占い相談から加入してください。')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const StorePage()));
  }

  Future<void> _loadTutorialDeity() async {
    final deityId = await Storage.getTutorialDeity();
    if (deityId == null) {
      if (mounted) {
        setState(() {
          _tutorialDeity = null;
          _tutorialPillarDetail = null;
        });
      }
      return;
    }
    final deity = deities.firstWhere(
      (d) => d.id == deityId,
      orElse: () => deities.first,
    );
    final detail = await PersonalityTypeDetailService.getDetailByPillarId(deityId);
    if (mounted) {
      setState(() {
        _tutorialDeity = deity;
        _tutorialPillarDetail = detail;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final deityColor = _tutorialDeity != null
        ? Color(int.parse(_tutorialDeity!.colorHex.replaceFirst('#', '0xff')))
        : const Color(0xFF6C63FF);

    final stack = Stack(
        children: [
          // 背景：チュートリアルで選ばれた神があればその神を大きく、なければ18柱のシンボルグリッド
          Positioned.fill(
            child: _tutorialDeity != null
                ? AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, _) {
                      final pulse = (math.sin(_glowController.value * 2 * math.pi) + 1) / 2;
                      return Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.center,
                            colors: [
                              deityColor.withOpacity(0.25 + pulse * 0.1),
                              deityColor.withOpacity(0.15 + pulse * 0.05),
                              Colors.black.withOpacity(0.8),
                              Colors.black,
                            ],
                            stops: const [0.0, 0.3, 0.7, 1.0],
                            radius: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Opacity(
                            opacity: 0.15 + pulse * 0.05,
                            child: Image.asset(
                              _tutorialDeity!.symbolAsset,
                              width: MediaQuery.of(context).size.width * 0.8,
                              height: MediaQuery.of(context).size.width * 0.8,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, _) {
                      final wave = math.sin(_glowController.value * 2 * math.pi) * 0.05;
                      return Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(
                              math.sin(_glowController.value * 2 * math.pi) * 0.1,
                              math.cos(_glowController.value * 2 * math.pi) * 0.1,
                            ),
                            colors: [
                              const Color(0xFF8B5CF6).withOpacity(0.15),
                              const Color(0xFF06B6D4).withOpacity(0.1),
                              const Color(0xFF0A0E1A).withOpacity(0.8),
                              const Color(0xFF000000),
                            ],
                            stops: const [0.0, 0.3, 0.7, 1.0],
                            radius: 1.5,
                          ),
                        ),
                        child: Stack(
                          children: [
                            // 星空エフェクト
                            ...List.generate(50, (i) {
                              final angle = (i / 50) * 2 * math.pi;
                              final radius = 0.2 + (i % 4) * 0.15;
                              final x = 0.5 + math.cos(angle + _glowController.value * math.pi) * radius;
                              final y = 0.5 + math.sin(angle + _glowController.value * math.pi) * radius;
                              final twinkle = (math.sin(_glowController.value * 6 * math.pi + i) + 1) / 2;
                              return Positioned(
                                left: x * MediaQuery.of(context).size.width,
                                top: y * MediaQuery.of(context).size.height,
                                child: Container(
                                  width: 1.5 + twinkle * 1.5,
                                  height: 1.5 + twinkle * 1.5,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.5 + twinkle * 0.5),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.white.withOpacity(0.6),
                                        blurRadius: 3 + twinkle * 3,
                                        spreadRadius: 0.5,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            // 神のシンボルグリッド
                            Opacity(
                              opacity: 0.2 + wave,
                              child: GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                itemCount: deities.length,
                                itemBuilder: (context, i) {
                                  final d = deities[i];
                                  final godColor = Color(int.parse(d.colorHex.replaceFirst('#', '0xff')));
                                  final itemPulse = (math.sin(_glowController.value * 2 * math.pi + i * 0.5) + 1) / 2;
                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        colors: [
                                          godColor.withOpacity(0.2 + itemPulse * 0.1),
                                          godColor.withOpacity(0.05),
                                          Colors.transparent,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: godColor.withOpacity(0.3 + itemPulse * 0.2),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: godColor.withOpacity(0.3 + itemPulse * 0.2),
                                          blurRadius: 15 + itemPulse * 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Image.asset(d.symbolAsset, fit: BoxFit.contain),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          // 神秘的なグラデーションオーバーレイ（読みやすさと神秘性を両立）
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xAA0A0E1A).withOpacity(0.4),
                      const Color(0xEE0A0E1A).withOpacity(0.85),
                      const Color(0xFF000000).withOpacity(0.95),
                    ],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // コンテンツ
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  _BalanceBar(
                    point: _point,
                    coins: _coins,
                    gems: _gems,
                    fragments: _fragments,
                    onAddTest: () async {
                      final v = await Storage.addPoint(10);
                      await CurrencyService.addCoins(10);
                      await _load();
                      setState(() => _point = v);
                    },
                  ),
                  if (_tutorialDeity != null) ...[
                    const SizedBox(height: 20),
                    _TutorialPillarHomeCard(
                      deity: _tutorialDeity!,
                      detail: _tutorialPillarDetail,
                    ),
                  ],
                  const SizedBox(height: 24),
                  // 機能カード（2列グリッド）
                  Row(
                    children: [
                      Expanded(
                        child: _FeatureCard(
                          icon: Icons.self_improvement,
                          title: '瞑想',
                          subtitle: '心を整える',
                          color: const Color(0xFF14B8A6),
                          onPressed: () =>
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const MeditationPage())),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FeatureCard(
                          icon: Icons.store,
                          title: 'ストア',
                          subtitle: 'アイテム',
                          color: const Color(0xFFFFB84D),
                          onPressed: () => unawaited(_openStore()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // チュートリアルボタン（E2E: data-testid 代わりに Key）
                  Semantics(
                    button: true,
                    label: 'チュートリアルを開く',
                    child: OutlinedButton.icon(
                      key: const Key('e2e-tutorial'),
                      onPressed: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const TutorialIntroPage())),
                      icon: const Icon(Icons.school),
                      label: const Text('チュートリアル'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.white.withOpacity(0.3), width: 1.5),
                      ),
                    ),
                  ),
                  if (_hasCachedTutorialDiagnosis) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      button: true,
                      label: '保存された性格診断結果を開く',
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final r = await TutorialDiagnosisLocalStore.loadResult();
                          if (!context.mounted || r == null) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PersonalityDiagnosisResultPage(diagnosisResult: r),
                            ),
                          );
                          await _loadCachedDiagnosisFlag();
                        },
                        icon: const Icon(Icons.psychology_alt),
                        label: const Text('保存された性格診断を開く'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: const Color(0xFF8B5CF6).withOpacity(0.6), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          )
        ],
      );

    if (widget.embedInShell) {
      final w = E2E.isEnabled ? Semantics(label: 'e2e-home-ready', child: stack) : stack;
      return w;
    }

    final body = Scaffold(
      appBar: AppBar(
        title: const Text('神が降臨する顔占い'),
        elevation: 0,
        actions: [
          Semantics(
            label: '利用規約とプライバシー、同意設定を開く',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.description_outlined),
              tooltip: 'Legal & Privacy',
              onPressed: () => showHomeLegalMenu(context),
            ),
          ),
          Semantics(
            label: '設定（ログイン・ログアウト）を開く',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '設定',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const HomeAccountSettingsPage(),
                  ),
                );
              },
            ),
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF8B5CF6).withOpacity(0.3),
                const Color(0xFF06B6D4).withOpacity(0.2),
                const Color(0xFF0A0E1A),
              ],
            ),
          ),
        ),
      ),
      body: stack,
    );
    return E2E.isEnabled ? Semantics(label: 'e2e-home-ready', child: body) : body;
  }
}

/// チュートリアルで定めた柱のキャラ画像と、性格データ上の特徴を表示
class _TutorialPillarHomeCard extends StatelessWidget {
  const _TutorialPillarHomeCard({
    required this.deity,
    this.detail,
  });

  final Deity deity;
  final PersonalityTypeDetail? detail;

  String get _characterAsset {
    final p = detail?.characterImage;
    if (p != null && p.trim().isNotEmpty) {
      return p;
    }
    return 'assets/characters/${deity.id}.png';
  }

  String get _pillarLabel {
    final t = detail?.pillarTitle;
    if (t != null && t.trim().isNotEmpty) {
      return t;
    }
    return deity.role;
  }

  String _featureExcerpt() {
    final core = detail?.sections['core']?.content;
    if (core != null && core.trim().isNotEmpty) {
      return _truncateFeature(core, 360);
    }
    final intro = detail?.sections['intro']?.content;
    if (intro != null && intro.trim().isNotEmpty) {
      return _truncateFeature(intro, 360);
    }
    return '${deity.role}。${deity.shortMessage}';
  }

  String _truncateFeature(String s, int maxChars) {
    var t = s.trim();
    t = t.replaceAll('\r\n', '\n');
    if (t.length <= maxChars) {
      return t;
    }
    final cut = t.substring(0, maxChars);
    final nl = cut.lastIndexOf('\n\n');
    if (nl > 100) {
      return '${cut.substring(0, nl).trim()}\n\n…';
    }
    final period = cut.lastIndexOf('。');
    if (period > 120) {
      return '${cut.substring(0, period + 1)}\n\n…';
    }
    return '$cut…';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(int.parse(deity.colorHex.replaceFirst('#', '0xff')));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 0,
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.2),
            Colors.black.withValues(alpha: 0.5),
            const Color(0xFF0A0E1A).withValues(alpha: 0.9),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Container(
              // 縦長のキャラ画像でも「全体が見える」ように cover ではなく contain を採用。
              // 余白が出る場合は背景に薄い黒を敷いて見栄えを安定させる。
              color: Colors.black.withValues(alpha: 0.28),
              constraints: const BoxConstraints(minHeight: 200),
              child: Image.asset(
                _characterAsset,
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.black38,
                  alignment: Alignment.center,
                  child: Image.asset(
                    deity.symbolAsset,
                    fit: BoxFit.contain,
                    width: 120,
                    height: 120,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'あなたの柱',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.65),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '【${deity.nameJa}】$_pillarLabel',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: accent,
                    height: 1.25,
                  ),
                ),
                if (detail != null && (detail!.typeName.isNotEmpty)) ...[
                  const SizedBox(height: 6),
                  Text(
                    detail!.typeName,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '特徴',
                  style: TextStyle(
                    fontSize: 12,
                    color: accent.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _featureExcerpt(),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceBar extends StatelessWidget {
  final int point;
  final int coins;
  final int gems;
  final int fragments;
  final VoidCallback onAddTest;
  const _BalanceBar(
      {required this.point, required this.coins, required this.gems, required this.fragments, required this.onAddTest});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ポイント $point、コイン $coins、ジェム $gems、フラグメント $fragments',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withOpacity(0.4),
              Colors.black.withOpacity(0.3),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.account_balance_wallet, color: Colors.amberAccent, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ポイント',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$point',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            _CurrencyItem(
              icon: Icons.monetization_on,
              value: coins,
              color: Colors.amberAccent,
            ),
            const SizedBox(width: 8),
            _CurrencyItem(
              icon: Icons.diamond,
              value: gems,
              color: Colors.cyanAccent,
            ),
            const SizedBox(width: 8),
            _CurrencyItem(
              icon: Icons.auto_awesome,
              value: fragments,
              color: Colors.purpleAccent,
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyItem extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;

  const _CurrencyItem({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onPressed;
  final bool showUnreadDot;

  const _FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onPressed,
    this.showUnreadDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title。$subtitle。',
      hint: 'ダブルタップで開く',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withOpacity(0.2),
                  color.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          shadows: [
                            Shadow(
                              color: color.withOpacity(0.6),
                              blurRadius: 8,
                              offset: const Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showUnreadDot)
            Positioned(
              top: 8,
              right: 8,
              child: IgnorePointer(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.45),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
