/// api_service.dart — เชื่อมต่อ Backend API
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'local_storage.dart';

class ApiService {
  static String get _baseUrl => AppConfig.apiBaseUrl;

  /// สมัครผู้ใช้ใหม่
  static Future<Map<String, dynamic>> register({
    required String name,
    required String personality,
    String wakeTime = '07:00',
    String sleepTime = '23:00',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'personality': personality,
        'wake_time': wakeTime,
        'sleep_time': sleepTime,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Registration failed: ${response.statusCode}');
  }

  /// Auto-reregister เมื่อ server DB reset (Render free tier)
  /// ใช้ข้อมูลเดิมจาก LocalStorage + สร้าง user ใหม่บน server
  static Future<bool> _autoReRegister() async {
    try {
      final name = LocalStorage.userName;
      final personality = LocalStorage.personality;
      if (name.isEmpty) return false;

      debugPrint('Auto-reregistering user: $name (DB was reset)');

      final result = await register(
        name: name,
        personality: personality,
        wakeTime: LocalStorage.wakeTime,
        sleepTime: LocalStorage.sleepTime,
      );

      // อัพเดต userId ใหม่ (server สร้าง id ใหม่)
      final newUserId = result['user_id'] as String;
      await LocalStorage.saveUser(
        userId: newUserId,
        name: name,
        personality: personality,
      );

      debugPrint('Auto-reregistered with new userId: $newUserId');
      return true;
    } catch (e) {
      debugPrint('Auto-reregister failed: $e');
      return false;
    }
  }

  /// ส่งข้อความแชท (auto-reregister ถ้า user หายจาก DB)
  static Future<Map<String, dynamic>> sendMessage({
    required String userId,
    required String message,
  }) async {
    var response = await http.post(
      Uri.parse('$_baseUrl/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'message': message,
      }),
    );

    // ถ้า 404 = user ไม่เจอ (DB reset เพราะ Render restart)
    // → auto-reregister แล้ว retry ด้วย userId ใหม่
    if (response.statusCode == 404) {
      debugPrint('User not found (404), attempting auto-reregister...');
      final ok = await _autoReRegister();
      if (ok) {
        // retry ด้วย userId ใหม่
        final newUserId = LocalStorage.userId;
        response = await http.post(
          Uri.parse('$_baseUrl/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': newUserId,
            'message': message,
          }),
        );
      }
    }

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Chat failed: ${response.statusCode} - ${response.body}');
  }

  /// ดึง reminders
  static Future<List<Map<String, dynamic>>> getReminders(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/reminders/$userId'),
    );

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list.cast<Map<String, dynamic>>();
    }
    throw Exception('Get reminders failed: ${response.statusCode}');
  }

  /// ทำเครื่องหมาย reminder ว่าเสร็จ
  static Future<void> completeReminder(int reminderId) async {
    await http.post(Uri.parse('$_baseUrl/reminders/$reminderId/done'));
  }

  /// ส่ง mood
  static Future<void> sendMood({
    required String userId,
    required int score,
    String note = '',
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/mood'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'score': score,
        'note': note,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Send mood failed: ${response.statusCode}');
    }
  }

  /// ดึงประวัติ mood
  static Future<List<Map<String, dynamic>>> getMoodHistory(
    String userId, {
    int days = 7,
  }) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/mood/$userId?days=$days'),
    );

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list.cast<Map<String, dynamic>>();
    }
    throw Exception('Get mood history failed: ${response.statusCode}');
  }

  /// ดึง routines
  static Future<List<Map<String, dynamic>>> getRoutines(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/routines/$userId'),
    );

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list.cast<Map<String, dynamic>>();
    }
    throw Exception('Get routines failed: ${response.statusCode}');
  }

  /// สร้าง routine ใหม่
  static Future<Map<String, dynamic>> createRoutine({
    required String userId,
    required String title,
    String time = '',
    int points = 5,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/routines'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'title': title,
        'time': time,
        'points': points,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Create routine failed: ${response.statusCode}');
  }

  /// เช็คกิจวัตร (done)
  static Future<void> completeRoutine(int routineId) async {
    await http.post(Uri.parse('$_baseUrl/routines/$routineId/complete'));
  }

  /// ลบ routine
  static Future<void> deleteRoutine(int routineId) async {
    await http.delete(Uri.parse('$_baseUrl/routines/$routineId'));
  }

  /// ดึงสถิติผู้ใช้ (streak, points)
  static Future<Map<String, dynamic>> getUserStats(String userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/stats/$userId'),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return {'streak': 0, 'total_points': 0};
  }

  /// ดึง critical alerts สำหรับแสดง banner
  static Future<Map<String, dynamic>> getCriticalAlerts({int hours = 6}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/alerts/critical-summary?hours=$hours'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return {'count': 0, 'alerts': []};
  }

  /// อัพเดทการตั้งค่า
  static Future<void> updateSettings({
    required String userId,
    String? personality,
    String? wakeTime,
    String? sleepTime,
  }) async {
    final body = <String, dynamic>{'user_id': userId};
    if (personality != null) body['personality'] = personality;
    if (wakeTime != null) body['wake_time'] = wakeTime;
    if (sleepTime != null) body['sleep_time'] = sleepTime;

    await http.put(
      Uri.parse('$_baseUrl/settings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }
}
