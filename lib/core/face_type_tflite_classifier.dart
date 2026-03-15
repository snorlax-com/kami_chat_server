import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'mediapipe_face_features.dart';
import 'mediapipe_face_data.dart';

/// TFLiteモデルを使用した顔型分類器
class FaceTypeTFLiteClassifier {
  static Interpreter? _interpreter;
  static bool _isInitialized = false;

  // 顔型のラベル
  static const List<String> FACE_TYPES = [
    '丸顔', // 0
    '細長顔', // 1
    '長方形顔', // 2
    '台座顔', // 3
    '卵顔', // 4
    '四角顔', // 5
    '逆三角形顔', // 6
    '三角形顔', // 7
  ];

  /// モデルを初期化
  static Future<bool> initialize() async {
    if (_isInitialized && _interpreter != null) {
      return true;
    }

    try {
      // モデルファイルを読み込む
      final modelPath = 'assets/models/face_type_classifier.tflite';
      final modelData = await rootBundle.load(modelPath);
      final modelBytes = modelData.buffer.asUint8List();

      // インタープリターを作成
      _interpreter = Interpreter.fromBuffer(modelBytes);

      // 入力・出力の形状を確認
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      print('[FaceTypeTFLiteClassifier] ✅ モデルを読み込みました');
      print('[FaceTypeTFLiteClassifier] 入力形状: $inputShape');
      print('[FaceTypeTFLiteClassifier] 出力形状: $outputShape');

      _isInitialized = true;
      return true;
    } catch (e) {
      print('[FaceTypeTFLiteClassifier] ❌ モデルの読み込みに失敗: $e');
      return false;
    }
  }

  /// 顔画像から顔型を分類
  static Future<Map<String, dynamic>?> classify(
    Face face,
    Uint8List imageBytes,
    MediaPipeFaceMesh? faceMesh,
    MediaPipeFaceFeatures? mediaPipeFeatures,
  ) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        return null;
      }
    }

    try {
      // 画像を前処理
      final inputImage = img.decodeImage(imageBytes);
      if (inputImage == null) {
        print('[FaceTypeTFLiteClassifier] ❌ 画像のデコードに失敗');
        return null;
      }

      // 顔領域を抽出
      final box = face.boundingBox;
      final faceImage = img.copyCrop(
        inputImage,
        x: box.left.toInt(),
        y: box.top.toInt(),
        width: box.width.toInt(),
        height: box.height.toInt(),
      );

      // リサイズ（224x224）
      final resized = img.copyResize(faceImage, width: 224, height: 224);

      // 画像を正規化（0-255 → 0-1）
      final inputBuffer = Float32List(224 * 224 * 3);
      int idx = 0;
      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final pixel = resized.getPixel(x, y);
          inputBuffer[idx++] = pixel.r / 255.0;
          inputBuffer[idx++] = pixel.g / 255.0;
          inputBuffer[idx++] = pixel.b / 255.0;
        }
      }

      // 入力テンソル
      final input = [
        inputBuffer.reshape([1, 224, 224, 3])
      ];

      // 出力テンソル
      final output = [Float32List(8)];

      // 推論実行
      _interpreter!.run(input, output);

      // 結果を取得
      final predictions = output[0] as Float32List;
      final maxIndex = predictions.indexOf(predictions.reduce((a, b) => a > b ? a : b));
      final confidence = predictions[maxIndex];
      final predictedType = FACE_TYPES[maxIndex];

      // MediaPipe特徴量と統合（加重平均）
      String finalType = predictedType;
      double finalConfidence = confidence;

      if (mediaPipeFeatures != null) {
        // MediaPipe特徴量ベースの分類結果を計算
        final mediaPipeType = _classifyFromFeatures(mediaPipeFeatures);

        // 加重平均（MLモデル: 70%, MediaPipe: 30%）
        if (mediaPipeType != null) {
          final mlWeight = 0.7;
          final mpWeight = 0.3;

          // 両方の結果が同じ場合
          if (predictedType == mediaPipeType['type']) {
            finalConfidence = (confidence * mlWeight + mediaPipeType['confidence'] * mpWeight);
          } else {
            // 異なる場合、より信頼度の高い方を選択
            if (confidence > mediaPipeType['confidence']) {
              finalType = predictedType;
              finalConfidence = confidence * mlWeight;
            } else {
              finalType = mediaPipeType['type'];
              finalConfidence = mediaPipeType['confidence'] * mpWeight;
            }
          }
        }
      }

      return {
        'type': finalType,
        'confidence': finalConfidence,
        'allPredictions': Map.fromIterables(
          FACE_TYPES,
          predictions.toList(),
        ),
        'mlModelType': predictedType,
        'mlModelConfidence': confidence,
      };
    } catch (e, stackTrace) {
      print('[FaceTypeTFLiteClassifier] ❌ 分類エラー: $e');
      print('[FaceTypeTFLiteClassifier] スタックトレース: $stackTrace');
      return null;
    }
  }

  /// MediaPipe特徴量から分類（フォールバック）
  static Map<String, dynamic>? _classifyFromFeatures(MediaPipeFaceFeatures features) {
    // 簡易的なルールベース分類
    final scores = <String, double>{};

    // 各型のスコアを計算
    for (final type in FACE_TYPES) {
      double score = 0.0;

      switch (type) {
        case '丸顔':
          if (features.faceAspectRatio > 0.70 && features.faceAspectRatio < 0.85) {
            score += 0.3;
          }
          if (features.jawCurvature > 0.5) score += 0.2;
          if (features.cheekProminence > 0.5) score += 0.2;
          break;
        case '細長顔':
          if (features.faceAspectRatio > 0.80) score += 0.4;
          if (features.eyeShape > 0.7) score += 0.2;
          break;
        case '長方形顔':
          if (features.faceAspectRatio > 0.55 && features.faceAspectRatio < 0.80) {
            score += 0.3;
          }
          if (features.eyeShape > 0.35) score += 0.2;
          break;
        case '台座顔':
          if (features.faceAspectRatio > 0.65 && features.faceAspectRatio < 0.90) {
            score += 0.3;
          }
          if (features.jawCurvature > 0.4) score += 0.2;
          break;
        case '卵顔':
          if (features.faceAspectRatio > 0.5 && features.faceAspectRatio < 0.95) {
            score += 0.3;
          }
          if (features.noseHeight > 0.15) score += 0.2;
          break;
        case '四角顔':
          if (features.faceAspectRatio > 0.55 && features.faceAspectRatio < 0.95) {
            score += 0.3;
          }
          if (features.jawCurvature < 0.6) score += 0.2;
          break;
        case '逆三角形顔':
          if (features.foreheadWidth > features.jawWidth * 1.2) {
            score += 0.4;
          }
          break;
        case '三角形顔':
          if (features.jawWidth > features.foreheadWidth * 1.2) {
            score += 0.4;
          }
          break;
      }

      scores[type] = score;
    }

    // 最高スコアの型を選択
    if (scores.isEmpty) return null;

    final bestEntry = scores.entries.reduce((a, b) => a.value > b.value ? a : b);
    return {
      'type': bestEntry.key,
      'confidence': bestEntry.value.clamp(0.0, 1.0),
    };
  }

  /// モデルを解放
  static void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}

extension Float32ListExtension on Float32List {
  List<List<List<List<double>>>> reshape(List<int> shape) {
    if (shape.length != 4) {
      throw ArgumentError('Shape must be 4D');
    }
    final result = <List<List<List<double>>>>[];
    int idx = 0;
    for (int i = 0; i < shape[0]; i++) {
      final batch = <List<List<double>>>[];
      for (int j = 0; j < shape[1]; j++) {
        final row = <List<double>>[];
        for (int k = 0; k < shape[2]; k++) {
          final channel = <double>[];
          for (int l = 0; l < shape[3]; l++) {
            channel.add(this[idx++]);
          }
          row.add(channel);
        }
        batch.add(row);
      }
      result.add(batch);
    }
    return result;
  }
}
