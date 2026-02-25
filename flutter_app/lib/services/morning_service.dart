// morning_service.dart — ดึงข้อความสรุปเช้าจาก Backend
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'local_storage.dart';
import 'notification_service.dart';

class MorningService {
  /// ตั้ง notification สรุปเช้า
  static Future<void> setupMorningBrief() async {
    if (!LocalStorage.morningNotification) return;

    final parts = LocalStorage.wakeTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 7;
    final minute = int.tryParse(parts[1]) ?? 0;

    await NotificationService.scheduleDailyReminder(
      id: 1,
      title: '☀️ ฟ้าทักมา~',
      body: 'อรุณสวัสดิ์ ${LocalStorage.userName}! วันนี้จะเป็นวันที่ดีนะ!',
      hour: hour,
      minute: minute,
    );
  }

  /// ดึงข้อความสรุปเช้าจาก API (ใช้แสดงในแชท)
  static Future<String?> fetchMorningBrief() async {
    try {
      final userId = LocalStorage.userId;
      if (userId.isEmpty) return null;

      final response = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/brief/morning/$userId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['message'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
