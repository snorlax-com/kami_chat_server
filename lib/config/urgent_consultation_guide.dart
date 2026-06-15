/// 至急質問券・至急相談の案内文（ストア・占い相談で共通）。
class UrgentConsultationGuide {
  UrgentConsultationGuide._();

  static const String title = '至急相談について';

  static const String body = '''
営業時間：8:00〜22:00（年中無休）

至急相談は、営業時間内であれば原則2時間以内に返信いたします。

営業時間外（22:00〜翌8:00）に受け付けたご相談は、翌営業開始時刻（8:00）から2時間以内を目安に返信いたします。

※相談内容や混雑状況により、返信にお時間をいただく場合があります。
※緊急時は内容を確認後、優先的に対応いたします。''';

  static const String purchaseConfirmQuestion =
      'この注意書きをご確認のうえ、購入してよろしいですか？';

  /// 選ぶボタンに表示する短い案内。
  static const String selectButtonHint = '2時間以内';
}
