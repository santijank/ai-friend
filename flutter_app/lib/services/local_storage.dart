/// local_storage.dart — เก็บข้อมูลในเครื่องด้วย Hive
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/message.dart';

class LocalStorage {
  static late Box _userBox;
  static late Box _messageBox;
  static late Box _settingsBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    _userBox = await Hive.openBox('user');
    _messageBox = await Hive.openBox('messages');
    _settingsBox = await Hive.openBox('settings');
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

  // === Clear All ===

  static Future<void> clearAll() async {
    await _userBox.clear();
    await _messageBox.clear();
    await _settingsBox.clear();
  }
}
