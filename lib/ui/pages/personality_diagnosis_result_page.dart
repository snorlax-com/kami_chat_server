import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/diagnosis_api_service.dart';
import 'package:kami_face_oracle/services/guest_session_service.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';
import 'package:kami_face_oracle/services/tutorial_diagnosis_local_store.dart';
import 'package:kami_face_oracle/ui/pages/personality_detail_page_view.dart';
import 'package:kami_face_oracle/ui/widgets/auraface_auth_sheet.dart';

class PersonalityDiagnosisResultPage extends StatefulWidget {
  final PersonalityTreeDiagnosisResult diagnosisResult;

  const PersonalityDiagnosisResultPage({
    super.key,
    required this.diagnosisResult,
  });

  @override
  State<PersonalityDiagnosisResultPage> createState() => _PersonalityDiagnosisResultPageState();
}

class _PersonalityDiagnosisResultPageState extends State<PersonalityDiagnosisResultPage> {
  String? _pillarId;
  String? _displayTypeName;
  String? _characterImagePath;
  String? _pillarTitle;

  /// サーバー同期後に差し替え（再ログイン時の GET /me 用）
  PersonalityTreeDiagnosisResult? _resultOverride;

  bool _detailUnlocked = false;
  bool _tutorialPosted = false;
  StreamSubscription<User?>? _authSub;

  PersonalityTreeDiagnosisResult get _effective =>
      _resultOverride ?? widget.diagnosisResult;

  bool get _showGuestLock => !_detailUnlocked;

  @override
  void initState() {
    super.initState();
    _loadPillarIdAndPlayMusic();
    _loadDisplayTypeName();
    // google-services 未設定時は FirebaseAuth が使えない
    if (CloudService.isFirebaseAppReady) {
      _authSub = FirebaseAuth.instance.userChanges().listen((_) {
        if (mounted) _refreshUnlockFromServer();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final fromPrefs = await TutorialDiagnosisLocalStore.isUnlocked();
    if (fromPrefs && mounted) {
      setState(() => _detailUnlocked = true);
    }
    await _refreshUnlockFromServer();
  }

  Future<void> _refreshUnlockFromServer() async {
    if (!CloudService.isFirebaseAppReady) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return;
    final token = await u.getIdToken();
    if (token == null) return;
    final me = await DiagnosisApiService.fetchMyDiagnosis(idToken: token);
    if (!mounted) return;
    if (me != null && me['isUnlocked'] == true) {
      final dj = me['detailJson'];
      if (dj is Map) {
        try {
          _resultOverride =
              PersonalityTreeDiagnosisResult.fromJson(Map<String, dynamic>.from(dj));
        } catch (_) {}
      }
      await TutorialDiagnosisLocalStore.setUnlocked(true);
      if (_resultOverride != null) {
        await TutorialDiagnosisLocalStore.saveResultJson(jsonEncode(_resultOverride!.toJson()));
      }
      if (mounted) {
        setState(() => _detailUnlocked = true);
      }
      await _loadDisplayTypeName();
    }
  }

  Future<void> _loadDisplayTypeName() async {
    final detail = await PersonalityTypeDetailService.getDetail(_effective.personalityType);
    if (!mounted) return;
    if (detail != null && detail.typeName.isNotEmpty) {
      setState(() => _displayTypeName = detail.typeName);
    } else {
      setState(() => _displayTypeName = _effective.personalityTypeName);
    }
  }

  void _safeSetPillarState({
    required String pillarId,
    required String characterImagePath,
    required String? pillarTitle,
  }) {
    if (!mounted) return;
    setState(() {
      _pillarId = pillarId;
      _characterImagePath = characterImagePath;
      _pillarTitle = pillarTitle;
    });
  }

  Future<void> _loadPillarIdAndPlayMusic() async {
    final detail = await PersonalityTypeDetailService.getDetail(_effective.personalityType);
    if (detail != null) {
      final pillarId = detail.pillarId;
      final characterImagePath = 'assets/characters/${pillarId.toLowerCase()}.png';

      String? pillarTitle;
      if (detail.pillarTitle.isNotEmpty) {
        pillarTitle = detail.pillarTitle;
      } else {
        try {
          final deity = deities.firstWhere(
            (d) => d.id.toLowerCase() == pillarId.toLowerCase(),
          );
          pillarTitle = deity.role;
        } catch (e) {
          pillarTitle = pillarId;
        }
      }

      _safeSetPillarState(
        pillarId: pillarId,
        characterImagePath: characterImagePath,
        pillarTitle: pillarTitle,
      );
      await _initBackgroundMusic(pillarId);
      await _maybePostTutorialToServer(pillarId);
    }
  }

  Future<void> _initBackgroundMusic(String pillarId) async {
    try {
      await BackgroundMusicService().playMeditationMusic(pillarId.toLowerCase());
    } catch (e) {
      debugPrint('[PersonalityDiagnosisResultPage] BGM: $e');
    }
  }

  Future<void> _maybePostTutorialToServer(String pillarId) async {
    if (_tutorialPosted) return;
    _tutorialPosted = true;
    try {
      final gid = await GuestSessionService.ensureGuestSessionId();
      await DiagnosisApiService.saveTutorialDiagnosis(
        guestSessionId: gid,
        pillarKey: pillarId.toLowerCase(),
        summaryText: 'あなたの柱が降臨しました',
        detailJson: _effective.toJson(),
      );
      await TutorialDiagnosisLocalStore.saveResultJson(jsonEncode(_effective.toJson()));
    } catch (e) {
      debugPrint('[PersonalityDiagnosisResultPage] tutorial API: $e');
    }
  }

  /// Firebase 未設定ビルド用: クラウド保存・ログインはできないが、この端末で詳細まで開く
  Future<void> _unlockLocallyWithoutFirebase() async {
    try {
      await TutorialDiagnosisLocalStore.saveResultJson(jsonEncode(_effective.toJson()));
    } catch (_) {}
    await TutorialDiagnosisLocalStore.setUnlocked(true);
    if (!mounted) return;
    setState(() => _detailUnlocked = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'アカウント連携はこのビルドでは使えません。診断の詳細をこの端末で表示します。（クラウドには保存されません）',
        ),
        duration: Duration(seconds: 5),
        backgroundColor: Color(0xFF5B21B6),
      ),
    );
  }

  Future<void> _openAuthAndClaim() async {
    if (!CloudService.isFirebaseAppReady) {
      await _unlockLocallyWithoutFirebase();
      if (mounted) await _openDetailPage();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1F3A),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: AurafaceAuthSheet(
          onAuthenticated: (user) async {
            Navigator.of(ctx).pop();
            await _runClaim(user);
          },
        ),
      ),
    );
  }

  Future<void> _runClaim(User user) async {
    try {
      final token = await user.getIdToken();
      final gid = await GuestSessionService.readStoredId();
      if (token == null || gid == null || gid.isEmpty) {
        throw Exception('セッション情報が不足しています');
      }
      await DiagnosisApiService.claimGuestData(guestSessionId: gid, idToken: token);
      await TutorialDiagnosisLocalStore.setUnlocked(true);
      if (mounted) {
        setState(() => _detailUnlocked = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('診断結果をアカウントに保存しました。詳細を表示します。'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      // 本番 Render が古く identity API が無いとき claim が 404 になる（ログで多発）
      final isServerIdentityUnavailable = s.contains('claim failed: 404') ||
          s.contains('claim failed: 502') ||
          s.contains('claim failed: 503') ||
          s.contains('Cannot POST /api/auth/claim-guest-data');
      if (isServerIdentityUnavailable) {
        try {
          await TutorialDiagnosisLocalStore.saveResultJson(jsonEncode(_effective.toJson()));
        } catch (_) {}
        await TutorialDiagnosisLocalStore.setUnlocked(true);
        if (!mounted) return;
        setState(() => _detailUnlocked = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ログインは成功しました。サーバーに診断保存APIがまだ無いため、この端末のみで詳細を表示します。'
              '（kami_chat_server を再デプロイするとクラウド保存できます）',
            ),
            backgroundColor: Color(0xFF92400E),
            duration: Duration(seconds: 12),
          ),
        );
        return;
      }
      final isUnauthorized =
          s.contains('401') || s.toLowerCase().contains('unauthorized');
      final msg = isUnauthorized
          ? 'Google ログインは成功しましたが、サーバーが Firebase トークンを検証できませんでした。'
              'kami_chat_server に FIREBASE_SERVICE_ACCOUNT_JSON（サービスアカウント JSON）を設定して再デプロイしてください。'
          : '保存に失敗しました: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 12),
        ),
      );
    }
  }

  String _personalityTypeNameForDetail() {
    final d = _displayTypeName;
    if (d != null && d.isNotEmpty) return d;
    final n = _effective.personalityTypeName;
    if (n.isNotEmpty) return n;
    return 'タイプ ${_effective.personalityType}';
  }

  Future<void> _openDetailPage() async {
    if (_showGuestLock) {
      await _openAuthAndClaim();
      return;
    }
    if (_pillarId == null) {
      await _loadPillarIdAndPlayMusic();
    }
    if (!mounted) return;
    // pillarId は詳細JSONから再取得（非同期完了前にタップした場合の null 防止）
    final pillarForDetail = _pillarId ??
        (await PersonalityTypeDetailService.getDetail(_effective.personalityType))?.pillarId;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalityDetailPageView(
          personalityType: _effective.personalityType,
          personalityTypeName: _personalityTypeNameForDetail(),
          pillarId: pillarForDetail,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = _personalityTypeNameForDetail();

    return Scaffold(
      appBar: AppBar(
        title: const Text('性格診断結果'),
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
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  colors: [
                    const Color(0xFF8B5CF6).withOpacity(0.2),
                    const Color(0xFF06B6D4).withOpacity(0.15),
                    const Color(0xFF0A0E1A).withOpacity(0.9),
                    const Color(0xFF000000),
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                  radius: 1.5,
                ),
              ),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildChatMessage(
                        message: _showGuestLock
                            ? 'あなたの柱が降臨しました。\n\nこの柱は、あなたの本質の入口です。\n\n柱の名: 「$typeLabel」'
                            : '診断結果：あなたの性格タイプは「$typeLabel」です。',
                        isFirst: true,
                      ),
                      const SizedBox(height: 12),
                      if (_showGuestLock) ...[
                        _buildChatMessage(
                          message:
                              '詳細な性格診断を開示するには、ログインまたはメールアドレス認証が必要です。\n\n認証後、診断結果は保存され、次回も同じ内容を確認できます。',
                        ),
                        const SizedBox(height: 12),
                        _buildLockedCard(hint: '性格タイプの深掘り解説'),
                        const SizedBox(height: 12),
                        _buildLockedCard(hint: '各層の判定・根拠'),
                        const SizedBox(height: 12),
                        _buildLockedCard(hint: '相談機能・保存済み履歴'),
                      ] else ...[
                        _buildChatMessage(message: _effective.personalityDescription),
                        const SizedBox(height: 12),
                        ..._effective.layerResults.entries.map((entry) {
                          final displayKey =
                              entry.key.replaceAll('（', ' (').replaceAll('）', ')');
                          return Column(
                            children: [
                              _buildChatMessage(message: '$displayKey: ${entry.value}'),
                              const SizedBox(height: 12),
                            ],
                          );
                        }),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E1A).withOpacity(0.9),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showGuestLock)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _openAuthAndClaim,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('診断結果を保存して続きを見る'),
                        ),
                      ),
                    if (_showGuestLock) const SizedBox(height: 10),
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF8B5CF6).withOpacity(0.6),
                              const Color(0xFF06B6D4).withOpacity(0.5),
                              const Color(0xFF8B5CF6).withOpacity(0.6),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF8B5CF6).withOpacity(0.5),
                              blurRadius: 25,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _openDetailPage,
                          icon: Icon(
                            _showGuestLock ? Icons.login : Icons.auto_awesome,
                            size: 24,
                          ),
                          label: Text(
                            _showGuestLock ? 'ログインして詳細を見る' : '詳しく見る',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLockedCard({required String hint}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A).withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: Colors.white54),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hint,
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatMessage({
    required String message,
    bool isFirst = false,
  }) {
    final iconPath = _characterImagePath ?? 'assets/characters/shisaru.png';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.only(right: 12, top: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF8B5CF6).withOpacity(0.6),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.4),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                iconPath,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[800],
                    child: const Icon(Icons.face, color: Colors.white70, size: 28),
                  );
                },
              ),
            ),
          ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F3A).withOpacity(0.8),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                border: Border.all(
                  color: const Color(0xFF8B5CF6).withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFirst && _pillarTitle != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 14,
                            color: const Color(0xFF8B5CF6).withOpacity(0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _pillarTitle!,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF8B5CF6).withOpacity(0.9),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    message,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 15,
                      height: 1.6,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}
