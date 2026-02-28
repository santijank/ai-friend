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
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        // ขอ notification permission (Android 13+)
        final granted = await android.requestNotificationsPermission();
        debugPrint('Notification permission: $granted');

        // ขอ exact alarm permission (Android 12+) — ไม่ fatal ถ้าไม่ได้
        try {
          final exactAlarm = await android.requestExactAlarmsPermission();
          debugPrint('Exact alarm permission: $exactAlarm');
        } catch (e) {
          debugPrint('Exact alarm permission request failed (non-fatal): $e');
        }

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
    } catch (e) {
      debugPrint('Permission request error: $e');
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

  /// ตั้งเตือนครั้งเดียว (พร้อมเสียง) — ไม่ throw exception
  /// ใช้ 3-level fallback: exact → inexact → show ทันที
  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    // Safety: ถ้าเวลาเป็นอดีต → skip ไม่ throw
    if (scheduledTime.isBefore(DateTime.now())) {
      debugPrint('⚠️ scheduledTime is in the past, skipping notification');
      return;
    }

    const details = NotificationDetails(
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
    );

    // แปลง timezone
    tz.TZDateTime tzTime;
    try {
      tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
      debugPrint('Scheduling: "$body" at $tzTime (tz.local=${tz.local.name})');
    } catch (e) {
      debugPrint('⚠️ TZDateTime conversion failed: $e — using show() fallback');
      // ถ้าแปลง timezone ไม่ได้ → แสดง notification ทันทีแทน
      try {
        await _plugin.show(id, title, body, details);
        debugPrint('✅ Showed immediate notification (timezone fallback)');
      } catch (e2) {
        debugPrint('❌ Even immediate notification failed: $e2');
      }
      return;
    }

    // Level 1: exact alarm
    try {
      await _plugin.zonedSchedule(
        id, title, body, tzTime, details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('✅ Scheduled with exactAllowWhileIdle');
      return;
    } catch (e) {
      debugPrint('⚠️ Exact alarm failed: $e');
    }

    // Level 2: inexact alarm
    try {
      await _plugin.zonedSchedule(
        id, title, body, tzTime, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('✅ Scheduled with inexactAllowWhileIdle');
      return;
    } catch (e) {
      debugPrint('⚠️ Inexact alarm failed: $e');
    }

    // Level 3: immediate notification (ultimate fallback)
    try {
      await _plugin.show(id, title, '(จะเตือนเวลาถึง) $body', details);
      debugPrint('✅ Showed immediate notification as fallback');
    } catch (e) {
      debugPrint('❌ Even immediate notification failed: $e');
    }
  }

  /// ตั้งเตือนทุกวัน (เช่น ทักทายตอนเช้า) — ไม่ throw exception
  static Future<void> scheduleDailyReminder({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    const details = NotificationDetails(
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
    );

    tz.TZDateTime scheduled;
    try {
      final now = tz.TZDateTime.now(tz.local);
      scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }
      debugPrint('Daily reminder: "$body" at $hour:$minute (next: $scheduled)');
    } catch (e) {
      debugPrint('⚠️ Daily TZDateTime creation failed: $e');
      return;
    }

    // Level 1: exact alarm
    try {
      await _plugin.zonedSchedule(
        id, title, body, scheduled, details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('✅ Daily scheduled with exactAllowWhileIdle');
      return;
    } catch (e) {
      debugPrint('⚠️ Daily exact alarm failed: $e');
    }

    // Level 2: inexact alarm
    try {
      await _plugin.zonedSchedule(
        id, title, body, scheduled, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint('✅ Daily scheduled with inexactAllowWhileIdle');
      return;
    } catch (e) {
      debugPrint('⚠️ Daily inexact alarm failed: $e');
    }

    // Level 3: immediate fallback
    try {
      await _plugin.show(id, title, body, details);
      debugPrint('✅ Daily showed immediate notification as fallback');
    } catch (e) {
      debugPrint('❌ Daily even immediate notification failed: $e');
    }
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
