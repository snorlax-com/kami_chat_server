import 'dart:io';
import 'package:flutter/services.dart';

/// 外部ストレージのファイルにアクセスするためのヘルパークラス
/// Android 11以降の権限問題を回避するため、Platform Channelを使用
class FileAccessHelper {
  static const MethodChannel _channel = MethodChannel('com.auraface.kami_face_oracle/file_access');

  /// 外部ストレージのファイルをアプリの内部ストレージにコピー
  /// これにより権限エラーを回避
  static Future<String?> copyExternalFileToInternal(String externalPath) async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<String>(
          'copyExternalFileToInternal',
          {'externalPath': externalPath},
        );
        return result;
      }
      return null;
    } catch (e) {
      print('[FileAccessHelper] エラー: $e');
      return null;
    }
  }

  /// ファイルが読み取り可能か確認
  static Future<bool> canReadFile(String filePath) async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<bool>(
          'canReadFile',
          {'filePath': filePath},
        );
        return result ?? false;
      }
      return false;
    } catch (e) {
      print('[FileAccessHelper] エラー: $e');
      return false;
    }
  }

  /// 外部ストレージのファイルをアプリの外部ストレージディレクトリ（cache）にコピー
  /// path_providerで取得できるディレクトリにコピー
  static Future<String?> copyExternalFileToAppCache(String externalPath) async {
    try {
      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<String>(
          'copyExternalFileToAppCache',
          {'externalPath': externalPath},
        );
        return result;
      }
      return null;
    } catch (e) {
      print('[FileAccessHelper] エラー: $e');
      return null;
    }
  }
}
