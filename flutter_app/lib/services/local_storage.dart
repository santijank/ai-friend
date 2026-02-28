/// local_storage.dart — เก็บข้อมูลในเครื่องด้วย Hive
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/message.dart';

class LocalStorage {
  static late Box _userBox;
  static late Box _messageBox;
  static late Box _settingsBox;
  static late Box _reminderBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    _userBox = await Hive.openBox('user');
    _messageBox = await Hive.openBox('messages');
    _settingsBox = await Hive.openBox('settings');
    _reminderBox = await Hive.openBox('reminders');
  }

  // === User ===

  static bool get isRegistered => _userBox.get('userId') != null;

  static String get userId => _userBox.get('userId', defaultValue: '');
  static String get userName => _userBox.get('userName', defaultValue: '');
  static String get personality =>
      _userBox.get('personality', defaultValue: 'friendly');

  static Future<void> saveUser({
    required String userId,
    required String name,
    required String personality,
  }) async {
    await _userBox.put('userId', userId);
    await _userBox.put('userName', name);
    await _userBox.put('personality', personality);
  }

  // === Messages ===

  static List<Message> getMessages() {
    final raw = _messageBox.get('history', defaultValue: <String>[]);
    final list = (raw as List).cast<String>();
    return list.map((json) => Message.fromJson(jsonDecode(json))).toList();
  }

  static Future<void> saveMessage(Message message) async {
    final list = _messageBox.get('history', defaultValue: <String>[]);
    final messages = (list as List).cast<String>();
    messages.add(jsonEncode(message.toJson()));
    // เก็บแค่ 200 ข้อความล่าสุด
    if (messages.length > 200) {
      messages.removeRange(0, messages.length - 200);
    }
    await _messageBox.put('history', messages);
  }

  static Future<void> clearMessages() async {
    await _messageBox.put('history', <String>[]);
  }

  // === Settings ===

  static String get wakeTime =>
      _settingsBox.get('wakeTime', defaultValue: '07:00');
  static String get sleepTime =>
      _settingsBox.get('sleepTime', defaultValue: '23:00');
  static bool get autoSpeak =>
      _settingsBox.get('autoSpeak', defaultValue: true);
  static bool get darkMode =>
      _settingsBox.get('darkMode', defaultValue: false);
  static String get themeColor =>
      _settingsBox.get('themeColor', defaultValue: 'blue');
  static bool get morningNotification =>
      _settingsBox.get('morningNotification', defaultValue: true);
  static bool get nightNotification =>
      _settingsBox.get('nightNotification', defaultValue: true);
  static bool get criticalAlertNotification =>
      _settingsBox.get('criticalAlertNotification', defaultValue: true);

  static Future<void> saveSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  // === Seen Alerts (ไม่แสดง alert ซ้ำ) ===

  static List<String> get seenAlertIds {
    final raw = _settingsBox.get('seenAlertIds', defaultValue: <String>[]);
    return (raw as List).cast<String>();
  }

  static Future<void> saveSeenAlertIds(List<String> ids) async {
    await _settingsBox.put('seenAlertIds', ids);
  }

  // === Reminders (เก็บในเครื่อง ไม่หายแม้ backend reset) ===

  /// บันทึก reminder ลงเครื่อง (resilient — ไม่ throw)
  static Future<void> saveReminder({
    required String message,
    required String remindAt,
  }) async {
    final newEntry = {
      'message': message,
      'remind_at': remindAt,
      'created_at': DateTime.now().toIso8601String(),
    };
    try {
      final reminders = getLocalReminders();
      reminders.add(newEntry);
      await _reminderBox.put(
        'list',
        reminders.map((r) => jsonEncode(r)).toList(),
      );
    } catch (e) {
      debugPrint('saveReminder error: $e — trying fresh save');
      // ถ้าข้อมูลเก่าเสีย → clear แล้ว save เฉพาะตัวใหม่
      try {
        await _reminderBox.put('list', [jsonEncode(newEntry)]);
      } catch (e2) {
        debugPrint('saveReminder fresh save also failed: $e2');
      }
    }
  }

  /// ดึง reminder ทั้งหมดจากเครื่อง (resilient — ไม่ throw, return [] ถ้ามีปัญหา)
  static List<Map<String, dynamic>> getLocalReminders() {
    try {
      final raw = _reminderBox.get('list', defaultValue: <dynamic>[]);
      if (raw is! List) return [];
      final result = <Map<String, dynamic>>[];
      for (final item in raw) {
        try {
          if (item is String) {
            result.add(jsonDecode(item) as Map<String, dynamic>);
          }
        } catch (_) {
          // skip corrupted entries
        }
      }
      return result;
    } catch (e) {
      debugPrint('getLocalReminders error: $e');
      return [];
    }
  }

  /// ดึงเฉพาะ reminder ที่ยังไม่หมดเวลา
  static List<Map<String, dynamic>> getPendingReminders() {
    final now = DateTime.now();
    return getLocalReminders().where((r) {
      try {
        final remindAt = r['remind_at'];
        if (remindAt is! String) return false;
        final dt = DateTime.parse(remindAt.replaceAll(' ', 'T'));
        return dt.isAfter(now);
      } catch (_) {
        return false;
      }
    }).toList();
  }

  /// ลบ reminder ที่หมดเวลาแล้ว
  static Future<void> cleanExpiredReminders() async {
    try {
      final pending = getPendingReminders();
      await _reminderBox.put(
        'list',
        pending.map((r) => jsonEncode(r)).toList(),
      );
    } catch (e) {
      debugPrint('cleanExpiredReminders error: $e');
    }
  }

  // === Clear All ===

  static Future<void> clearAll() async {
    await _userBox.clear();
    await _messageBox.clear();
    await _settingsBox.clear();
    await _reminderBox.clear();
  }
}
