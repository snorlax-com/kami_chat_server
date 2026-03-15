/// FaceMesh Web ブリッジ（Web 時のみ有効。非 Web はスタブ）
export 'face_mesh_web_bridge_stub.dart' if (dart.library.html) 'face_mesh_web_bridge_web.dart';
