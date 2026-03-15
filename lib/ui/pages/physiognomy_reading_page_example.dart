// 使用例：PhysiognomyReadingPageの呼び出し方

import 'package:flutter/material.dart';
import 'package:kami_face_oracle/ui/pages/physiognomy_reading_page.dart';

/// 使用例：肌診断結果から占い結果を表示
class PhysiognomyReadingExample extends StatelessWidget {
  final int personalityType;
  final Map<String, double> skinScores;
  final String readingText;

  const PhysiognomyReadingExample({
    super.key,
    required this.personalityType,
    required this.skinScores,
    required this.readingText,
  });

  @override
  Widget build(BuildContext context) {
    return PhysiognomyReadingPage(
      personalityType: personalityType,
      skinScores: skinScores,
      readingText: readingText,
    );
  }
}

/// 使用例：ナビゲーション経由で表示
void navigateToPhysiognomyReading(
  BuildContext context, {
  required int personalityType,
  required Map<String, double> skinScores,
  required String readingText,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PhysiognomyReadingPage(
        personalityType: personalityType,
        skinScores: skinScores,
        readingText: readingText,
      ),
    ),
  );
}
