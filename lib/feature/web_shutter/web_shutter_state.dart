/// JS エンジンから返る状態（getShutterStateJson のパース結果）
class WebShutterState {
  final bool ok;
  final int stableCount;
  final int stableFramesRequired;
  final bool countingDown;
  final double countdownProgress;
  final String reason;
  final Map<String, dynamic> debug;

  WebShutterState({
    required this.ok,
    required this.stableCount,
    required this.stableFramesRequired,
    required this.countingDown,
    required this.countdownProgress,
    required this.reason,
    required this.debug,
  });

  factory WebShutterState.fromJson(Map<String, dynamic> json) {
    return WebShutterState(
      ok: json['ok'] as bool? ?? false,
      stableCount: json['stableCount'] as int? ?? 0,
      stableFramesRequired: json['stableFramesRequired'] as int? ?? 8,
      countingDown: json['countingDown'] as bool? ?? false,
      countdownProgress: (json['countdownProgress'] as num?)?.toDouble() ?? 0.0,
      reason: json['reason'] as String? ?? '',
      debug: json['debug'] as Map<String, dynamic>? ?? {},
    );
  }

  double get progress01 => stableFramesRequired > 0 ? (stableCount / stableFramesRequired).clamp(0.0, 1.0) : 0.0;
}
