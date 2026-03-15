/// 品質シグナル（暗さ・コントラスト・ブレ・曇り疑い）
/// Web では Canvas サンプリングなどで取得。既存の brightness があれば流用可。
class QualitySignals {
  final double brightness; // 0..1
  final double contrast; // 0..1 (rough)
  final double motion; // 0..1 (rough)
  final bool fogSuspected;

  QualitySignals({
    required this.brightness,
    required this.contrast,
    required this.motion,
    required this.fogSuspected,
  });

  /// 曇り疑い: コントラストが低く、かつ暗すぎない
  static bool inferFogSuspected(double brightness, double contrast) {
    return contrast < 0.2 && brightness > 0.2;
  }
}
