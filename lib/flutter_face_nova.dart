library flutter_face_nova;

export 'src/liveness_types.dart';
export 'src/flutter_face_nova_mobile.dart'
    if (dart.library.js_interop) 'src/flutter_face_nova_web.dart';
