import 'package:flutter/foundation.dart';

String get backendUrl {
  if (kDebugMode) return 'http://localhost:5492';
  // In release web builds, backend is served from the same origin
  if (kIsWeb) {
    final origin = Uri.base.origin;
    return origin;
  }
  return 'http://localhost:5492';
}
