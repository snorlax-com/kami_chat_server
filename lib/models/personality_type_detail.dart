/// 性格タイプの詳細情報モデル
class PersonalityTypeDetail {
  final int typeId;
  final String typeName;
  final String pillarId;
  final String pillarTitle;
  final String characterImage;
  final String illustrationImage;
  final Map<String, PersonalitySection> sections;

  PersonalityTypeDetail({
    required this.typeId,
    required this.typeName,
    required this.pillarId,
    required this.pillarTitle,
    required this.characterImage,
    required this.illustrationImage,
    required this.sections,
  });

  factory PersonalityTypeDetail.fromJson(int typeId, Map<String, dynamic> json) {
    final sections = <String, PersonalitySection>{};
    if (json['sections'] != null) {
      (json['sections'] as Map<String, dynamic>).forEach((key, value) {
        sections[key] = PersonalitySection.fromJson(value);
      });
    }

    return PersonalityTypeDetail(
      typeId: typeId,
      typeName: json['type_name'] ?? 'タイプ$typeId',
      pillarId: json['pillar_id'] ?? '',
      pillarTitle: json['pillar_title'] ?? '',
      characterImage: json['character_image'] ?? '',
      illustrationImage: json['illustration_image'] ?? '',
      sections: sections,
    );
  }

  /// セクションの順序（表示順）
  static const List<String> sectionOrder = [
    'intro',
    'core',
    'impression',
    'thinking',
    'emotion',
    'relationship',
    'strength',
    'weakness',
    'stress',
    'growth',
    'career',
    'compatibility',
    'summary',
  ];

  /// 順序に従ったセクションリストを取得
  List<MapEntry<String, PersonalitySection>> get orderedSections {
    return sectionOrder.where((key) => sections.containsKey(key)).map((key) => MapEntry(key, sections[key]!)).toList();
  }
}

/// 性格タイプの各セクション
class PersonalitySection {
  final String title;
  final String content;

  PersonalitySection({
    required this.title,
    required this.content,
  });

  factory PersonalitySection.fromJson(Map<String, dynamic> json) {
    return PersonalitySection(
      title: json['title'] ?? '',
      content: json['content'] ?? '',
    );
  }
}
