// Web ビルド用: dart:io の File のスタブ（実体は使わない）

class File {
  File(String path);
  String get path => throw UnsupportedError('dart:io File is not available on web');
  Future<bool> exists() => throw UnsupportedError('dart:io File is not available on web');
  bool existsSync() => throw UnsupportedError('dart:io File is not available on web');
  Future<List<int>> readAsBytes() => throw UnsupportedError('dart:io File is not available on web');
  Future<File> writeAsBytes(List<int> bytes) => throw UnsupportedError('dart:io File is not available on web');
  Future<int> length() => throw UnsupportedError('dart:io File is not available on web');
  Future<File> copy(String newPath) => throw UnsupportedError('dart:io File is not available on web');
  Future<void> delete() => throw UnsupportedError('dart:io File is not available on web');
}

class Directory {
  Directory(String path);
  String get path => throw UnsupportedError('dart:io Directory is not available on web');
  String get parent => throw UnsupportedError('dart:io Directory is not available on web');
  Future<bool> exists() => throw UnsupportedError('dart:io Directory is not available on web');
  Stream<dynamic> list() => throw UnsupportedError('dart:io Directory is not available on web');
}
