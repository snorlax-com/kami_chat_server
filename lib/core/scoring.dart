import 'dart:math' as math;
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/core/face_analyzer.dart';

class Scoring {
  // しきい値（調整可）
  static const exprThr = 0.55; // 笑顔/目の開き
  static const glossThr = 0.50; // 潤
  static const shapeThr = 0.55; // 直線
  static const claimThr = 0.55; // 主張

  static Map<String, int> discretize(FaceFeatures f) {
    final expr = ((f.smile * 0.6 + f.eyeOpen * 0.4) >= exprThr) ? 1 : 0;
    final skin = (f.gloss >= glossThr) ? 1 : 0;
    final shape = (f.straightness >= shapeThr) ? 1 : 0;
    final claim = (f.claim >= claimThr) ? 1 : 0;
    return {'expr': expr, 'skin': skin, 'shape': shape, 'claim': claim};
  }

  static Deity nearestDeity(FaceFeatures f) {
    final d = discretize(f);
    Deity? best;
    int bestScore = -1;
    for (final god in deities) {
      final score = (god.expr == d['expr']! ? 1 : 0) +
          (god.skin == d['skin']! ? 1 : 0) +
          (god.shape == d['shape']! ? 1 : 0) +
          (god.claim == d['claim']! ? 1 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = god;
      }
    }
    return best ?? deities.first;
  }

  // ハイブリッド判定（肌の変化影響を考慮）
  static Deity nearestDeityHybrid(FaceFeatures f, {double skinDeltaPenalty = 0.0}) {
    // 皮膚悪化(delta>0)は潤い判定を下げる
    final adjSkin = (f.gloss * (1.0 - (0.5 * skinDeltaPenalty).clamp(0.0, 0.7))).clamp(0.0, 1.0);
    final dExpr = ((f.smile * 0.6 + f.eyeOpen * 0.4) >= exprThr) ? 1 : 0;
    final dSkin = (adjSkin >= glossThr) ? 1 : 0;
    final dShape = (f.straightness >= shapeThr) ? 1 : 0;
    final dClaim = (f.claim >= claimThr) ? 1 : 0;

    Deity? best;
    int bestScore = -1;
    for (final god in deities) {
      final score = (god.expr == dExpr ? 1 : 0) +
          (god.skin == dSkin ? 1 : 0) +
          (god.shape == dShape ? 1 : 0) +
          (god.claim == dClaim ? 1 : 0);
      if (score > bestScore) {
        bestScore = score;
        best = god;
      }
    }
    return best ?? deities.first;
  }

  // 連続スコアでの最近傍（L1）判定。離散化のタイブレ偏りを回避
  static Deity nearestDeityContinuous(FaceFeatures f, {double skinDeltaPenalty = 0.0}) {
    final expr = (f.smile * 0.6 + f.eyeOpen * 0.4).clamp(0.0, 1.0);
    // 肌悪化ペナルティで潤を弱める
    final skin = (f.gloss * (1.0 - (0.5 * skinDeltaPenalty).clamp(0.0, 0.7))).clamp(0.0, 1.0);
    final shape = f.straightness.clamp(0.0, 1.0);
    final claim = f.claim.clamp(0.0, 1.0);

    Deity? best;
    double bestDist = 1e9;
    for (final god in deities) {
      // deity軸は0/1。L1距離で最近傍
      final d =
          (expr - god.expr).abs() + (skin - god.skin).abs() + (shape - god.shape).abs() + (claim - god.claim).abs();
      if (d < bestDist) {
        bestDist = d;
        best = god;
      }
    }
    return best ?? deities.first;
  }

  // 重み付きスコア（L1ではなく類似度）で偏りを軽減
  // 例: expr 0.30, skin 0.35, shape 0.20, claim 0.15
  static Deity nearestDeityWeighted(FaceFeatures f, {double skinDeltaPenalty = 0.0}) {
    final expr = (f.smile * 0.6 + f.eyeOpen * 0.4).clamp(0.0, 1.0);
    final skin = (f.gloss * (1.0 - (0.5 * skinDeltaPenalty).clamp(0.0, 0.7))).clamp(0.0, 1.0);
    final shape = f.straightness.clamp(0.0, 1.0);
    final claim = f.claim.clamp(0.0, 1.0);

    const wExpr = 0.30, wSkin = 0.35, wShape = 0.20, wClaim = 0.15;
    final scores = <Deity, double>{};

    for (final god in deities) {
      double s = wExpr * (1.0 - (expr - god.expr).abs()) +
          wSkin * (1.0 - (skin - god.skin).abs()) +
          wShape * (1.0 - (shape - god.shape).abs()) +
          wClaim * (1.0 - (claim - god.claim).abs());

      // Amateraに対するペナルティ（全軸1なので選ばれやすすぎるため）
      if (god.id == 'amatera') {
        s -= 0.08; // Amateraのスコアを下げる
      }

      // Yorusiも全軸1なので同様にペナルティ
      if (god.id == 'yorusi') {
        s -= 0.05;
      }

      scores[god] = s;
    }

    // スコアでソート
    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topScore = sorted.first.value;

    // スコアが近い候補（0.1以内）を抽出
    final closeCandidates = sorted.where((e) => (topScore - e.value).abs() < 0.12).toList();

    if (closeCandidates.length > 1) {
      // スコアが近い場合はランダム選択で多様性を確保
      final r = math.Random(DateTime.now().millisecondsSinceEpoch + expr.hashCode + skin.hashCode);
      return closeCandidates[r.nextInt(closeCandidates.length)].key;
    }

    return sorted.first.key;
  }
}
