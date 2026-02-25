/// auth_service.dart — Device ID + Social Login (เตรียมไว้)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'local_storage.dart';

class AuthService {
  /// สร้าง unique device ID
  static Future<String> getDeviceId() async {
    if (kIsWeb) return 'web-device';
    return 'device-unknown';
  }

  /// ตรวจสอบว่า login อยู่หรือไม่
  static bool get isLoggedIn => LocalStorage.isRegistered;

  /// Logout — ล้างข้อมูล
  static Future<void> logout() async {
    await LocalStorage.clearAll();
  }
}
