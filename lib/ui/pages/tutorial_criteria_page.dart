import 'package:flutter/material.dart';

class TutorialCriteriaPage extends StatelessWidget {
  const TutorialCriteriaPage({super.key});

  @override
  Widget build(BuildContext context) {
    print('[TutorialCriteriaPage] build()が呼ばれました');
    return Scaffold(
      appBar: AppBar(
        title: const Text('判断基準'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple.shade50,
              Colors.blue.shade50,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                _buildSection(
                  title: '📊 判断基準の柱',
                  content: 'チュートリアル機能では、以下の4つの主要な柱と詳細な五官分析から神を判定します。',
                ),
                const SizedBox(height: 24),
                _buildPillar1(context),
                const SizedBox(height: 24),
                _buildPillar2(context),
                const SizedBox(height: 24),
                _buildPillar3(context),
                const SizedBox(height: 24),
                _buildPillar4(context),
                const SizedBox(height: 24),
                _buildGokan(context),
                const SizedBox(height: 24),
                _buildFinalFlow(context),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required String content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildPillar1(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '柱1: 三停（さんてい）',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '顔を縦に3分割した比率から判定します。',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildSubSection('判定方法', [
              '上停: 額の上端 〜 眉の位置',
              '中停: 眉の位置 〜 鼻の基部（鼻下）',
              '下停: 鼻の基部 〜 顎先',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('判定基準', [
              '上停が最も長い → 上停',
              '中停が最も長い → 中停',
              '下停が最も長い → 下停',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildPillar2(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '柱2: 陰陽（いんよう）',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '顔の特徴から「陽」か「陰」かを判定します。',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildSubSection('判定に使用する特徴量', [
              '明るさ（30%）: 画像の明るさ > 0.65 → 陽 +0.3',
              '目のバランス（15%）: 左右の目の対称性 > 0.65 → 陽 +0.15',
              '眉の角度（15%）: 眉の傾き > 0.2 → 陽 +0.15',
              '口の幅（20%）: 口角の幅 > 0.65 → 陽 +0.20',
              '鼻の形状（10%）: 鼻の幅/高さ比 > 0.6 → 陽 +0.10',
              '頬の突出（10%）: 頬の張り出し > 0.6 → 陽 +0.10',
              '額の幅（5%）: 額の横幅 > 0.6 → 陽 +0.05',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('最終判定', [
              '合計スコア > 0.55 → 陽',
              '合計スコア < -0.45 → 陰',
              'それ以外 → スコアの正負で判定',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildPillar3(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '柱3: 顔形（かおがた）',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '顔の輪郭の形状から判定します。',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildSubSection('判定基準', [
              '丸: 顎の曲率 > 0.5 かつ アスペクト比 > 0.75',
              '角: 顎の曲率 < 0.25 かつ アスペクト比 < 0.65',
              '卵: 上記以外（中間）',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('計算方法', [
              '顎の曲率: 顔の輪郭ポイントから複数セグメントで曲率を計算',
              'アスペクト比: 顔の幅 / 顔の高さ',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildPillar4(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '柱4: 顔の型（人相学）',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '8種類の顔の型から判定します（三停よりも荷重が大きい）。',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildFaceTypeCard('丸顔', [
              '特徴: 肉付きが良く、全体的に丸い',
              '判定: アスペクト比が0.75に近い（20%）',
              '判定: 顎が丸い（30%）',
              '判定: 頬が張っている（20%）',
              '判定: 目が大きい（15%）',
              '判定: 耳たぶが大きい（15%）',
              '性格: 社交性、楽天的、情緒的',
            ]),
            const SizedBox(height: 12),
            _buildFaceTypeCard('細長顔', [
              '特徴: 縦に細長い、切れ長の目、長い鼻',
              '判定: アスペクト比 < 0.7（30%）',
              '判定: 切れ長の目（20%）',
              '判定: 長い鼻（20%）',
              '判定: 長い耳（15%）',
              '判定: 額が狭い（15%）',
              '性格: 着実、礼儀正しい、洞察力',
            ]),
            const SizedBox(height: 12),
            _buildFaceTypeCard('長方形顔', [
              '特徴: 縦長で、切れ長の目、立派な鼻',
              '判定: アスペクト比 0.65-0.75（25%）',
              '判定: 切れ長の目（20%）',
              '判定: 立派な鼻（20%）',
              '判定: 大きな口（15%）',
              '判定: 豊かな耳たぶ（20%）',
              '性格: 聡明、実行力、指導力、温かさ',
            ]),
            const SizedBox(height: 12),
            _buildFaceTypeCard('台座顔', [
              '特徴: 四角い台座のような形、肉付きが良い',
              '判定: アスペクト比 0.75-0.85（20%）',
              '判定: 角張っている（20%）',
              '判定: 額が広い（15%）',
              '判定: 肉付きが良い（15%）',
              '判定: 大きな目（15%）',
              '判定: 豊かな耳たぶ（15%）',
              '性格: 積極的、社交性、処理能力、指導力',
            ]),
            const SizedBox(height: 12),
            _buildFaceTypeCard('卵顔', [
              '特徴: 卵型、鼻筋が通っている、頬骨が張っている',
              '判定: アスペクト比 0.65-0.75（25%）',
              '判定: 丸みがある（20%）',
              '判定: 高い鼻（15%）',
              '判定: 頬骨が張っている（15%）',
              '判定: 大きな目（15%）',
              '判定: 小さな耳たぶ（10%）',
              '性格: 頭脳明晰、努力家、忍耐力',
            ]),
            const SizedBox(height: 12),
            _buildFaceTypeCard('四角顔', [
              '特徴: 角張っている、骨張っている',
              '判定: アスペクト比 > 0.75（25%）',
              '判定: 角張っている（30%）',
              '判定: 肉が少ない（20%）',
              '判定: 太い鼻（15%）',
              '判定: 目がくぼみ気味（10%）',
              '性格: 冷静、処理能力、頑固、意志力',
            ]),
            const SizedBox(height: 12),
            _buildFaceTypeCard('逆三角形顔', [
              '特徴: 額が広く、顎が細い',
              '判定: 額/顎比 > 1.2（30%）',
              '判定: 額が広い（20%）',
              '判定: 顎が細い（20%）',
              '判定: 大きな目（15%）',
              '判定: 切れ長（15%）',
              '性格: 真面目、冷静、緻密、地位志向',
            ]),
            const SizedBox(height: 12),
            _buildFaceTypeCard('三角形顔', [
              '特徴: 額が狭く、顎が広い（下ぶくれ）',
              '判定: 額/顎比 < 0.8（30%）',
              '判定: 額が狭い（20%）',
              '判定: 顎が広い（20%）',
              '判定: 丸みがある（15%）',
              '判定: 丸く太い鼻（15%）',
              '性格: 明るく円満、意志が強い、実行力、義理人情',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildFaceTypeCard(String title, List<String> items) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.deepPurple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Text(
                  '• $item',
                  style: const TextStyle(fontSize: 14),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildGokan(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '詳細分析: 五官の特徴',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '三停・陰陽・顔形・顔の型の基本判定に加えて、五官の詳細な特徴も補正として使用されます。',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            _buildSubSection('1. 目のバランス', [
              '計算: 左右の目のY座標の差から対称性を計算',
              '補正: eyeBalance > 0.75 → Amatera, Yatael, Osiria に +0.06',
              '補正: eyeBalance < 0.35 → Noirune, Mimika, Sylna に +0.06',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('2. 口の幅', [
              '計算: 左右の口角の距離を顔の幅で正規化',
              '補正: mouthWidth > 0.7 → Skura, Kanonis, Sylna, Osiria に +0.04',
              '補正: mouthWidth < 0.3 → Delphos, Amanoira, Fatemis に +0.04',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('3. 眉の角度', [
              '計算: 左右の眉のY座標の差から角度を推定',
              '補正: browAngle > 0.4 → Ragias, Fatemis, Delphos, Amatera に +0.04',
              '補正: browAngle < -0.3 → Kanonis, Sylna, Noirune に +0.04',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('4. 鼻の形状', [
              '計算: 鼻の幅/高さ比を計算',
              '補正: noseShape > 0.7 → Verdatsu, Ragias, Fatemis に +0.03',
              '補正: noseShape < 0.3 → Skura, Noirune, Shiran に +0.03',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('5. 頬の突出', [
              '計算: 左右の頬の最も外側のポイントまでの距離を計算',
              '補正: cheekProminence > 0.7 → Skura, Sylna, Kanonis に +0.02',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('6. 額の幅', [
              '計算: 額の領域のポイントから幅を計算',
              '補正: 陰陽判定の一部として使用（重み5%）',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildFinalFlow(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '最終判定フロー',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 12),
            _buildSubSection('1. 基本候補の抽出', [
              '顔の型（信頼度 > 50%）→ 優先候補（スコア 1.2）',
              '三停 × 陰陽の組み合わせ → 基本候補（スコア 1.0）',
              '代替候補 → 補助候補（スコア 0.8）',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('2. 補正の適用', [
              '顔形補正: 顔形に応じたボーナス（最大+0.05）',
              '顔の型補正: 顔の型に応じたボーナス（最大+0.15）',
              '五官特徴補正: 各五官の特徴に応じたボーナス（最大+0.06）',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('3. 最終選択', [
              'スコアが最も高い神を選択',
              'スコア差が0.15以内の場合はランダム選択（多様性確保）',
            ]),
            const SizedBox(height: 12),
            _buildSubSection('神の候補マッピング（三停 × 陰陽）', [
              '上停 × 陽 → Amatera, Yatael, Skura',
              '上停 × 陰 → Delphos, Amanoira, Noirune',
              '中停 × 陽 → Ragias, Verdatsu, Osiria',
              '中停 × 陰 → Fatemis, Kanonis, Sylna',
              '下停 × 陽 → Tenkora, Shisaru, Yorusi',
              '下停 × 陰 → Mimika, Tenmira, Shiran',
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSubSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Text(
                '• $item',
                style: const TextStyle(fontSize: 14),
              ),
            )),
      ],
    );
  }
}
