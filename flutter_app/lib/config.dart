/// config.dart — ตั้งค่าแอป
import 'package:flutter/foundation.dart';

class AppConfig {
  // === API URL ===
  // Production: ส่ง --dart-define=API_BASE_URL=https://... ตอน build
  // Dev: ใช้ localhost (web) หรือ 10.0.2.2 (Android emulator)
  static String get apiBaseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) return 'http://localhost:8000';
    return 'http://10.0.2.2:8000';
  }

  // === App Info ===
  static const String appName = 'ฟ้า AI Friend';
  static const String appVersion = '1.3.0';

  // === Theme Colors ===
  static const int primaryColorValue = 0xFF6C9BCF;
  static const int secondaryColorValue = 0xFFF5F7FA;
}
