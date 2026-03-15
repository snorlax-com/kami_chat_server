/// 連写フレーム（角度スコアで最良を選択）
class BurstFrame<T> {
  final T image;
  final double yawAbs;
  final double pitchAbs;
  final double rollAbs;
  BurstFrame(this.image, this.yawAbs, this.pitchAbs, this.rollAbs);

  double get score => yawAbs + pitchAbs + rollAbs;
}

/// Web用：0.8秒で3枚連写し、最も正面に近い1枚を採用
class BurstCapture<T> {
  final List<BurstFrame<T>> _frames = [];

  void add(T img, double yaw, double pitch, double roll) {
    _frames.add(BurstFrame(
      img,
      yaw.abs(),
      pitch.abs(),
      roll.abs(),
    ));
  }

  bool get hasEnough => _frames.length >= 3;

  BurstFrame<T>? pickBest() {
    if (_frames.isEmpty) return null;
    final sorted = List<BurstFrame<T>>.from(_frames)..sort((a, b) => a.score.compareTo(b.score));
    return sorted.first;
  }

  void clear() => _frames.clear();
}
