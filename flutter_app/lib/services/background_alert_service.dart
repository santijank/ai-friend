/// background_alert_service.dart — Background polling สำหรับ critical alerts
/// ใช้ WorkManager เช็ค backend ทุก ~15 นาที แม้ปิดแอป
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String _taskName = 'alertCheckTask';
const String _taskUniqueName = 'com.aifriend.alertCheck';
const String _seenAlertsKey = 'seen_alert_ids';

/// Top-level callback — ทำงานใน isolate แยก (ต้องเป็น top-level function)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _taskName) return true;

    final apiBaseUrl = inputData?['apiBaseUrl'] ?? '';
    if (apiBaseUrl.isEmpty) return true;

    try {
      final alertData = await _fetchAlerts(apiBaseUrl);
      if (alertData == null) return true;

      final alerts = (alertData['alerts'] as List?) ?? [];
      if (alerts.isEmpty) return true;

      // โหลด alert IDs ที่เคยแจ้งแล้ว
      final prefs = await SharedPreferences.getInstance();
      final seenIds = prefs.getStringList(_seenAlertsKey) ?? [];
      final seenSet = seenIds.toSet();

      // หา alerts ใหม่ที่ยังไม่เคยแจ้ง
      final newAlerts = <Map<String, dynamic>>[];
      for (final alert in alerts) {
        final id = alert['id']?.toString() ?? '';
        final title = alert['title']?.toString() ?? '';
        final key = '${id}_$title';
        if (id.isNotEmpty && !seenSet.contains(key)) {
          newAlerts.add(Map<String, dynamic>.from(alert));
          seenSet.add(key);
        }
      }

      if (newAlerts.isEmpty) return true;

      // แสดง notification สำหรับ alert ใหม่
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      for (final alert in newAlerts) {
        final id = (alert['id'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
        final title = alert['title'] ?? 'แจ้งเตือน';
        final severity = alert['severity'] ?? '';
        final alertType = alert['alert_type'] ?? '';

        String prefix = 'ข่าวด่วน';
        if (alertType == 'earthquake') prefix = 'แผ่นดินไหว';
        if (severity == 'critical') prefix = 'ภัยพิบัติ';

        await plugin.show(
          id,
          '$prefix: $title',
          alert['description']?.toString() ?? '',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'critical_alerts',
              'Critical Alerts',
              channelDescription: 'แจ้งเตือนแผ่นดินไหว ภัยพิบัติ ข่าวด่วน',
              importance: Importance.max,
              priority: Priority.max,
              playSound: true,
              enableVibration: true,
              enableLights: true,
              fullScreenIntent: true,
              category: AndroidNotificationCategory.alarm,
              visibility: NotificationVisibility.public,
            ),
          ),
        );
      }

      // บันทึก alert IDs ที่แจ้งแล้ว (เก็บแค่ 100 ตัวล่าสุด)
      final updatedList = seenSet.toList();
      if (updatedList.length > 100) {
        updatedList.removeRange(0, updatedList.length - 100);
      }
      await prefs.setStringList(_seenAlertsKey, updatedList);
    } catch (_) {
      // ล้มเหลว → ไม่ต้องทำอะไร รอรอบถัดไป
    }

    return true;
  });
}

/// Fetch alerts จาก backend (retry 1 ครั้ง, timeout 90 วินาที)
Future<Map<String, dynamic>?> _fetchAlerts(String apiBaseUrl) async {
  for (int attempt = 0; attempt < 2; attempt++) {
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/alerts/critical-summary?hours=1'))
          .timeout(const Duration(seconds: 90));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      if (attempt == 0) {
        await Future.delayed(const Duration(seconds: 10));
      }
    }
  }
  return null;
}

/// Service class สำหรับเริ่มต้นและจัดการ WorkManager
class BackgroundAlertService {
  /// เริ่ม background polling (เรียกจาก main.dart)
  static Future<void> initialize(String apiBaseUrl) async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      _taskUniqueName,
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      inputData: {'apiBaseUrl': apiBaseUrl},
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  /// หยุด background polling
  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(_taskUniqueName);
  }
}
