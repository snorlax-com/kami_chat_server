import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/e2e.dart';
import 'package:kami_face_oracle/ui/pages/home_page.dart';
import 'package:kami_face_oracle/ui/pages/capture_page.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_camera_page.dart';
import 'package:kami_face_oracle/ui/pages/consultation_page.dart';
import 'package:kami_face_oracle/features/consent/widgets/age_gate_dialog.dart';
import 'package:kami_face_oracle/services/background_music_service.dart';

/// 統合テストで占い相談メール送信テスト時に true（--dart-define=INTEGRATION_TEST_CONSULTATION=true）
bool get _integrationTestConsultation =>
    bool.fromEnvironment('INTEGRATION_TEST_CONSULTATION', defaultValue: false);

/// MaterialApp とルートウィジェット（main の runner から参照）
class AuraFaceApp extends StatelessWidget {
  const AuraFaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 統合テスト: 占い相談画面を直接表示（メール送信テスト用）
    if (E2E.isEnabled && _integrationTestConsultation) {
      return MaterialApp(
        title: 'Face Oracle',
        theme: _mysticTheme,
        debugShowCheckedModeBanner: false,
        home: const ConsultationPage(),
      );
    }
    // E2E: ?e2e=1&route=camera でカメラ画面を直接表示（CanvasKit で DOM にテキストが出ないためテストを安定化）
    final useE2ECameraRoute =
        E2E.isEnabled && (Uri.base.queryParameters['route'] == 'camera' || Uri.base.queryParameters['camera'] == '1');
    return MaterialApp(
      title: 'Face Oracle',
      theme: _mysticTheme,
      debugShowCheckedModeBanner: false,
      home: useE2ECameraRoute
          ? const TutorialCameraPage(currentStep: 'neutral', forceE2ESkipCamera: true)
          : const RootGate(),
    );
  }
}

class AuraFaceAutoApp extends StatelessWidget {
  final String initialImagePath;

  const AuraFaceAutoApp({super.key, required this.initialImagePath});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Oracle (Auto)',
      theme: _mysticTheme,
      debugShowCheckedModeBanner: false,
      home: CapturePage(
        autoMode: true,
        initialImagePath: initialImagePath,
      ),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        BackgroundMusicService().pauseForBackground();
        break;
      case AppLifecycleState.resumed:
        BackgroundMusicService().resumeFromBackground();
        break;
      case AppLifecycleState.detached:
        BackgroundMusicService().stop();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return const AgeGateWrapper(child: HomePage());
  }
}

final ThemeData _mysticTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF8B5CF6),
    brightness: Brightness.dark,
    primary: const Color(0xFF8B5CF6),
    secondary: const Color(0xFF06B6D4),
    tertiary: const Color(0xFFF59E0B),
    surface: const Color(0xFF1A1F3A),
    onSurface: Colors.white,
    onPrimary: Colors.white,
  ),
  scaffoldBackgroundColor: const Color(0xFF0A0E1A),
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 20,
      letterSpacing: 1.2,
      shadows: [
        Shadow(color: const Color(0xFF8B5CF6).withOpacity(0.8), blurRadius: 10, offset: const Offset(0, 0)),
        Shadow(color: const Color(0xFF06B6D4).withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 0)),
      ],
    ),
    iconTheme: const IconThemeData(color: Colors.white, size: 28),
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF1A1F3A).withOpacity(0.8),
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shadowColor: const Color(0xFF8B5CF6).withOpacity(0.3),
    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: const Color(0xFF8B5CF6).withOpacity(0.3), width: 1.5),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF8B5CF6),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      shadowColor: const Color(0xFF8B5CF6).withOpacity(0.5),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFFC084FC),
      side: BorderSide(color: const Color(0xFFC084FC).withOpacity(0.6), width: 2),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF06B6D4), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16)),
  ),
  textTheme: const TextTheme(
    displayLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.5),
    displayMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 1.2),
    bodyLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(color: Colors.white70, fontWeight: FontWeight.w400),
  ),
);
