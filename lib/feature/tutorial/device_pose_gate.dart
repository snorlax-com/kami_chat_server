import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';

class DevicePoseGate {
  // --- tuning ---
  final double gyroStillThreshold; // rad/s
  final int gyroStableRequiredFrames;

  final double pitchThresholdDeg; // deg
  final double rollThresholdDeg; // deg

  DevicePoseGate({
    this.gyroStillThreshold = 0.08,
    this.gyroStableRequiredFrames = 12,
    this.pitchThresholdDeg = 6.0,
    this.rollThresholdDeg = 6.0,
  });

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accSub;

  // last values
  double gyroMag = 999;
  double pitchDeg = 999;
  double rollDeg = 999;

  int _gyroStableFrames = 0;

  bool get deviceIsStill => _gyroStableFrames >= gyroStableRequiredFrames;
  bool get deviceIsVertical => pitchDeg.abs() <= pitchThresholdDeg && rollDeg.abs() <= rollThresholdDeg;

  void start() {
    _gyroSub?.cancel();
    _accSub?.cancel();

    _gyroSub = gyroscopeEventStream().listen((e) {
      final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      gyroMag = mag;

      if (mag < gyroStillThreshold) {
        _gyroStableFrames++;
      } else {
        _gyroStableFrames = 0;
      }
    });

    _accSub = accelerometerEventStream().listen((e) {
      final ax = e.x, ay = e.y, az = e.z;

      // Android座標系でのpitch/roll計算（縦向き固定を考慮）
      // スマホを縦向きに持った時：
      // - X軸: 右方向が正
      // - Y軸: 上方向が正
      // - Z軸: 画面の手前方向が正
      //
      // 縦向きで垂直な状態では、重力は-Y方向（下方向）に向く
      // つまり、ayが負の大きな値になる
      //
      // 標準的な計算方法（角度を-90度～90度の範囲に正規化）:
      // pitch（前後の傾き）: X軸周りの回転
      // roll（左右の傾き）: Z軸周りの回転
      //
      // 重力の大きさを計算
      final g = math.sqrt(ax * ax + ay * ay + az * az);

      if (g > 0.1) {
        // 標準的な計算方法を使用（角度を-90度～90度の範囲に正規化）
        // pitch: 前後の傾き（X軸周りの回転）
        pitchDeg = math.atan2(ax, math.sqrt(ay * ay + az * az)) * 180 / math.pi;

        // roll: 左右の傾き（Z軸周りの回転）
        rollDeg = math.atan2(az, math.sqrt(ax * ax + ay * ay)) * 180 / math.pi;

        // 角度を-90度～90度の範囲に正規化（180度近くの値は異常）
        // 180度近くの値は、実際には-90度～90度の範囲に変換
        if (pitchDeg.abs() > 90) {
          pitchDeg = pitchDeg > 0 ? pitchDeg - 180 : pitchDeg + 180;
        }
        if (rollDeg.abs() > 90) {
          rollDeg = rollDeg > 0 ? rollDeg - 180 : rollDeg + 180;
        }
      }
    });
  }

  void stop() {
    _gyroSub?.cancel();
    _accSub?.cancel();
    _gyroSub = null;
    _accSub = null;
  }
}
