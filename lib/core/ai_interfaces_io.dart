import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:kami_face_oracle/services/remote_config_service.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class AppAiConfig {
  static bool get enableTFLite => RemoteConfigService.instance.getBool('enable_tflite', defaultValue: true);
  static bool get enableSegmentation =>
      RemoteConfigService.instance.getBool('enable_segmentation', defaultValue: false);
  static String get modelsDir => 'assets/models/';
}

class GlossEvennessTFLite {
  final String modelPath;
  GlossEvennessTFLite(this.modelPath);

  bool get isAvailable => AppAiConfig.enableTFLite && File(modelPath).existsSync();

  Future<Map<String, double>?> predict(img.Image face) async {
    if (!isAvailable) return null;
    try {
      return null;
    } catch (e) {
      return null;
    }
  }
}

class BlemishSegmentation {
  final String modelPath;
  BlemishSegmentation(this.modelPath);

  bool get isAvailable => AppAiConfig.enableSegmentation && File(modelPath).existsSync();

  Future<double?> inferMaskRatio(img.Image face) async {
    if (!isAvailable) return null;
    try {
      return null;
    } catch (e) {
      return null;
    }
  }
}

class SkinConditionClassifier {
  final String modelPath;
  Interpreter? _interpreter;
  bool _isInitialized = false;

  SkinConditionClassifier(this.modelPath);

  bool get isAvailable => AppAiConfig.enableTFLite;

  Future<bool> initialize() async {
    if (!isAvailable) {
      print('[SkinConditionClassifier] TFLiteが無効化されています');
      return false;
    }

    if (_isInitialized && _interpreter != null) {
      return true;
    }

    try {
      print('[SkinConditionClassifier] モデル初期化開始: $modelPath');
      _interpreter = await Interpreter.fromAsset(modelPath);
      _interpreter!.allocateTensors();
      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);
      print('[SkinConditionClassifier] ✅ モデル初期化成功');
      print('[SkinConditionClassifier]   入力形状: ${inputTensor.shape}');
      print('[SkinConditionClassifier]   出力形状: ${outputTensor.shape}');
      _isInitialized = true;
      return true;
    } catch (e, stackTrace) {
      print('[SkinConditionClassifier] ❌ 初期化エラー: $e');
      print('[SkinConditionClassifier] スタックトレース: ${stackTrace.toString().split("\n").take(5).join("\n")}');
      _interpreter = null;
      _isInitialized = false;
      return false;
    }
  }

  Future<Map<String, double>?> classify(img.Image faceImage) async {
    print('[SkinConditionClassifier] 🔍 classify() 開始');

    if (!_isInitialized || _interpreter == null) {
      print('[SkinConditionClassifier] 🔍 初期化が必要、initialize()を呼び出し');
      final initialized = await initialize();
      if (!initialized) {
        print('[SkinConditionClassifier] ⚠️ モデルが初期化できませんでした');
        print('[SkinConditionClassifier] 🔍 classify失敗理由: initialization_failed');
        return null;
      }
    }

    try {
      print('[SkinConditionClassifier] 🔍 入力画像サイズ: ${faceImage.width}x${faceImage.height}');

      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);

      final inputShape = inputTensor.shape;
      final inputHeight = inputShape[1];
      final inputWidth = inputShape[2];
      final inputChannels = inputShape.length > 3 ? inputShape[3] : 3;

      print(
          '[SkinConditionClassifier] 🔍 モデル入力形状: $inputShape (height=$inputHeight, width=$inputWidth, channels=$inputChannels)');
      print('[SkinConditionClassifier] 🔍 モデル入力型: ${inputTensor.type}');

      if (faceImage.width == 0 || faceImage.height == 0) {
        print('[SkinConditionClassifier] ⚠️ 入力画像サイズが無効: ${faceImage.width}x${faceImage.height}');
        print('[SkinConditionClassifier] 🔍 classify失敗理由: invalid_input_image (size=0)');
        return null;
      }

      final resized = img.copyResize(
        faceImage,
        width: inputWidth,
        height: inputHeight,
        interpolation: img.Interpolation.linear,
      );

      print('[SkinConditionClassifier] 🔍 リサイズ後: ${resized.width}x${resized.height}');

      final inputData = _imageToFloat32List(resized, inputWidth, inputHeight);

      print(
          '[SkinConditionClassifier] 🔍 前処理完了: inputData.length=${inputData.length}, 期待サイズ=${inputWidth * inputHeight * inputChannels}');

      final outputShape = outputTensor.shape;
      final outputSize = outputShape.reduce((a, b) => a * b);
      final output = Float32List(outputSize);

      print('[SkinConditionClassifier] 入力データサイズ: ${inputData.length}, 期待サイズ: ${inputWidth * inputHeight * 3}');
      print('[SkinConditionClassifier] 出力形状: $outputShape, 出力サイズ: $outputSize');
      print('[SkinConditionClassifier] 入力テンソル型: ${inputTensor.type}, 出力テンソル型: ${outputTensor.type}');

      print('[SkinConditionClassifier] 推論実行中（解決案1: setInputTensor/invoke）...');
      try {
        inputTensor.setTo(inputData);
        _interpreter!.invoke();
        final outputData = outputTensor.data;
        if (outputData is Float32List) {
          for (int i = 0; i < output.length && i < outputData.length; i++) {
            output[i] = outputData[i] as double;
          }
        } else {
          final list = outputData as List;
          for (int i = 0; i < output.length && i < list.length; i++) {
            output[i] = (list[i] as num).toDouble();
          }
        }
        print('[SkinConditionClassifier] ✅ 推論完了（解決案1成功）');
      } catch (e, stackTrace) {
        print('[SkinConditionClassifier] ❌ 解決案1エラー: $e');
        print('[SkinConditionClassifier] スタックトレース: ${stackTrace.toString().split("\n").take(3).join("\n")}');

        print('[SkinConditionClassifier] 解決案2にフォールバック（形状確認とリシェイプ）...');
        try {
          final expectedSize = inputShape.reduce((a, b) => a * b);
          if (inputData.length != expectedSize) {
            print('[SkinConditionClassifier] 警告: 入力データサイズが不一致。期待: $expectedSize, 実際: ${inputData.length}');
          }
          _interpreter!.run(inputData, output);
          print('[SkinConditionClassifier] ✅ 推論完了（解決案2成功）');
        } catch (e2) {
          print('[SkinConditionClassifier] ❌ 解決案2もエラー: $e2');

          print('[SkinConditionClassifier] 解決案3にフォールバック（runForMultipleInputs）...');
          try {
            _interpreter!.runForMultipleInputs([inputData], {0: output});
            print('[SkinConditionClassifier] ✅ 推論完了（解決案3成功）');
          } catch (e3) {
            print('[SkinConditionClassifier] ❌ 解決案3もエラー: $e3');

            print('[SkinConditionClassifier] 解決案4にフォールバック（モデル再初期化）...');
            try {
              _interpreter?.close();
              _interpreter = null;
              _isInitialized = false;
              await initialize();
              if (_interpreter != null) {
                _interpreter!.run(inputData, output);
                print('[SkinConditionClassifier] ✅ 推論完了（解決案4成功）');
              } else {
                throw Exception('モデルの再初期化に失敗');
              }
            } catch (e4) {
              print('[SkinConditionClassifier] ❌ 解決案4もエラー: $e4');

              print('[SkinConditionClassifier] 解決案5にフォールバック（入力データ型変換）...');
              try {
                final inputType = inputTensor.type;
                print('[SkinConditionClassifier] 入力テンソル型: $inputType');

                dynamic convertedInput;
                if (inputType == TensorType.float32) {
                  convertedInput = inputData;
                } else if (inputType == TensorType.uint8) {
                  final uint8Data = Uint8List(inputData.length);
                  for (int i = 0; i < inputData.length; i++) {
                    uint8Data[i] = (inputData[i] * 255).clamp(0, 255).toInt();
                  }
                  convertedInput = uint8Data;
                } else {
                  convertedInput = inputData;
                }

                _interpreter!.run(convertedInput, output);
                print('[SkinConditionClassifier] ✅ 推論完了（解決案5成功）');
              } catch (e5) {
                print('[SkinConditionClassifier] ❌ 解決案5もエラー: $e5');
                print('[SkinConditionClassifier] ❌ すべての解決案が失敗しました');
                rethrow;
              }
            }
          }
        }
      }

      print('[SkinConditionClassifier] 出力データ型: ${output.runtimeType}');
      List<double> rawOutput = output.map((e) => e.toDouble()).toList();

      print('[SkinConditionClassifier] 生の出力値: ${rawOutput.take(5).toList()}');

      if (outputShape.length > 1 && outputShape[0] == 1) {
        final numClasses = outputShape[1];
        rawOutput = rawOutput.sublist(0, numClasses);
      }

      final probabilities = _softmax(rawOutput);

      final total = probabilities.fold<double>(0.0, (sum, v) => sum + v);
      print('[SkinConditionClassifier] 🔍 Softmax後合計: $total (期待値≈1.0)');

      final labels = ['acne', 'darkcircle', 'normal', 'swelling', 'wrinkle'];

      final result = <String, double>{};
      for (int i = 0; i < labels.length && i < probabilities.length; i++) {
        result[labels[i]] = probabilities[i].clamp(0.0, 1.0);
      }

      print('[SkinConditionClassifier] 📋 ラベル順序（アルファベット順）: $labels');
      for (int i = 0; i < labels.length && i < probabilities.length; i++) {
        print('[SkinConditionClassifier]   [$i] ${labels[i]} = ${(probabilities[i] * 100).toStringAsFixed(2)}%');
      }

      final maxValue = result.values.reduce((a, b) => a > b ? a : b);
      if (maxValue < 0.01) {
        print('[SkinConditionClassifier] ⚠️⚠️⚠️ 警告: AI分類が0.00%連発（最大値=$maxValue）');
      }

      final normalValue = result['normal'] ?? 0.0;
      final otherValues = [
        result['acne'] ?? 0.0,
        result['darkcircle'] ?? 0.0,
        result['wrinkle'] ?? 0.0,
        result['swelling'] ?? 0.0,
      ];
      final otherMax = otherValues.reduce((a, b) => a > b ? a : b);

      if (normalValue > 0.7 && otherMax < 0.1) {
        print(
            '[SkinConditionClassifier] ⚠️⚠️⚠️ 警告: 正常肌が異常に高確率（${(normalValue * 100).toStringAsFixed(1)}%）で、他が低い（最大${(otherMax * 100).toStringAsFixed(1)}%）');
      }

      print(
          '[SkinConditionClassifier] ✅ 最終結果: acne=${result['acne']?.toStringAsFixed(3)}, darkcircle=${result['darkcircle']?.toStringAsFixed(3)}, wrinkle=${result['wrinkle']?.toStringAsFixed(3)}, swelling=${result['swelling']?.toStringAsFixed(3)}, normal=${result['normal']?.toStringAsFixed(3)}');
      print('[SkinConditionClassifier] 🔍 classify() 完了');

      return result;
    } catch (e, stackTrace) {
      print('[SkinConditionClassifier] ❌ 分類エラー: $e');
      print('[SkinConditionClassifier] 🔍 スタックトレース: ${stackTrace.toString().split("\n").take(10).join("\n")}');

      String errorReason = 'unknown';
      if (e.toString().contains('FileNotFoundException') || e.toString().contains('No such file')) {
        errorReason = 'model_missing';
      } else if (e.toString().contains('Interpreter') || e.toString().contains('initialize')) {
        errorReason = 'interpreter_init_failed';
      } else if (e.toString().contains('input') || e.toString().contains('size') || e.toString().contains('decode')) {
        errorReason = 'invalid_input_image';
      } else if (e.toString().contains('run') ||
          e.toString().contains('invoke') ||
          e.toString().contains('inference')) {
        errorReason = 'inference_failed';
      } else if (e.toString().contains('output') || e.toString().contains('NaN') || e.toString().contains('Infinity')) {
        errorReason = 'output_invalid';
      }

      print('[SkinConditionClassifier] 🔍 classify失敗理由: $errorReason');
      print('[SkinConditionClassifier] 🔍 classify() 失敗');

      return null;
    }
  }

  Float32List _imageToFloat32List(img.Image image, int width, int height) {
    final inputSize = width * height * 3;
    final inputData = Float32List(inputSize);

    int index = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        inputData[index++] = pixel.r / 255.0;
        inputData[index++] = pixel.g / 255.0;
        inputData[index++] = pixel.b / 255.0;
      }
    }

    return inputData;
  }

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final expLogits = logits.map((x) => math.exp(x - maxLogit)).toList();
    final sum = expLogits.reduce((a, b) => a + b);
    return expLogits.map((x) => x / sum).toList();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
