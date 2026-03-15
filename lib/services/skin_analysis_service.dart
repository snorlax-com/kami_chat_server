import 'dart:async';
import 'dart:io' if (dart.library.html) 'package:kami_face_oracle/core/io_stub.dart' as io;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../skin_analysis.dart';

/// 肌診断サービスのシングルトン（多重実行防止・リソース管理）
class SkinAnalysisService {
  static final SkinAnalysisService _instance = SkinAnalysisService._internal();
  factory SkinAnalysisService() => _instance;
  SkinAnalysisService._internal();

  // 多重実行防止用のロック
  bool _isAnalyzing = false;
  final _queue = <_AnalysisTask>[];
  _AnalysisTask? _currentTask;

  /// 肌診断を実行（キュー化・直列化）
  /// 既に実行中の場合はキューに追加され、順次処理される
  Future<SkinAnalysisResult> analyzeSkin(io.File imageFile, Face face) async {
    final task = _AnalysisTask(imageFile, face);
    _queue.add(task);

    // 既に実行中でない場合は即座に実行
    if (!_isAnalyzing) {
      _processQueue();
    }

    return task.completer.future;
  }

  /// キューを処理（直列化）
  Future<void> _processQueue() async {
    if (_isAnalyzing || _queue.isEmpty) return;

    _isAnalyzing = true;
    print('[SkinAnalysisService] 🔒 分析開始（キューサイズ: ${_queue.length}）');

    while (_queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      _currentTask = task;

      try {
        print('[SkinAnalysisService] 📊 分析実行中: ${task.imageFile.path}');
        final result = await SkinAnalyzer.analyzeSkin(task.imageFile, task.face);
        task.completer.complete(result);
        print('[SkinAnalysisService] ✅ 分析完了');
      } catch (e, stackTrace) {
        print('[SkinAnalysisService] ❌ 分析エラー: $e');
        print('[SkinAnalysisService] スタックトレース: ${stackTrace.toString().split("\n").take(10).join("\n")}');
        task.completer.completeError(e, stackTrace);
      } finally {
        _currentTask = null;
      }
    }

    _isAnalyzing = false;
    print('[SkinAnalysisService] 🔓 分析終了（キュー処理完了）');
  }

  /// 現在のキューサイズを取得
  int get queueSize => _queue.length;

  /// 分析中かどうか
  bool get isAnalyzing => _isAnalyzing;
}

/// 分析タスク
class _AnalysisTask {
  final io.File imageFile;
  final Face face;
  final Completer<SkinAnalysisResult> completer = Completer<SkinAnalysisResult>();

  _AnalysisTask(this.imageFile, this.face);
}
