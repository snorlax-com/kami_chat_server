import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:kami_face_oracle/core/deities.dart';
import 'package:kami_face_oracle/core/storage.dart';
import 'package:kami_face_oracle/services/personality_type_detail_service.dart';

const String kPillarInteractionSeedKeyV1 = 'pillar_interaction_seed_v1';
const String kPillarInteractionSeedKeyV2 = 'pillar_interaction_seed_v2';

/// チュートリアル等から占い相談チャット先頭に表示する行（柱／ユーザー）
class PillarInteractionSeed {
  const PillarInteractionSeed({
    required this.from,
    required this.text,
  });

  final String from; // 'pillar' | 'user'
  final String text;

  bool get isUser => from == 'user';

  Map<String, dynamic> toJson() => {'from': from, 'text': text};

  static PillarInteractionSeed fromJson(Map<String, dynamic> m) {
    return PillarInteractionSeed(
      from: (m['from'] as String? ?? 'pillar').toLowerCase() == 'user' ? 'user' : 'pillar',
      text: m['text'] as String? ?? '',
    );
  }
}

class PillarInteractionSeedStore {
  PillarInteractionSeedStore._();

  /// チュートリアルフローから全文を上書き（質問の列挙など）
  static Future<void> setAll(List<PillarInteractionSeed> items) async {
    final sp = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await sp.remove(kPillarInteractionSeedKeyV1);
      return;
    }
    await sp.setString(
      kPillarInteractionSeedKeyV2,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
    await sp.remove(kPillarInteractionSeedKeyV1);
  }

  static Future<void> clear() => setAll([]);

  static String _sanitizeSeedText(String text) {
    var t = text;
    t = t.replaceAll(
      '初回の相談は下の欄に入力し、「通常相談」または「至急」で送信してください（相談券が必要です）。',
      '相談したい内容を下の欄に入力して送信してください。',
    );
    t = t.replaceAll('「通常相談」または「至急」で送信', '下の欄から送信');
    t = t.replaceAll('（相談券が必要です）', '');
    return t.trim();
  }

  static List<PillarInteractionSeed> _parseSeedJson(String raw) {
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PillarInteractionSeed.fromJson(e as Map<String, dynamic>))
          .map((e) => PillarInteractionSeed(from: e.from, text: _sanitizeSeedText(e.text)))
          .where((e) => e.text.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<PillarInteractionSeed>> _loadRaw() async {
    final sp = await SharedPreferences.getInstance();
    final v2 = sp.getString(kPillarInteractionSeedKeyV2);
    if (v2 != null && v2.isNotEmpty) {
      return _parseSeedJson(v2);
    }
    final v1 = sp.getString(kPillarInteractionSeedKeyV1);
    if (v1 == null || v1.isEmpty) return [];
    final parsed = _parseSeedJson(v1);
    if (parsed.isNotEmpty) {
      await setAll(parsed);
    }
    return parsed;
  }

  static String _truncate(String s, int max) {
    final t = s.trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max).trim()}…';
  }

  static Future<List<PillarInteractionSeed>> _defaultFromTutorial() async {
    final out = <PillarInteractionSeed>[];
    final deityId = await Storage.getTutorialDeity();
    if (deityId == null) {
      out.add(
        const PillarInteractionSeed(
          from: 'pillar',
          text: '占い相談へようこそ。ここではあなたの柱の声と、創始者（人間）経由の相談のやり取りが続きます。\n'
              '相談したい内容を下の欄に入力して送信してください。',
        ),
      );
      return out;
    }
    final detail = await PersonalityTypeDetailService.getDetailByPillarId(deityId);
    final deity = deities.firstWhere(
      (d) => d.id == deityId,
      orElse: () => deities.first,
    );
    final pillarName =
        (detail != null && detail.pillarTitle.trim().isNotEmpty) ? detail.pillarTitle : deity.role;
    out.add(
      PillarInteractionSeed(
        from: 'pillar',
        text: '【${deity.nameJa}】$pillarName\n\n'
            'チュートリアルで出会った柱からの案内です。',
      ),
    );
    if (detail != null) {
      final intro = detail.sections['intro']?.content;
      if (intro != null && intro.trim().isNotEmpty) {
        out.add(PillarInteractionSeed(
          from: 'pillar',
          text: _truncate(intro, 1200),
        ));
      }
    }
    out.add(
      const PillarInteractionSeed(
        from: 'pillar',
        text: '隠占として降臨した柱に占ってほしいことや、悩みを相談したいことがあれば、下の欄から送ってください。'
            '柱の性格とあなたの性格を踏まえ、創始者（人間）が柱を通じてお答えします。例：今年の運勢、今の問題の解決のヒント など',
      ),
    );
    return out;
  }

  /// 保存済みシードがあればそれ。なければチュートリアル柱・性格文からのデフォルト。
  static Future<List<PillarInteractionSeed>> loadForDisplay() async {
    final raw = await _loadRaw();
    if (raw.isNotEmpty) {
      return raw;
    }
    return _defaultFromTutorial();
  }
}
