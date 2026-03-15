// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'image_input.dart';

/// Web: HTML file input（iOS Safari でも安定）
class ImageInputImpl implements ImageInput {
  @override
  Future<PickedImage?> pick({required bool preferCamera}) async {
    final input = html.FileUploadInputElement();
    input.accept = 'image/*';
    if (preferCamera) {
      input.setAttribute('capture', 'user');
    }
    input.click();
    await input.onChange.first;

    final files = input.files;
    if (files == null || files.isEmpty) return null;
    final file = files.first;

    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoadEnd.first;

    final data = reader.result;
    if (data == null) return null;
    final bytes = Uint8List.view(data as ByteBuffer);

    final filename = file.name.isNotEmpty ? file.name : 'upload.jpg';
    final mime = (file.type.isNotEmpty && file.type.startsWith('image/')) ? file.type : 'image/jpeg';

    return PickedImage(bytes: bytes, filename: filename, mimeType: mime);
  }

  @override
  Future<PickedImage?> pickFromExternalPathOrIntentIfAvailable() async {
    return null;
  }
}
