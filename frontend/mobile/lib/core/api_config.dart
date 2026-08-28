import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Central API configuration.
///
/// - Android emulator reaches the host machine via 10.0.2.2.
/// - Web/iOS simulator use localhost.
class ApiConfig {
  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:8000/api/v1';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000/api/v1';
    return 'http://localhost:8000/api/v1';
  }
}
