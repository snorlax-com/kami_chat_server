import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// モバイル用: bytes を一時ファイルに書き、パスを返す
Future<String?> getTempImagePathFromBytes(List<int> bytes) async {
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/tmp_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await f.writeAsBytes(bytes);
    return f.path;
  } catch (_) {
    return null;
  }
}
