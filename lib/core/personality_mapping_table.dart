/// 34,992通りの判断フローから18タイプへの完全なマッピングテーブル
///
/// このマッピングテーブルは、すべての9層の組み合わせ（34,992通り）を
/// 直接18の性格タイプにマッピングします。
///
/// 組み合わせ数: 3 × 2 × 3^6 × 8 = 34,992通り
/// - 第1層: 3通り（小/中/大）
/// - 第2層: 2通り（直線/曲線）
/// - 第3-8層: 各3通り（小/中/大）
/// - 第9層: 8通り（8種類の顔型）

import 'dart:convert';
import 'package:flutter/services.dart';

class PersonalityMappingTable {
  static bool _isInitialized = false;
  static Map<String, int>? _mappingTable; // JSONから読み込んだマッピングテーブル
  static final Map<int, Map<String, String>> _typeInfo = {
    1: {
      'name': '協調的リーダー型',
      'description': '積極的で行動力があり、協調的で調和を大切にする。社交的で人との繋がりを大切にし、創造的で芸術的センスがある。バランス感覚に優れ、適応力がある。明るく前向きで、人を包み込む力がある。',
    },
    2: {
      'name': '情熱的革新者型',
      'description':
          '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、社交的で人との繋がりを大切にし、創造的で芸術的センスがある。完璧主義で洞察力があり、バランス感覚に優れ適応力がある。新しいことに挑戦する勇気がある。',
    },
    3: {
      'name': '柔軟な適応者型',
      'description':
          '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、社交的で人との繋がりを大切にし、内向的で慎重に行動する。創造的で芸術的センスがあり、バランス感覚に優れ適応力がある。状況に応じて柔軟に対応できる。',
    },
    4: {
      'name': '情熱的表現者型',
      'description':
          '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、感情豊かで共感力が高い。社交的で人との繋がりを大切にし、創造的で芸術的センスがある。完璧主義で洞察力がある。表現力が豊かで、感情を大切にする。',
    },
    5: {
      'name': '堅実な計画者型',
      'description': '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、社交的で人との繋がりを大切にし、創造的で芸術的センスがある。計画的で長期的な視点があり、着実に目標を達成する。',
    },
    6: {
      'name': '社交的楽天家型',
      'description': '積極的で行動力があり、協調的で調和を大切にする。社交的で人との繋がりを大切にし、創造的で芸術的センスがある。明るく前向きで、エネルギッシュ。楽観的で、周囲を明るくする力がある。',
    },
    7: {
      'name': 'バランス型実務家',
      'description':
          '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、社交的で人との繋がりを大切にし、内向的で慎重に行動する。創造的で芸術的センスがあり、完璧主義で洞察力がある。バランス感覚に優れ適応力がある。すべての要素をバランスよく持ち合わせている。',
    },
    8: {
      'name': '情熱的リーダー型',
      'description':
          '積極的で行動力があり、冷静で分析的。社交的で人との繋がりを大切にし、内向的で慎重に行動する。創造的で芸術的センスがあり、完璧主義で洞察力がある。バランス感覚に優れ適応力がある。目標達成への意欲が高く、リーダーシップがある。',
    },
    9: {
      'name': '積極的開拓者型',
      'description': '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、社交的で人との繋がりを大切にし、創造的で芸術的センスがある。計画的で長期的な視点があり、新しいことに挑戦する勇気がある。',
    },
    10: {
      'name': '複雑な個性型',
      'description': '多様な特徴が複雑に組み合わさった個性的なタイプ。単純な分類では捉えきれない独自の性格特性を持ち、状況に応じて柔軟に変化する。固定観念にとらわれず、独自の価値観と行動パターンを持つ。',
    },
    11: {
      'name': '情熱的表現者型',
      'description': '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、感情豊かで共感力が高い。社交的で人との繋がりを大切にし、創造的で芸術的センスがある。表現力が豊かで、感情を大切にする。',
    },
    12: {
      'name': '冷静な観察者型',
      'description': '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、内向的で慎重に行動する。創造的で芸術的センスがあり、完璧主義で洞察力がある。観察力に優れ、細部に注意を払う。',
    },
    13: {
      'name': '寛大な支援者型',
      'description': '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、感情豊かで共感力が高い。社交的で人との繋がりを大切にし、創造的で芸術的センスがある。寛大で、他者を支援する力がある。',
    },
    14: {
      'name': '積極的開拓者型',
      'description': '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、社交的で人との繋がりを大切にし、創造的で芸術的センスがある。新しいことに挑戦する勇気があり、開拓精神がある。',
    },
    15: {
      'name': '内向的芸術家型',
      'description': '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、内向的で慎重に行動する。創造的で芸術的センスがあり、完璧主義で洞察力がある。内面的な世界を大切にし、芸術的な表現力がある。',
    },
    16: {
      'name': 'バランス型実務家',
      'description':
          '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、社交的で人との繋がりを大切にし、内向的で慎重に行動する。創造的で芸術的センスがあり、完璧主義で洞察力がある。バランス感覚に優れ適応力がある。実務的な能力に優れている。',
    },
    17: {
      'name': '情熱的革新者型',
      'description':
          '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、社交的で人との繋がりを大切にし、創造的で芸術的センスがある。完璧主義で洞察力があり、バランス感覚に優れ適応力がある。革新的なアイデアを持ち、情熱的に取り組む。',
    },
    18: {
      'name': '冷静な完璧主義者型',
      'description':
          '積極的で行動力があり、協調的で調和を大切にする。冷静で分析的で、社交的で人との繋がりを大切にし、内向的で慎重に行動する。創造的で芸術的センスがあり、完璧主義で洞察力がある。完璧を追求し、冷静に分析する力がある。',
    },
  };

  /// マッピングテーブルを初期化
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // JSONファイルからマッピングテーブルを読み込む
      final jsonString = await rootBundle.loadString('assets/personality_type_mapping.json');
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      _mappingTable = {};
      jsonData.forEach((key, value) {
        if (value is int && value >= 1 && value <= 18) {
          _mappingTable![key] = value;
        }
      });

      _isInitialized = true;
      print('[PersonalityMappingTable] ✅ マッピングテーブルを初期化しました (${_mappingTable!.length}件)');
    } catch (e) {
      print('[PersonalityMappingTable] ⚠️ JSONファイルの読み込みに失敗: $e');
      print('[PersonalityMappingTable] フォールバック: ロジックベースの分類を使用します');
      _isInitialized = true; // フォールバックでも初期化済みとする
    }
  }

  /// 9層の組み合わせから性格タイプを取得
  static int getPersonalityType(
    String layer1,
    String layer2,
    String layer3,
    String layer4,
    String layer5,
    String layer6,
    String layer7,
    String layer8,
    String layer9,
  ) {
    // 層の値を数値化
    // 第1層、第3-8層: 大=2, 中=1, 小=0
    // 第2層: 曲線=1, 直線=0
    final l1 = _layerValueToInt(layer1, layerNum: 1);
    final l2 = _layerValueToInt(layer2, layerNum: 2);
    final l3 = _layerValueToInt(layer3, layerNum: 3);
    final l4 = _layerValueToInt(layer4, layerNum: 4);
    final l5 = _layerValueToInt(layer5, layerNum: 5);
    final l6 = _layerValueToInt(layer6, layerNum: 6);
    final l7 = _layerValueToInt(layer7, layerNum: 7);
    final l8 = _layerValueToInt(layer8, layerNum: 8);
    final l9 = _faceTypeToInt(layer9);

    // 組み合わせキーを生成（例: "1,1,1,1,2,1,1,1,4"）
    final key = '$l1,$l2,$l3,$l4,$l5,$l6,$l7,$l8,$l9';

    // JSONマッピングテーブルから取得を試みる
    if (_mappingTable != null && _mappingTable!.containsKey(key)) {
      final type = _mappingTable![key]!;
      print('[PersonalityMappingTable] パターン "$key" → タイプ$type (JSONマッピング)');
      return type;
    }

    // フォールバック: ロジックベースの分類
    final type = _classifyByLogic(l1, l2, l3, l4, l5, l6, l7, l8, l9, layer9);
    print('[PersonalityMappingTable] パターン "$key" → タイプ$type (ロジックベース)');
    return type;
  }

  /// ロジックベースの分類（batch_personality_diagnosis.dartのロジックを参考）
  static int _classifyByLogic(
    int l1,
    int l2,
    int l3,
    int l4,
    int l5,
    int l6,
    int l7,
    int l8,
    int l9,
    String layer9,
  ) {
    // 積極性スコア（高=2, 中=1, 低=0）
    final aggressiveness = (l1 == 2 ? 2 : (l1 == 1 ? 1 : 0)) + (l3 == 2 ? 1 : 0) + (l8 == 2 ? 1 : 0);

    // 協調性スコア（高=2, 中=1, 低=0）
    // 第2層: 曲線=1（柔軟な思考、多角的な視点、協調的）→ +2, 直線=0（我が強く頑固、融通性に欠ける）→ +0
    final cooperativeness = (l1 == 0 ? 1 : 0) +
        (l2 == 1 ? 2 : 0) + // 曲線=1なら+2、直線=0なら+0
        (l4 == 2 ? 1 : 0) +
        (l5 == 2 ? 1 : 0) +
        (l7 == 2 ? 1 : 0);

    // 思考スタイル（感情的=2, バランス=1, 理性的=0）
    final thinkingStyle =
        (l6 == 0 ? 2 : (l6 == 2 ? 0 : 1)) + (l7 == 2 ? 1 : (l7 == 0 ? 0 : 0)) + (l8 == 2 ? 1 : (l8 == 0 ? 0 : 0));

    // 社交性スコア（高=2, 中=1, 低=0）
    final sociality = (l5 == 2 ? 1 : 0) + (l7 == 2 ? 1 : 0) + (l8 == 2 ? 1 : 0) + (_isSocialFaceType(layer9) ? 1 : 0);

    // 行動パターン（行動的=2, バランス=1, 慎重=0）
    final actionPattern = (l1 == 2 ? 2 : (l1 == 0 ? 0 : 1)) + (l3 == 2 ? 1 : 0) + (l4 == 0 ? 1 : 0) + (l8 == 2 ? 1 : 0);

    // 18タイプの分類ロジック（条件を階層的に整理し、重複を排除）
    // より具体的な条件から順にチェックし、排他的にする

    // 1. 最高スコアの組み合わせ（aggressiveness >= 4 && cooperativeness >= 3 && sociality >= 3）
    if (aggressiveness >= 4 && cooperativeness >= 3 && sociality >= 3) {
      // 曲線（柔軟な思考、多角的な視点、知性的）の場合
      if (l2 == 1) {
        if (thinkingStyle >= 2 && actionPattern >= 3 && cooperativeness >= 3 && aggressiveness >= 4 && l1 == 2)
          return 17; // 情熱的革新者型（曲線）
        if (actionPattern >= 4 && thinkingStyle >= 2 && aggressiveness >= 4 && sociality >= 3) return 14; // 積極的開拓者型（曲線）
        if (cooperativeness >= 4 && sociality >= 3 && aggressiveness >= 4 && thinkingStyle >= 2)
          return 2; // 情熱的革新者型（曲線）
        if (aggressiveness >= 4 &&
            thinkingStyle >= 3 &&
            actionPattern >= 3 &&
            sociality >= 4 &&
            cooperativeness >= 4 &&
            l1 == 2 &&
            l3 == 2) return 8; // 情熱的リーダー型（曲線）
        final hash = (l1 * 3 + l2 * 5 + l3 * 7 + l4 * 11 + l5 * 13 + l6 * 17 + l7 * 19 + l8 * 23 + l9 * 29) % 6;
        final types = [1, 2, 6, 14, 16, 17]; // 曲線向けのタイプ
        return types[hash];
      }
      // 直線（ストレート、シンプル、我が強い）の場合
      else {
        if (actionPattern >= 4 && thinkingStyle < 2 && aggressiveness >= 4) return 1; // 協調的リーダー型（直線）
        if (actionPattern >= 3 && aggressiveness >= 4) return 6; // 社交的楽天家型（直線）
        final hash = (l1 * 3 + l2 * 5 + l3 * 7 + l4 * 11 + l5 * 13 + l6 * 17 + l7 * 19 + l8 * 23 + l9 * 29) % 4;
        final types = [1, 6, 8, 18]; // 直線向けのタイプ
        return types[hash];
      }
    }

    // 2. 高積極性・低協調性（aggressiveness >= 4 && cooperativeness < 2）
    if (aggressiveness >= 4 && cooperativeness < 2) {
      if (actionPattern >= 4 && thinkingStyle < 2) return 1; // 情熱的リーダー型
      if (actionPattern >= 3) return 6; // 実践的行動派型
      final hash = (l1 * 3 + l2 * 5) % 2;
      return hash == 0 ? 1 : 6;
    }

    // 3. 低積極性・高協調性（aggressiveness < 2 && cooperativeness >= 3）
    if (aggressiveness < 2 && cooperativeness >= 3) {
      // 曲線（柔軟な思考、多角的な視点）の場合
      if (l2 == 1) {
        if (thinkingStyle >= 3 && sociality >= 3 && cooperativeness >= 4 && aggressiveness == 0)
          return 4; // 情熱的表現者型（曲線）
        if (sociality >= 4 &&
            thinkingStyle >= 4 &&
            cooperativeness >= 4 &&
            aggressiveness == 0 &&
            l1 == 0 &&
            l3 == 1 &&
            l4 == 2 &&
            l5 == 2 &&
            l6 == 0 &&
            l7 == 2 &&
            l8 == 1) return 13; // 寛大な支援者型（曲線）
        if (cooperativeness >= 4 && thinkingStyle >= 3 && sociality >= 2 && aggressiveness == 0 && l1 == 0 && l3 == 0)
          return 15; // 内向的芸術家型（曲線）
      }
      // 直線（ストレート、シンプル）の場合
      else {
        if (thinkingStyle >= 2 && sociality >= 2 && cooperativeness >= 3 && aggressiveness == 0)
          return 12; // 冷静な観察者型（直線）
        if (cooperativeness >= 3 && sociality >= 1 && aggressiveness == 0) return 18; // 冷静な完璧主義者型（直線）
      }
      // cooperativeness >= 3 && sociality >= 3 の条件をここでチェック（aggressiveness < 2 の範囲内）
      if (cooperativeness >= 3 && sociality >= 3 && aggressiveness >= 1 && aggressiveness < 2) {
        final hash = (l1 * 2 + l2 * 3 + l3 * 5 + l4 * 7 + l5 * 11 + l6 * 13 + l7 * 17 + l8 * 19 + l9 * 23) % 18;
        final types = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]; // 全18タイプ（タイプ10を含む）
        return types[hash];
      }
      final hash = (l1 * 2 + l2 * 3 + l3 * 5 + l4 * 7 + l5 * 11 + l6 * 13 + l7 * 17 + l8 * 19 + l9 * 23) % 18;
      final types = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]; // 全18タイプ（タイプ10を含む）
      return types[hash];
    }

    // 4. 低積極性・低協調性（aggressiveness < 2 && cooperativeness < 2）
    if (aggressiveness < 2 && cooperativeness < 2) {
      if (thinkingStyle < 1 && sociality < 1 && actionPattern < 1) return 3; // 柔軟な適応者型
      if (thinkingStyle >= 2 && actionPattern < 1 && sociality < 1) return 7; // 内向的思考家型
      if (actionPattern < 1 && sociality < 1 && thinkingStyle < 1) return 12; // 冷静な観察者型
      final hash = (l1 * 3 + l2 * 5 + l3 * 7 + l4 * 11 + l5 * 13 + l6 * 17 + l7 * 19 + l8 * 23 + l9 * 29) % 18;
      final types = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]; // 全18タイプ（タイプ10を含む）
      return types[hash];
    }

    // 5. 中高積極性・中協調性・高思考スタイル（aggressiveness >= 3 && cooperativeness >= 2 && thinkingStyle >= 3）
    if (aggressiveness >= 3 && cooperativeness >= 2 && thinkingStyle >= 3) {
      if (sociality >= 2 && cooperativeness >= 3 && aggressiveness >= 3 && thinkingStyle >= 3 && actionPattern >= 2)
        return 11; // 情熱的表現者型
      final hash = (l1 * 3 + l2 * 5 + l3 * 7 + l4 * 11 + l5 * 13 + l6 * 17 + l7 * 19 + l8 * 23 + l9 * 29) % 18;
      final types = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]; // 全18タイプ（タイプ10を含む）
      return types[hash];
    }

    // 6. 中積極性・中協調性・低思考スタイル（aggressiveness >= 2 && cooperativeness >= 2 && thinkingStyle < 2）
    if (aggressiveness >= 2 && cooperativeness >= 2 && thinkingStyle < 2) {
      if (actionPattern >= 1 && sociality >= 1 && cooperativeness >= 2 && l1 == 1 && l2 == 1) return 9; // 堅実な計画者型
      final hash = (l1 * 3 + l2 * 5 + l3 * 7 + l4 * 11 + l5 * 13 + l6 * 17 + l7 * 19 + l8 * 23 + l9 * 29) % 10;
      final types = [1, 3, 5, 6, 7, 9, 11, 16, 17, 18]; // より多様なタイプに分散
      return types[hash];
    }

    // 7. 中積極性・中協調性・中思考スタイル・低行動パターン（aggressiveness >= 2 && cooperativeness >= 2 && thinkingStyle >= 2 && actionPattern < 2）
    if (aggressiveness >= 2 && cooperativeness >= 2 && thinkingStyle >= 2 && actionPattern < 2) {
      if (sociality >= 1 && cooperativeness >= 2 && thinkingStyle >= 2 && l1 == 1 && l2 == 1 && l3 == 1)
        return 18; // 冷静な完璧主義者型
      final hash = (l1 * 3 + l2 * 5 + l3 * 7 + l4 * 11 + l5 * 13 + l6 * 17 + l7 * 19 + l8 * 23 + l9 * 29) % 8;
      final types = [3, 7, 9, 12, 16, 17, 18]; // より多様なタイプに分散
      return types[hash];
    }

    // 8. 中協調性・中思考スタイル（cooperativeness >= 2 && thinkingStyle >= 2 && 上記の条件に該当しない）
    if (cooperativeness >= 2 && thinkingStyle >= 2) {
      // 曲線（柔軟な思考、多角的な視点）の場合
      if (l2 == 1) {
        if (aggressiveness >= 2 && sociality >= 2 && cooperativeness >= 3 && thinkingStyle >= 3 && actionPattern >= 1)
          return 5; // 堅実な計画者型（曲線）
        if (aggressiveness == 0 && cooperativeness >= 3 && thinkingStyle >= 3 && sociality >= 2 && l1 == 0)
          return 15; // 内向的芸術家型（曲線）
      }
      // 直線（ストレート、シンプル）の場合
      else {
        if (aggressiveness >= 2 && sociality >= 1 && cooperativeness >= 2 && thinkingStyle >= 2 && actionPattern >= 1)
          return 9; // 積極的開拓者型（直線）
        if (aggressiveness == 0 && cooperativeness >= 2 && thinkingStyle >= 2 && sociality >= 1 && l1 == 0)
          return 12; // 冷静な観察者型（直線）
      }
      final hash = (l1 * 3 + l2 * 5 + l3 * 7 + l4 * 11 + l5 * 13 + l6 * 17 + l7 * 19 + l8 * 23 + l9 * 29) % 18;
      final types = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]; // 全18タイプ（タイプ10を含む）
      return types[hash];
    }

    // 9. 中積極性・低協調性・低思考スタイル（aggressiveness >= 2 && cooperativeness >= 1 && thinkingStyle >= 1 && 上記の条件に該当しない）
    if (aggressiveness >= 2 && cooperativeness >= 1 && thinkingStyle >= 1) {
      final hash = (l1 * 3 + l2 * 5 + l3 * 7 + l4 * 11 + l5 * 13 + l6 * 17 + l7 * 19 + l8 * 23 + l9 * 29) % 16;
      final types = [1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 14, 15, 16, 17, 18]; // タイプ10, 13を除外
      return types[hash];
    }

    // 10. 低積極性・低協調性（aggressiveness >= 1 && cooperativeness >= 1 && 上記の条件に該当しない）
    if (aggressiveness >= 1 && cooperativeness >= 1) {
      final hash = (l1 * 2 + l2 * 3 + l3 * 5 + l4 * 7 + l5 * 11 + l6 * 13 + l7 * 17 + l8 * 19 + l9 * 23) % 18;
      final types = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]; // 全18タイプ（タイプ10を含む）
      return types[hash];
    }

    // 11. 最低条件（aggressiveness >= 1 || cooperativeness >= 1 && 上記の条件に該当しない）
    if (aggressiveness >= 1 || cooperativeness >= 1) {
      final hash = (l1 * 3 + l2 * 5 + l3 * 7 + l4 * 11 + l5 * 13 + l6 * 17 + l7 * 19 + l8 * 23 + l9 * 29) % 16;
      final types = [1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 14, 15, 16, 17, 18]; // タイプ10, 13を除外
      return types[hash];
    }

    // デフォルト: 組み合わせ番号を使って均等に分散
    // より多様なタイプが検出されるように、組み合わせのハッシュ値を使用
    // すべてのタイプ（タイプ10を含む）を含めて18種類から選択
    final hash = (l1 * 3 + l2 * 5 + l3 * 7 + l4 * 11 + l5 * 13 + l6 * 17 + l7 * 19 + l8 * 23 + l9 * 29) % 18;
    final types = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]; // 全18タイプ（タイプ10を含む）
    return types[hash];
  }

  /// 層の値を数値化
  /// 第1層、第3-8層: 大=2, 中=1, 小=0
  /// 第2層: 曲線=1, 直線=0
  static int _layerValueToInt(String value, {int layerNum = 0}) {
    // 第2層の特別処理
    if (layerNum == 2) {
      if (value.contains('曲線')) return 1;
      if (value.contains('直線')) return 0;
      return 0; // デフォルトは直線
    }
    // その他の層
    if (value.contains('大')) return 2;
    if (value.contains('中')) return 1;
    if (value.contains('小')) return 0;
    return 1; // デフォルト
  }

  /// 顔の型を数値化（0-7）
  static int _faceTypeToInt(String faceType) {
    final faceTypeMap = {
      '丸顔': 0,
      '卵顔': 1,
      '細長顔': 2,
      '逆三角形顔': 3,
      '四角顔': 4,
      '台座顔': 5,
      '三角形顔': 6,
      '長方形顔': 7,
    };
    return faceTypeMap[faceType] ?? 1;
  }

  /// 社交的な顔の型かどうか
  static bool _isSocialFaceType(String faceType) {
    return ['丸顔', '卵顔', '台座顔'].contains(faceType);
  }

  /// タイプ名を取得
  static String? getTypeName(int personalityType) {
    return _typeInfo[personalityType]?['name'];
  }

  /// タイプの説明を取得
  static String? getTypeDescription(int personalityType) {
    return _typeInfo[personalityType]?['description'];
  }
}

/// このマッピングテーブルは、すべての9層の組み合わせ（52,488通り）を
/// 直接18の性格タイプにマッピングします。
///
/// 分類方法:
/// - スコア計算を使わない
/// - 第9層（顔の型）を3つに分けない（8通りすべてを使用）
/// - クラスタリング結果に基づいて、52,488通りの組み合わせを18タイプにマッピング
/// - 性格の文言が似ているものをまとめて18タイプにする
/// - 均等に分ける必要はない
