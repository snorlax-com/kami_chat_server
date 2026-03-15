/// 撮影OKゲート（正面・水平・距離・明るさ）
class CaptureGateConfig {
  final double maxYaw;
  final double maxPitch;
  final double maxRoll;
  final double centerTol;
  final double minFaceH;
  final double maxFaceH;
  final double minBrightness;

  const CaptureGateConfig({
    this.maxYaw = 8,
    this.maxPitch = 8,
    this.maxRoll = 5,
    this.centerTol = 0.10,
    this.minFaceH = 0.35,
    this.maxFaceH = 0.65,
    this.minBrightness = 0.20,
  });
}

class CaptureGateState {
  final bool okPose;
  final bool okCenter;
  final bool okSize;
  final bool okBrightness;
  final bool okAll;
  const CaptureGateState({
    required this.okPose,
    required this.okCenter,
    required this.okSize,
    required this.okBrightness,
    required this.okAll,
  });
}

class CaptureGate {
  static CaptureGateState evaluate({
    required CaptureGateConfig cfg,
    required double yaw,
    required double pitch,
    required double roll,
    required double faceCx,
    required double faceCy,
    required double faceH,
    required double brightness,
  }) {
    final okPose = yaw.abs() <= cfg.maxYaw && pitch.abs() <= cfg.maxPitch && roll.abs() <= cfg.maxRoll;
    final okCenter = (faceCx - 0.5).abs() <= cfg.centerTol && (faceCy - 0.5).abs() <= cfg.centerTol;
    final okSize = faceH >= cfg.minFaceH && faceH <= cfg.maxFaceH;
    final okBrightness = brightness >= cfg.minBrightness;
    final okAll = okPose && okCenter && okSize && okBrightness;
    return CaptureGateState(
      okPose: okPose,
      okCenter: okCenter,
      okSize: okSize,
      okBrightness: okBrightness,
      okAll: okAll,
    );
  }
}
