/// 18タイプの詳細データを構築するユーティリティ
///
/// このファイルは、ユーザーが提供した18タイプの詳細説明を
/// JSON形式に変換するためのヘルパー関数を含みます。
class PersonalityTypeDataBuilder {
  /// タイプIDから柱情報を取得してデータを構築
  static Map<String, dynamic> buildTypeData({
    required int typeId,
    required String typeName,
    required String pillarId,
    required Map<String, Map<String, String>> sections,
  }) {
    // pillar_infoから画像パスを取得
    try {
      // 動的インポートはできないので、直接パスを構築
      final characterImage = 'assets/characters/${pillarId.toLowerCase()}.png';
      final illustrationImage = 'assets/illustrations/${pillarId.toLowerCase()}.png';

      final sectionsData = <String, Map<String, String>>{};
      sections.forEach((key, value) {
        sectionsData[key] = {
          'title': value['title'] ?? '',
          'content': value['content'] ?? '',
        };
      });

      return {
        'type_name': typeName,
        'pillar_id': pillarId,
        'pillar_title': _getPillarTitle(pillarId),
        'character_image': characterImage,
        'illustration_image': illustrationImage,
        'sections': sectionsData,
      };
    } catch (e) {
      print('[PersonalityTypeDataBuilder] エラー: $e');
      return {};
    }
  }

  static String _getPillarTitle(String pillarId) {
    final titles = {
      'Shisaru': '星の神',
      'Ragias': '雷の神',
      'Shiran': '旅の神',
      'Yatael': '導きの神',
      'Amanoira': '宿命の神',
      'Tenkora': '狐の神',
      'Kanonis': '慈愛の神',
      'Yorusi': '太陽の使い',
      'Tenmira': '未来の神',
      'Amatera': '太陽の女神',
      'Mimika': '知恵の神',
      'Sylna': '森の神',
      'Noirune': '月の神',
      'Skura': '春の神',
      'Fatemis': '運命の神',
    };
    return titles[pillarId] ?? '';
  }
}
