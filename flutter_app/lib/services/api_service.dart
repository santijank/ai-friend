/// api_service.dart — เชื่อมต่อ Backend API
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

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

  /// ส่งข้อความแชท
  static Future<Map<String, dynamic>> sendMessage({
    required String userId,
    required String message,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'message': message,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Chat failed: ${response.statusCode}');
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
