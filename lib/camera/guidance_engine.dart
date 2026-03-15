/// ガイダンス種別（優先順位で1つだけ表示）
enum GuidanceType {
  none,
  fog,
  tooDark,
  backlight,
  tooFar,
  tooClose,
  shaky,
  occluded,
  notFront,
  notLevel,
}

class GuidanceMessage {
  final GuidanceType type;
  final String main;
  final String? sub;
  const GuidanceMessage(this.type, this.main, [this.sub]);
}

/// 優先順位に基づきメッセージを1つだけ返す
class GuidanceEngine {
  static GuidanceMessage decide({
    required bool hasFace,
    required bool hasKeyParts,
    required bool okPose,
    required bool okCenter,
    required bool okSize,
    required bool okBrightness,
    required bool fogSuspected,
    required bool shaky,
    required bool occluded,
    required bool notLevel,
    required bool notFront,
  }) {
    // 1) 曇り/汚れ疑い（固定文言）
    if (!hasKeyParts && fogSuspected) {
      return const GuidanceMessage(
        GuidanceType.fog,
        '画面が曇っているかもしれません。カメラ（レンズ）を服で拭いてください。',
        '指紋や曇りがあると、目や口が認識できません。',
      );
    }

    // 2) 顔なし or 暗い
    if (!hasFace || !okBrightness) {
      return const GuidanceMessage(GuidanceType.tooDark, '暗いです。明るい場所へ移動してください。');
    }

    // 3) 距離
    if (!okSize) {
      return const GuidanceMessage(GuidanceType.tooFar, 'もう少し近づいてください（顔が小さすぎます）。');
    }
    if (!okCenter) {
      return const GuidanceMessage(GuidanceType.none, '顔を枠の中央に合わせてください。');
    }

    // 4) ブレ
    if (shaky) {
      return const GuidanceMessage(GuidanceType.shaky, 'スマホを両手で持って、1秒止まってください。');
    }

    // 5) 隠れ
    if (occluded) {
      return const GuidanceMessage(GuidanceType.occluded, '目と口が隠れています。髪をよけてください。');
    }

    // 6) 角度
    if (notLevel) {
      return const GuidanceMessage(GuidanceType.notLevel, 'スマホを水平にしてください。');
    }
    if (notFront || !okPose) {
      return const GuidanceMessage(GuidanceType.notFront, '正面を向いてください。');
    }

    return const GuidanceMessage(GuidanceType.none, '準備OKです。');
  }
}
