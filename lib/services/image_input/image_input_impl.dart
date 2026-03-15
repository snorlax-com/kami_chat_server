import 'image_input.dart';
import 'mobile_image_input.dart' if (dart.library.html) 'web_image_input.dart';

ImageInput createImageInput() => ImageInputImpl();
