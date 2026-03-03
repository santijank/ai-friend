/// notification_service.dart — จัดการ Local Notifications (พร้อมเสียง)
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:android_intent_plus/android_intent.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Timer-based scheduling (ทำงาน 100% ขณะแอปเปิด)
  static final Map<int, Timer> _activeTimers = {};

  /// Callback เมื่อ user กดที่ notification — payload = reminder message
  static void Function(String payload)? onNotificationTap;

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
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty && onNotificationTap != null) {
          onNotificationTap!(payload);
        }
      },
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

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders_v2',
      'Reminders',
      channelDescription: 'การแจ้งเตือนจากฟ้า',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    ),
  );

  /// ตั้งเตือนครั้งเดียว — ใช้ Timer (primary) + zonedSchedule (backup)
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

    final delay = scheduledTime.difference(DateTime.now());
    debugPrint('Scheduling: "$body" in ${delay.inSeconds}s (${scheduledTime.toIso8601String()})');

    // === PRIMARY: Timer + show() — ทำงาน 100% ขณะแอปเปิด ===
    _activeTimers[id]?.cancel();
    _activeTimers[id] = Timer(delay, () async {
      try {
        await _plugin.show(id, title, body, _reminderDetails, payload: body);
        debugPrint('✅ Timer notification fired: $body');
      } catch (e) {
        debugPrint('❌ Timer notification failed: $e');
      }
      _activeTimers.remove(id);
    });
    debugPrint('⏱️ Timer set for ${delay.inSeconds}s');

    // === BACKUP: zonedSchedule — อาจทำงานได้ถ้าแอปปิด (ขึ้นกับมือถือ) ===
    try {
      final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
      await _plugin.zonedSchedule(
        id, title, body, tzTime, _reminderDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('✅ Also scheduled zonedSchedule as backup');
    } catch (e) {
      debugPrint('⚠️ zonedSchedule backup failed (non-fatal): $e');
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

  /// ทดสอบระบบแจ้งเตือนทีละ component — return ผลลัพธ์เป็น text
  static Future<String> runDiagnostic() async {
    final buf = StringBuffer();

    // 1. Test timezone
    try {
      buf.writeln('1) tz.local = ${tz.local.name}');
    } catch (e) {
      buf.writeln('1) tz.local FAIL: $e');
    }

    // 2. Test TZDateTime creation
    try {
      final testTime = DateTime.now().add(const Duration(minutes: 5));
      final tzTime = tz.TZDateTime.from(testTime, tz.local);
      buf.writeln('2) TZDateTime.from() OK → $tzTime');
    } catch (e) {
      buf.writeln('2) TZDateTime.from() FAIL: $e');
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

    // 3. Test plugin.show() — immediate notification
    try {
      await _plugin.show(99990, 'Test', 'ทดสอบ show()', details);
      buf.writeln('3) plugin.show() OK');
    } catch (e) {
      buf.writeln('3) plugin.show() FAIL: $e');
    }

    // 4. Test zonedSchedule exact
    try {
      final futureTime = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 2));
      await _plugin.zonedSchedule(
        99991, 'Test Exact', 'ทดสอบ exact alarm', futureTime, details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      buf.writeln('4) zonedSchedule exact OK');
      await _plugin.cancel(99991); // ยกเลิกทันทีหลังทดสอบ
    } catch (e) {
      buf.writeln('4) zonedSchedule exact FAIL: $e');
    }

    // 5. Test zonedSchedule inexact
    try {
      final futureTime = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 2));
      await _plugin.zonedSchedule(
        99992, 'Test Inexact', 'ทดสอบ inexact alarm', futureTime, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      buf.writeln('5) zonedSchedule inexact OK');
      await _plugin.cancel(99992);
    } catch (e) {
      buf.writeln('5) zonedSchedule inexact FAIL: $e');
    }

    // 6. Check pending notifications count
    try {
      final pending = await _plugin.pendingNotificationRequests();
      buf.writeln('6) Pending notifications: ${pending.length}');
      for (final p in pending) {
        buf.writeln('   - id=${p.id} "${p.title}"');
      }
    } catch (e) {
      buf.writeln('6) pendingNotifications FAIL: $e');
    }

    // 7. Check notification permission
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final enabled = await android.areNotificationsEnabled();
        buf.writeln('7) Notification permission: ${enabled == true ? "GRANTED ✅" : "DENIED ❌"}');
      } else {
        buf.writeln('7) Notification permission: N/A (not Android)');
      }
    } catch (e) {
      buf.writeln('7) Notification permission check FAIL: $e');
    }

    // 8. Check exact alarm permission
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final canExact = await android.canScheduleExactNotifications();
        buf.writeln('8) Exact alarm permission: ${canExact == true ? "GRANTED ✅" : "DENIED ❌"}');
      } else {
        buf.writeln('8) Exact alarm permission: N/A (not Android)');
      }
    } catch (e) {
      buf.writeln('8) Exact alarm check FAIL: $e');
    }

    // 9. Check battery optimization status
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // ใช้ Android intent เพื่อเปิดหน้าตั้งค่า battery
        buf.writeln('9) Battery optimization: ตรวจสอบโดย request exemption ตอนเปิดแอป');
        buf.writeln('   → ถ้ายังไม่ได้กด "อนุญาต" ให้กดที่หน้า popup');
      } else {
        buf.writeln('9) Battery optimization: N/A (not Android)');
      }
    } catch (e) {
      buf.writeln('9) Battery optimization check FAIL: $e');
    }

    return buf.toString();
  }

  /// ตั้งเตือนทดสอบจริง 10 วินาที — ใช้ Timer (ต้องมา notification จริง)
  static Future<String> scheduleTestNotification() async {
    try {
      // ใช้ Timer + show() (เชื่อถือได้ 100% ขณะแอปเปิด)
      _activeTimers[88888]?.cancel();
      _activeTimers[88888] = Timer(const Duration(seconds: 10), () async {
        try {
          await _plugin.show(
            88888,
            '🔔 ทดสอบสำเร็จ!',
            'ระบบแจ้งเตือนทำงานแล้ว! (Timer-based)',
            _reminderDetails,
          );
          debugPrint('✅ Test timer notification fired!');
        } catch (e) {
          debugPrint('❌ Test timer notification failed: $e');
        }
        _activeTimers.remove(88888);
      });

      final now = DateTime.now();
      final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}:${(now.second + 10).toString().padLeft(2, '0')}';
      return 'ตั้ง Timer แล้ว! จะมี notification ใน 10 วินาที (~$timeStr)\n'
          'ใช้ Timer+show() (ไม่พึ่ง AlarmManager)\n'
          'เปิดแอปค้างไว้ รอ 10 วินาที...';
    } catch (e) {
      return 'ตั้งเวลาไม่ได้: $e';
    }
  }

  /// ขอยกเว้น Battery Optimization (Doze Mode) — เปิด system dialog
  static Future<void> requestBatteryOptimizationExemption() async {
    try {
      if (defaultTargetPlatform != TargetPlatform.android) return;

      const intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:com.aifriend.ai_friend',
      );
      await intent.launch();
      debugPrint('✅ Battery optimization exemption dialog launched');
    } catch (e) {
      debugPrint('⚠️ Battery optimization request failed (non-fatal): $e');
    }
  }

  /// ล้าง notification ที่ค้าง (เลยเวลาแล้วแต่ไม่ยิง) แล้ว cancel ทั้งหมด
  static Future<int> cleanStalePendingNotifications() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      if (pending.isEmpty) return 0;

      // cancel ทุก id ที่เป็น test (99990-99992, 88888) ไม่นับ
      final staleIds = pending
          .where((p) => p.id != 99990 && p.id != 99991 && p.id != 99992 && p.id != 88888)
          .map((p) => p.id)
          .toList();

      for (final id in staleIds) {
        await _plugin.cancel(id);
      }
      debugPrint('🧹 Cleaned ${staleIds.length} stale pending notifications');
      return staleIds.length;
    } catch (e) {
      debugPrint('Clean stale notifications error: $e');
      return 0;
    }
  }
}
