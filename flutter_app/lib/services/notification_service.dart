/// notification_service.dart — จัดการ Local Notifications (พร้อมเสียง)
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // ตั้ง timezone เป็น Bangkok (สำคัญมาก! ถ้าไม่ตั้ง จะใช้ UTC)
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // สร้าง notification channels ล่วงหน้า (Android 8.0+)
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      // Channel สำหรับ critical alerts — เสียงดังสุด + ปลุกจอ
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'critical_alerts',
          'Critical Alerts',
          description: 'แจ้งเตือนแผ่นดินไหว ภัยพิบัติ ข่าวด่วน',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        ),
      );
      // Channel สำหรับ reminders — เสียงปกติ
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'reminders_v2',
          'Reminders',
          description: 'การแจ้งเตือนจากฟ้า',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      // Channel สำหรับ daily — ทักทายเช้า/ค่ำ
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'daily_v2',
          'Daily Reminders',
          description: 'ทักทายตอนเช้าและสรุปตอนค่ำ',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }
  }

  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      // ขอ notification permission (Android 13+)
      final granted = await android.requestNotificationsPermission();
      debugPrint('Notification permission: $granted');

      // ขอ exact alarm permission (Android 12+)
      final exactAlarm = await android.requestExactAlarmsPermission();
      debugPrint('Exact alarm permission: $exactAlarm');

      return granted ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

  /// แสดง critical alert ทันที (พร้อมเสียง + ปลุกจอ)
  static Future<void> showCriticalAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
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
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// ตั้งเตือนครั้งเดียว (พร้อมเสียง)
  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
    debugPrint('Scheduling notification: "$body" at $tzTime (tz.local=${tz.local.name})');

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders_v2',
          'Reminders',
          channelDescription: 'การแจ้งเตือนจากฟ้า',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAndAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// ตั้งเตือนทุกวัน (เช่น ทักทายตอนเช้า) — พร้อมเสียง
  static Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_v2',
          'Daily Reminders',
          channelDescription: 'ทักทายตอนเช้าและสรุปตอนค่ำ',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAndAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// ยกเลิก notification
  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  /// ยกเลิกทั้งหมด
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
