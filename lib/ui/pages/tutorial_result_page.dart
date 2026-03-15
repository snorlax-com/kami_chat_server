import 'package:flutter/material.dart';
import 'package:kami_face_oracle/core/tutorial_classifier.dart';
import 'package:kami_face_oracle/core/deity.dart';
import 'package:kami_face_oracle/core/router_tree_classifier.dart';
import 'package:kami_face_oracle/ui/pages/tutorial_comment_page.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class TutorialResultPage extends StatefulWidget {
  final TutorialDiagnosisResult diagnosisResult;
  final Deity deity; // 神の情報を追加
  final Map<String, dynamic>? deityMeta; // 性格診断データ
  final String? comment; // コメント

  const TutorialResultPage({
    super.key,
    required this.diagnosisResult,
    required this.deity,
    this.deityMeta,
    this.comment,
  });

  @override
  State<TutorialResultPage> createState() => _TutorialResultPageState();
}

class _TutorialResultPageState extends State<TutorialResultPage> {
  // 文字列または数値を安全にdoubleに変換するヘルパーメソッド
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed;
    }
    return null;
  }

  void _navigateToCommentPage() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TutorialCommentPage(
          deity: widget.deity,
          comment: widget.comment,
          deityMeta: widget.deityMeta,
          diagnosisResult: widget.diagnosisResult,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('判断基準'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false, // 戻るボタンを無効化
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
          child: Column(
            children: [
              // 選考した判断基準を表示
              Expanded(
                child: _buildSelectedCriteriaPage(),
              ),
              // 次へボタン
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: _navigateToCommentPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    '次へ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedCriteriaPage() {
    final detailedReason = widget.diagnosisResult.detailedReason;
    final features = detailedReason?['features'] as Map<String, dynamic>?;

    // 選考した判断基準を抽出（新しい樹形図ルーティング型フローに合わせて）
    final selectedCriteria = <String, List<String>>{};

    // ルーティング情報を構築（樹形図ルーティング型・正しい順番）
    final routeInfo = <String>[];

    // 第一分岐：眉の形状
    if (features?['brow'] != null) {
      final brow = features!['brow'] as Map<String, dynamic>;
      final browShape = _parseDouble(brow['shape']) ?? 0.5;

      if (browShape > 0.6) {
        routeInfo.add('曲線的');
      } else if (browShape < 0.2) {
        routeInfo.add('直線的');
      }
    }

    // 第二分岐：眉の角度
    if (features?['brow'] != null) {
      final brow = features!['brow'] as Map<String, dynamic>;
      final browAngle = _parseDouble(brow['angle']) ?? 0.0;

      if (browAngle > 0.2) {
        routeInfo.add('上昇タイプ');
      } else if (browAngle < -0.2) {
        routeInfo.add('下降タイプ');
      } else if (browAngle >= -0.15 && browAngle <= 0.15) {
        routeInfo.add('水平タイプ');
      }
    }

    // 第三分岐：眉間の幅
    if (features?['brow'] != null) {
      final brow = features!['brow'] as Map<String, dynamic>;
      final glabellaWidth = _parseDouble(brow['glabellaWidth']) ?? 0.5;

      if (glabellaWidth > 0.9) {
        routeInfo.add('眉間広');
      } else if (glabellaWidth < 0.2) {
        routeInfo.add('眉間狭');
      }
    }

    // 第四分岐：目の特徴
    if (features?['eye'] != null) {
      final eye = features!['eye'] as Map<String, dynamic>;
      final eyeShape = _parseDouble(eye['shape']) ?? 0.5;
      final eyeBalance = _parseDouble(eye['balance']) ?? 0.5;

      if (eyeShape > 0.95) {
        routeInfo.add('洞察・集中');
      } else if (eyeBalance > 0.85) {
        routeInfo.add('積極・開放');
      } else if (eyeBalance < 0.35) {
        routeInfo.add('内向・沈静');
      }
    }

    // 第五分岐：口の特徴
    if (features?['mouth'] != null) {
      final mouth = features!['mouth'] as Map<String, dynamic>;
      final mouthSize = _parseDouble(mouth['size']) ?? 0.5;

      if (mouthSize > 0.8) {
        routeInfo.add('外向表現型');
      } else if (mouthSize < 0.25) {
        routeInfo.add('内向沈静型');
      }
    }

    // 最終絞り込み：顔の型
    if (features?['faceType'] != null) {
      final faceType = features!['faceType'] as String?;
      if (faceType != null) {
        switch (faceType) {
          case '丸顔':
          case '台座顔':
          case '三角形顔':
            routeInfo.add('社交・包容');
            break;
          case '細長顔':
          case '逆三角形顔':
            routeInfo.add('思考・分析');
            break;
          case '四角顔':
          case '長方形顔':
            routeInfo.add('意志・行動');
            break;
        }
      }
    }

    // ルーティング情報を表示
    if (routeInfo.isNotEmpty) {
      selectedCriteria['判定ルート'] = ['ルート: ${routeInfo.join(" → ")}'];
    }

    // routerTreeから使用された特徴を取得
    final routerTree = detailedReason?['routerTree'] as Map<String, dynamic>?;
    final routerUsedFeatures =
        (routerTree?['usedFeatures'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];

    // 使用された極端特徴を抽出
    final usedFeatures = <String>[];

    // 眉の特徴（極端な特徴のみ・優先順位順：形状 → 角度 → 眉間の幅 → その他）
    if (features?['brow'] != null) {
      final brow = features!['brow'] as Map<String, dynamic>;
      final browCriteria = <String>[];

      // 第一優先：眉の形状
      // routerTreeで使用された場合のみ、かつ実際に極端な値の場合のみ表示
      final browShape = _parseDouble(brow['shape']) ?? 0.5;
      if (routerUsedFeatures.contains('brow_shape')) {
        // 極端に曲線的（>0.9）または極端に直線的（<0.2）の場合のみ表示
        if (browShape > 0.9) {
          browCriteria.add('眉の形状: 非常に曲線的 (${browShape.toStringAsFixed(2)})');
          usedFeatures.add('brow_shape');
        } else if (browShape < 0.2) {
          browCriteria.add('眉の形状: 直線的 (${browShape.toStringAsFixed(2)})');
          usedFeatures.add('brow_shape');
        }
        // 0.2 <= browShape <= 0.9 の場合は、routerTreeで使用されていても表示しない（極端ではない）
      }

      // 第二優先：眉の角度
      final browAngle = _parseDouble(brow['angle']) ?? 0.0;
      if (browAngle > 0.2 ||
          browAngle < -0.2 ||
          (browAngle >= -0.1 && browAngle <= 0.1) ||
          (browAngle >= -0.15 && browAngle <= 0.15) ||
          browAngle < -0.3) {
        if (browAngle > 0.2) {
          browCriteria.add('眉の角度: 右上がり (${browAngle.toStringAsFixed(2)})');
        } else if (browAngle < -0.2) {
          browCriteria.add('眉の角度: 右下がり (${browAngle.toStringAsFixed(2)})');
        } else if (browAngle >= -0.1 && browAngle <= 0.1) {
          browCriteria.add('眉の角度: 非常に水平 (${browAngle.toStringAsFixed(2)})');
        } else if (browAngle >= -0.15 && browAngle <= 0.15) {
          browCriteria.add('眉の角度: 水平 (${browAngle.toStringAsFixed(2)})');
        } else if (browAngle < -0.3) {
          browCriteria.add('眉の角度: 八字眉 (${browAngle.toStringAsFixed(2)})');
        }
        usedFeatures.add('brow_angle');
      }

      final browLength = _parseDouble(brow['length']) ?? 0.5;
      if (browLength > 0.9 || browLength < 0.3) {
        if (browLength > 0.9) {
          browCriteria.add('眉の長さ: 非常に長い (${browLength.toStringAsFixed(2)})');
        } else if (browLength < 0.3) {
          browCriteria.add('眉の長さ: 短い (${browLength.toStringAsFixed(2)})');
        }
        usedFeatures.add('brow_length');
      }

      final browThickness = _parseDouble(brow['thickness']) ?? 0.5;
      if (browThickness > 0.95 || browThickness < 0.2) {
        if (browThickness > 0.95) {
          browCriteria.add('眉の太さ: 非常に濃い (${browThickness.toStringAsFixed(2)})');
        } else if (browThickness < 0.2) {
          browCriteria.add('眉の太さ: 非常に薄い (${browThickness.toStringAsFixed(2)})');
        }
        usedFeatures.add('brow_thickness');
      }

      // 第三優先：眉間の幅
      final glabellaWidth = _parseDouble(brow['glabellaWidth']) ?? 0.5;
      if (glabellaWidth > 0.9 || glabellaWidth < 0.2) {
        if (glabellaWidth > 0.9) {
          browCriteria.add('眉間の幅: 非常に広い (${glabellaWidth.toStringAsFixed(2)})');
        } else if (glabellaWidth < 0.2) {
          browCriteria.add('眉間の幅: 非常に狭い (${glabellaWidth.toStringAsFixed(2)})');
        }
        usedFeatures.add('brow_space');
      }

      final browNeatness = _parseDouble(brow['neatness']) ?? 0.5;
      if (browNeatness > 0.95 || browNeatness < 0.15) {
        if (browNeatness > 0.95) {
          browCriteria.add('眉の整い: 非常に整っている (${browNeatness.toStringAsFixed(2)})');
        } else if (browNeatness < 0.15) {
          browCriteria.add('眉の整い: 非常に乱れている (${browNeatness.toStringAsFixed(2)})');
        }
        usedFeatures.add('brow_tidy');
      }

      if (browCriteria.isNotEmpty) {
        selectedCriteria['眉の特徴'] = browCriteria;
      }
    }

    // 目の特徴（極端な特徴のみ）
    if (features?['eye'] != null) {
      final eye = features!['eye'] as Map<String, dynamic>;
      final eyeCriteria = <String>[];

      final eyeBalance = _parseDouble(eye['balance']) ?? 0.5;
      if (eyeBalance > 0.85 || eyeBalance < 0.35) {
        if (eyeBalance > 0.85) {
          eyeCriteria.add('目のバランス: 非常に良い (${eyeBalance.toStringAsFixed(2)})');
        } else if (eyeBalance < 0.35) {
          eyeCriteria.add('目のバランス: 悪い (${eyeBalance.toStringAsFixed(2)})');
        }
        usedFeatures.add('eye_balance');
      }

      final eyeSize = _parseDouble(eye['size']) ?? 0.5;
      // routerTreeで使用された場合のみ、かつ実際に極端な値の場合のみ表示
      if (routerUsedFeatures.contains('eye_size')) {
        // 極端に大きい（>0.9）または極端に小さい（<0.3）の場合のみ表示
        if (eyeSize > 0.9) {
          eyeCriteria.add('目のサイズ: 非常に大きい (${eyeSize.toStringAsFixed(2)})');
          usedFeatures.add('eye_size');
        } else if (eyeSize < 0.3) {
          eyeCriteria.add('目のサイズ: 小さい (${eyeSize.toStringAsFixed(2)})');
          usedFeatures.add('eye_size');
        }
        // 0.3 <= eyeSize <= 0.9 の場合は、routerTreeで使用されていても表示しない（極端ではない）
      }

      final eyeShape = _parseDouble(eye['shape']) ?? 0.5;
      if (eyeShape > 0.95) {
        eyeCriteria.add('目の形状: 非常に切れ長 (${eyeShape.toStringAsFixed(2)})');
        usedFeatures.add('eye_shape');
      }

      if (eyeCriteria.isNotEmpty) {
        selectedCriteria['目の特徴'] = eyeCriteria;
      }
    }

    // 口の特徴（常に表示、判断されていない場合は「なし」と表示）
    final candidates = detailedReason?['candidates'] as Map<String, dynamic>?;
    final mouthWasSelected = candidates?['mouth'] == true;
    final mouth = features?['mouth'] as Map<String, dynamic>?;
    final mouthCriteria = <String>[];
    final mouthSize = _parseDouble(mouth?['size']) ?? 0.5;

    // 口の特徴が選考された場合、判断基準を表示
    if (mouthWasSelected) {
      // 口の大きさに基づく判断基準を表示
      if (mouthSize > 0.8) {
        mouthCriteria.add('口の大きさ: 非常に大きい (${mouthSize.toStringAsFixed(2)})');
        mouthCriteria.add('判断基準: 口が非常に大きい → 本能や欲望が強い、明るく開放的、社会性がある');
        mouthCriteria.add('該当する柱: Kanonis, Sylna, Amatera, Yatael, Skura');
      } else if (mouthSize > 0.75) {
        mouthCriteria.add('口の大きさ: 大きい (${mouthSize.toStringAsFixed(2)})');
        mouthCriteria.add('判断基準: 口が非常に大きい → 本能や欲望が強い、明るく開放的');
        mouthCriteria.add('該当する柱: Kanonis, Sylna, Amatera');
      } else if (mouthSize < 0.25) {
        mouthCriteria.add('口の大きさ: 非常に小さい (${mouthSize.toStringAsFixed(2)})');
        mouthCriteria.add('判断基準: 口が非常に小さい → 素直で誠実、慎重、神経質、美的感覚が鋭い');
        mouthCriteria.add('該当する柱: Delphos, Amanoira, Fatemis, Noirune, Mimika');
      } else if (mouthSize < 0.3) {
        mouthCriteria.add('口の大きさ: 小さい (${mouthSize.toStringAsFixed(2)})');
        mouthCriteria.add('判断基準: 口が小さい → 素直で誠実、慎重、神経質');
        mouthCriteria.add('該当する柱: Amanoira, Fatemis, Noirune, Mimika');
      } else if (mouthSize < 0.4) {
        mouthCriteria.add('口の大きさ: やや小さい (${mouthSize.toStringAsFixed(2)})');
        mouthCriteria.add('判断基準: 口が小さい → 素直で誠実、慎重');
        mouthCriteria.add('該当する柱: Amanoira');
      } else {
        // 口の特徴が選考されたが、極端な値でない場合
        mouthCriteria.add('口の大きさ: ${mouthSize.toStringAsFixed(2)}');
        mouthCriteria.add('判断基準: 口の特徴が判定に使用されました');
      }
      usedFeatures.add('mouth_size');
    } else {
      // routerTreeで使用された場合、または極端な値の場合に表示
      // 極端な特徴のみを抽出（普通の値0.25~0.8はスキップ）
      // routerTreeで使用されている場合は、極端な値でなくても表示する
      if (routerUsedFeatures.contains('mouth_size') || mouthSize > 0.8 || mouthSize < 0.25) {
        if (mouthSize > 0.8) {
          mouthCriteria.add('口の大きさ: 非常に大きい (${mouthSize.toStringAsFixed(2)})');
          usedFeatures.add('mouth_size');
        } else if (mouthSize < 0.25) {
          mouthCriteria.add('口の大きさ: 非常に小さい (${mouthSize.toStringAsFixed(2)})');
          usedFeatures.add('mouth_size');
        } else if (routerUsedFeatures.contains('mouth_size')) {
          // routerTreeで使用されているが、極端な値でない場合も表示（中間的な値として）
          if (mouthSize > 0.6) {
            mouthCriteria.add('口の大きさ: 大きい (${mouthSize.toStringAsFixed(2)})');
            usedFeatures.add('mouth_size');
          } else if (mouthSize < 0.4) {
            mouthCriteria.add('口の大きさ: 小さい (${mouthSize.toStringAsFixed(2)})');
            usedFeatures.add('mouth_size');
          } else {
            // routerTreeで使用されているが、中間的な値の場合も表示
            mouthCriteria.add('口の大きさ: 標準的 (${mouthSize.toStringAsFixed(2)})');
            usedFeatures.add('mouth_size');
          }
        }
      }

      // routerTreeで使用されている場合は、必ず表示する
      if (routerUsedFeatures.contains('mouth_size') && mouthCriteria.isEmpty) {
        mouthCriteria.add('口の大きさ: ${mouthSize.toStringAsFixed(2)}');
        usedFeatures.add('mouth_size');
      }

      // 判断されていない場合は「なし」と表示
      if (mouthCriteria.isEmpty) {
        mouthCriteria.add('なし');
      }
    }

    // 常に口の特徴の枠を表示
    selectedCriteria['口の特徴'] = mouthCriteria;

    // 顔の型
    if (features?['faceType'] != null) {
      final faceType = features!['faceType'] as String?;
      if (faceType != null && faceType.isNotEmpty) {
        selectedCriteria['顔の型'] = ['顔の型: $faceType'];
        usedFeatures.add('face_type');
      }
    }

    // 使用された特徴を表示
    if (usedFeatures.isNotEmpty) {
      selectedCriteria['使用された特徴'] = ['特徴数: ${usedFeatures.length}個 (${usedFeatures.join(", ")})'];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            '選考した判断基準',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.deity.nameJa}が選ばれた理由',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.deepPurple.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Colors.deepPurple,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '極端な特徴のみで判定されます。普通の値はスキップされます。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.deepPurple.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 選考した判断基準を表示
          ...selectedCriteria.entries.map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...entry.value.map((criterion) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '• ',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.deepPurple,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                criterion,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            );
          }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
