import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/integration_test_flags.dart';
import 'package:kami_face_oracle/core/personality_tree_classifier.dart';
import 'package:kami_face_oracle/services/cloud_service.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';
import 'package:kami_face_oracle/services/diagnosis_api_service.dart';
import 'package:kami_face_oracle/services/guest_session_service.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';
import 'package:kami_face_oracle/services/tutorial_diagnosis_local_store.dart';
import 'package:kami_face_oracle/ui/pages/personality_detail_page_view.dart';
import 'package:kami_face_oracle/services/auraface_auth_service.dart';
import 'package:kami_face_oracle/ui/widgets/tutorial_guest_exit_actions.dart';
import 'package:kami_face_oracle/ui/widgets/tutorial_guest_exit_scope.dart';

class PersonalityDiagnosisResultPage extends StatefulWidget {
  final PersonalityTreeDiagnosisResult diagnosisResult;

  /// チュートリアル撮影直後の結果画面（戻るで終了確認を必ず出す）。
  final bool isTutorialFlow;

  const PersonalityDiagnosisResultPage({
    super.key,
    required this.diagnosisResult,
    this.isTutorialFlow = false,
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
  bool _isOpeningDetail = false;
  int _loginAttemptId = 0;
  StreamSubscription<User?>? _authSub;

  PersonalityTreeDiagnosisResult get _effective =>
      _resultOverride ?? widget.diagnosisResult;

  bool get _showGuestLock => !_detailUnlocked;

  /// 未ログインで詳細ロック中（チュートリアル直後・保存診断の再表示を含む）。
  bool get _isGuestLockedFlow =>
      _showGuestLock && TutorialGuestExitActions.shouldConfirmExit(tutorialFlow: widget.isTutorialFlow);

  /// チュートリアル直後かつ未ログインのときだけ終了確認ダイアログを出す。
  bool get _needsTutorialGuestExitGuard =>
      widget.isTutorialFlow && _isGuestLockedFlow;

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    print(
      '[GuestExit] PersonalityDiagnosisResultPage init '
      'tutorialFlow=${widget.isTutorialFlow} guard=$_needsTutorialGuestExitGuard',
    );
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

  bool _isLoginAttemptCurrent(int attemptId) => mounted && attemptId == _loginAttemptId;

  Future<void> _cancelGuestLoginAttempt() async {
    _loginAttemptId++;
    debugPrint('[PersonalityDiagnosis] cancel guest login attempt=$_loginAttemptId');
    if (mounted) setState(() => _isOpeningDetail = false);
    unawaited(AurafaceAuthService.abortPendingGoogleSignIn());
  }

  Future<void> _bootstrap() async {
    if (widget.isTutorialFlow) {
      try {
        await TutorialDiagnosisLocalStore.persistTutorialResult(_effective);
        debugPrint('[PersonalityDiagnosis] tutorial result persisted locally');
      } catch (e) {
        debugPrint('[PersonalityDiagnosis] tutorial persist failed: $e');
        await TutorialDiagnosisLocalStore.markTutorialConsumed();
      }
    }
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
      await BackgroundMusicService().playMeditationMusic(pillarId.toLowerCase());
      await _maybePostTutorialToServer(pillarId);
    }
  }

  Future<void> _maybePostTutorialToServer(String pillarId) async {
    if (_tutorialPosted) return;
    _tutorialPosted = true;
    try {
      await TutorialDiagnosisLocalStore.persistTutorialResult(_effective);
      final gid = await GuestSessionService.ensureGuestSessionId();
      await DiagnosisApiService.saveTutorialDiagnosis(
        guestSessionId: gid,
        pillarKey: pillarId.toLowerCase(),
        summaryText: 'あなたの柱が降臨しました',
        detailJson: _effective.toJson(),
      );
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

  void _resetGuestLoginUiState() {
    if (mounted) setState(() => _isOpeningDetail = false);
  }

  Future<void> _popGuestResultWithoutLogin() async {
    _resetGuestLoginUiState();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _exitWithoutLoginFromResultPage() async {
    if (widget.isTutorialFlow) {
      _resetGuestLoginUiState();
      await TutorialGuestExitActions.finishWithoutLogin(context);
      return;
    }
    await _popGuestResultWithoutLogin();
  }

  /// Google ログイン → claim。成功時は [_detailUnlocked] が true。
  Future<bool> _loginWithGoogleAndClaim({bool showSuccessSnack = true}) async {
    debugPrint('[PersonalityDiagnosis] loginAndClaim start');
    if (!IntegrationTestFlags.hasGoogleSignInHang && !CloudService.isFirebaseAppReady) {
      await _unlockLocallyWithoutFirebase();
      return _detailUnlocked;
    }
    try {
      // ログイン UI 表示前に guest_session_id を確保（claim 時の「セッション不足」防止）
      await GuestSessionService.ensureGuestSessionId();
      final cred = await AurafaceAuthService.signInWithGoogle().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException('Google ログインがタイムアウトしました');
        },
      );
      final user = cred.user;
      if (user == null) {
        debugPrint('[PersonalityDiagnosis] loginAndClaim: no user');
        return false;
      }
      debugPrint('[PersonalityDiagnosis] loginAndClaim: google ok');
      await _runClaim(user, showSuccessSnack: showSuccessSnack);
      return _detailUnlocked;
    } on TimeoutException catch (e) {
      debugPrint('[PersonalityDiagnosis] loginAndClaim: timeout $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ログインがタイムアウトしました。もう一度お試しください。'),
            backgroundColor: Color(0xFF92400E),
          ),
        );
      }
      return false;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'aborted-by-user') {
        debugPrint('[PersonalityDiagnosis] loginAndClaim: cancelled');
        return false;
      }
      debugPrint('[PersonalityDiagnosis] loginAndClaim auth error: ${e.code}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'ログインに失敗しました'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
      return false;
    } catch (e) {
      debugPrint('[PersonalityDiagnosis] loginAndClaim failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ログインに失敗しました: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
      return false;
    }
  }

  Future<void> _unlockDetailAfterLogin({
    required bool showSuccessSnack,
    required String snackMessage,
    Color snackColor = Colors.green,
    Duration snackDuration = const Duration(seconds: 5),
  }) async {
    try {
      await TutorialDiagnosisLocalStore.saveResultJson(jsonEncode(_effective.toJson()));
    } catch (_) {}
    await TutorialDiagnosisLocalStore.setUnlocked(true);
    if (!mounted) return;
    setState(() => _detailUnlocked = true);
    if (showSuccessSnack) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snackMessage),
          backgroundColor: snackColor,
          duration: snackDuration,
        ),
      );
    }
  }

  Future<void> _runClaim(User user, {bool showSuccessSnack = true}) async {
    try {
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) {
        throw Exception('認証トークンを取得できませんでした');
      }
      final gid = await GuestSessionService.ensureGuestSessionId();

      if (gid.startsWith('guest_local_')) {
        await _unlockDetailAfterLogin(
          showSuccessSnack: showSuccessSnack,
          snackMessage: 'ログインしました。オフラインのため診断結果はこの端末に保存されます。',
          snackColor: const Color(0xFF92400E),
          snackDuration: const Duration(seconds: 8),
        );
        return;
      }

      await DiagnosisApiService.claimGuestData(guestSessionId: gid, idToken: token);
      await _unlockDetailAfterLogin(
        showSuccessSnack: showSuccessSnack,
        snackMessage: '診断結果をアカウントに保存しました。',
      );
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      final isRecoverable = s.contains('claim failed: 404') ||
          s.contains('claim failed: 502') ||
          s.contains('claim failed: 503') ||
          s.contains('claim failed: 400') ||
          s.contains('Cannot POST /api/auth/claim-guest-data') ||
          s.contains('TimeoutException') ||
          s.contains('SocketException') ||
          s.contains('Failed host lookup') ||
          s.contains('Connection refused') ||
          s.contains('401') ||
          s.toLowerCase().contains('unauthorized');
      if (isRecoverable) {
        final msg = s.contains('401') || s.toLowerCase().contains('unauthorized')
            ? 'ログインしました。サーバー連携は未設定のため、この端末で詳細を表示します。'
            : 'ログインしました。クラウド保存はできませんでしたが、この端末で詳細を表示します。';
        await _unlockDetailAfterLogin(
          showSuccessSnack: showSuccessSnack,
          snackMessage: msg,
          snackColor: const Color(0xFF92400E),
          snackDuration: const Duration(seconds: 10),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存に失敗しました: $e'),
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

  Future<void> _handleGuestBackOrExit({bool forcePrompt = false}) async {
    if (_isOpeningDetail) {
      await _cancelGuestLoginAttempt();
      return;
    }
    // ignore: avoid_print
    print(
      '[GuestExit] result page back tap guestLock=$_showGuestLock '
      'guard=$_needsTutorialGuestExitGuard unlocked=$_detailUnlocked force=$forcePrompt',
    );
    if (forcePrompt) {
      TutorialGuestExitActions.clearBusyForExplicitExit();
      TutorialGuestExitActions.dismissExitDialogIfOpen();
    }
    if (_needsTutorialGuestExitGuard) {
      await TutorialGuestExitActions.promptExitIfNeeded(
        context,
        tutorialFlow: widget.isTutorialFlow,
        forcePrompt: forcePrompt,
        onLogin: () async {
          final attemptId = ++_loginAttemptId;
          if (mounted) setState(() => _isOpeningDetail = true);
          try {
            await _loginWithGoogleAndClaim();
          } finally {
            if (_isLoginAttemptCurrent(attemptId)) {
              _resetGuestLoginUiState();
            }
          }
        },
        onExitWithoutLogin: _exitWithoutLoginFromResultPage,
      );
      return;
    }
    if (_isGuestLockedFlow) {
      await _popGuestResultWithoutLogin();
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _pushDetailPage() async {
    if (_pillarId == null) {
      await _loadPillarIdAndPlayMusic();
    }
    if (!mounted) return;
    final pillarForDetail = _pillarId ??
        (await PersonalityTypeDetailService.getDetail(_effective.personalityType))?.pillarId;
    if (!mounted) return;
    debugPrint('[PersonalityDiagnosis] push detail type=${_effective.personalityType}');
    await Navigator.push(
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

  Future<void> _openDetailPage() async {
    if (_isOpeningDetail) return;
    final attemptId = ++_loginAttemptId;
    setState(() => _isOpeningDetail = true);
    try {
      if (_showGuestLock) {
        final unlocked = await _loginWithGoogleAndClaim(showSuccessSnack: false);
        if (!_isLoginAttemptCurrent(attemptId)) return;
        if (!unlocked) return;
      }
      if (!_isLoginAttemptCurrent(attemptId)) return;
      await _pushDetailPage();
    } finally {
      if (_isLoginAttemptCurrent(attemptId)) {
        setState(() => _isOpeningDetail = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = _personalityTypeNameForDetail();

    return TutorialGuestExitScope(
      enabled: _isGuestLockedFlow,
      tutorialFlow: widget.isTutorialFlow,
      onLogin: () async {
        final attemptId = ++_loginAttemptId;
        if (mounted) setState(() => _isOpeningDetail = true);
        try {
          await _loginWithGoogleAndClaim();
        } finally {
          if (_isLoginAttemptCurrent(attemptId)) {
            _resetGuestLoginUiState();
          }
        }
      },
      onExitWithoutLogin: _exitWithoutLoginFromResultPage,
      onBackRequested: () => unawaited(_handleGuestBackOrExit(forcePrompt: true)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('性格診断結果'),
          automaticallyImplyLeading: false,
          leading: _isGuestLockedFlow
              ? Semantics(
                  identifier: 'maestro_guest_result_back',
                  label: '戻る',
                  button: true,
                  child: IconButton(
                    key: const Key('guest-result-back-button'),
                    icon: const Icon(Icons.arrow_back),
                    tooltip: '戻る',
                    onPressed: () => unawaited(_handleGuestBackOrExit(forcePrompt: true)),
                  ),
                )
              : Semantics(
                  identifier: 'maestro_guest_result_back',
                  label: '戻る',
                  button: true,
                  child: BackButton(
                    key: const Key('guest-result-back-button'),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
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
                              '詳細な性格診断を開示するには、Google でログインが必要です。\n\n認証後、診断結果は保存され、次回も同じ内容を確認できます。',
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
                          key: const Key('guest-login-detail-button'),
                          onPressed: _isOpeningDetail ? null : () => unawaited(_openDetailPage()),
                          icon: _isOpeningDetail
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _showGuestLock ? Icons.login : Icons.auto_awesome,
                                  size: 24,
                                ),
                          label: Text(
                            _isOpeningDetail
                                ? '処理中…'
                                : (_showGuestLock ? 'ログインして詳細を見る' : '詳しく見る'),
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
