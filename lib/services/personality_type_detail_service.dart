import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:kami_face_oracle/models/personality_type_detail.dart';

/// 性格タイプの詳細情報を読み込むサービス
class PersonalityTypeDetailService {
  static PersonalityTypeDetail? _cachedDetail;
  static int? _cachedTypeId;

  /// 性格タイプの詳細情報を取得
  static Future<PersonalityTypeDetail?> getDetail(int typeId) async {
    // キャッシュをチェック
    if (_cachedDetail != null && _cachedTypeId == typeId) {
      return _cachedDetail;
    }

    try {
      // JSONファイルを読み込む
      final jsonString = await rootBundle.loadString(
        'assets/data/personality_type_details.json',
      );
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      // タイプIDに対応するデータを取得
      final typeKey = typeId.toString();
      if (!jsonData.containsKey(typeKey)) {
        print('[PersonalityTypeDetailService] タイプ$typeIdのデータが見つかりません');
        return null;
      }

      final typeData = jsonData[typeKey] as Map<String, dynamic>;

      // 画像パスが設定されていない場合は、pillar_idから推測
      final characterImage = typeData['character_image'] as String?;
      if (!typeData.containsKey('character_image') || (characterImage == null || characterImage.isEmpty)) {
        final pillarId = typeData['pillar_id'] as String? ?? '';
        if (pillarId.isNotEmpty) {
          typeData['character_image'] = 'assets/characters/${pillarId.toLowerCase()}.png';
          typeData['illustration_image'] = 'assets/illustrations/${pillarId.toLowerCase()}.png';
        }
      }

      // モデルに変換
      final detail = PersonalityTypeDetail.fromJson(typeId, typeData);

      // デバッグログ: セクションの内容を確認
      print('[PersonalityTypeDetailService] 詳細データ読み込み成功:');
      print('  - typeId: $typeId');
      print('  - typeName: ${detail.typeName}');
      print('  - pillarId: ${detail.pillarId}');
      print('  - characterImage: ${detail.characterImage}');
      print('  - illustrationImage: ${detail.illustrationImage}');
      print('  - sections数: ${detail.sections.length}');
      print('  - orderedSections数: ${detail.orderedSections.length}');
      for (final entry in detail.orderedSections) {
        final contentLength = entry.value.content.length;
        final contentPreview =
            entry.value.content.length > 50 ? '${entry.value.content.substring(0, 50)}...' : entry.value.content;
        print('    - ${entry.key}: title="${entry.value.title}", content.length=$contentLength');
        if (entry.value.content.isEmpty) {
          print('      ⚠️ 警告: セクション${entry.key}のcontentが空です');
        } else {
          print('      content preview: $contentPreview');
        }
      }

      // キャッシュに保存
      _cachedDetail = detail;
      _cachedTypeId = typeId;

      return detail;
    } catch (e) {
      print('[PersonalityTypeDetailService] エラー: $e');
      return null;
    }
  }

  /// キャッシュをクリア
  static void clearCache() {
    _cachedDetail = null;
    _cachedTypeId = null;
  }
}
