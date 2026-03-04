/// fcm_service.dart — Firebase Cloud Messaging (Push Notifications)
/// ส่ง push notification จาก backend ตรงเวลา แม้ปิดแอป
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'local_storage.dart';

/// Notification details สำหรับ reminder — fullScreenIntent เปิดจอ + แสดงทับจอล็อค
const _reminderNotificationDetails = NotificationDetails(
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

/// Background message handler — ต้องเป็น top-level function
/// ทำงานใน isolate แยก เมื่อ FCM data message มาถึงขณะแอปปิด/จอดับ
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  debugPrint('FCM background: type=${data['type']}, body=${data['body']}');

  if (data['type'] == 'reminder') {
    final title = data['title'] ?? '🤖 ฟ้าเตือน~';
    final body = data['body'] ?? '';

    // Init plugin ใน isolate (ต้อง init ใหม่เพราะอยู่คนละ isolate กับ main)
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // สร้าง local notification + fullScreenIntent → ปลุกจอ + เปิดแอป
    await plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      _reminderNotificationDetails,
      payload: body,
    );
    debugPrint('✅ Background: created local notification with fullScreenIntent');
  }
}

class FcmService {
  static final _messaging = FirebaseMessaging.instance;

  /// Callback เมื่อได้รับ reminder ขณะ app เปิดอยู่ → เปิดหน้าเตือน + พูด
  static void Function(String message)? onReminderReceived;

  /// เริ่มต้น FCM — เรียกหลัง Firebase.initializeApp()
  static Future<void> init() async {
    // ขอ permission (iOS + Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission: ${settings.authorizationStatus}');

    // ลงทะเบียน background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // รับ FCM token
    final token = await _messaging.getToken();
    debugPrint('FCM token: ${token?.substring(0, 20)}...');

    if (token != null) {
      await _registerTokenWithBackend(token);
    }

    // ฟัง token refresh (เปลี่ยน token ใหม่ → ส่งให้ backend)
    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM token refreshed');
      _registerTokenWithBackend(newToken);
    });

    // ฟัง foreground messages → เปิดหน้าเตือน + พูด
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // เมื่อ user กด notification ตอน app อยู่ background → เปิดหน้าเตือน
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // เช็คว่าเปิด app จาก notification หรือเปล่า (terminated state)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      Future.delayed(const Duration(seconds: 1), () {
        _handleMessageOpenedApp(initialMessage);
      });
    }
  }

  /// ส่ง FCM token ให้ backend เก็บ
  static Future<void> _registerTokenWithBackend(String token) async {
    final userId = LocalStorage.userId;
    if (userId.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/devices/register-token'),
        headers: {'Content-Type': 'application/json'},
        body: '{"user_id": "$userId", "fcm_token": "$token"}',
      );
      if (response.statusCode == 200) {
        debugPrint('FCM token registered with backend');
      } else {
        debugPrint('FCM token registration failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('FCM token registration error: $e');
    }
  }

  /// Foreground: แอปเปิดอยู่ → เปิดหน้าเตือนเต็มจอ + ฟ้าพูดทันที
  static void _handleForegroundMessage(RemoteMessage message) {
    // อ่านจาก data (backend ส่ง data-only message)
    final data = message.data;
    final body = data['body'] ?? message.notification?.body ?? '';
    final title = data['title'] ?? message.notification?.title ?? '';

    if (body.isEmpty) return;
    debugPrint('FCM foreground: $title — $body');

    // ถ้ามี callback → เปิดหน้าเตือนเต็มจอ + ฟ้าพูด (ไม่ต้องกด notification)
    if (onReminderReceived != null) {
      onReminderReceived!(body);
      return;
    }

    // Fallback: แสดง notification (ถ้ายังไม่ได้ set callback)
    final plugin = FlutterLocalNotificationsPlugin();
    plugin.show(
      message.hashCode,
      title,
      body,
      _reminderNotificationDetails,
      payload: body,
    );
  }

  /// User กด notification จาก background → เปิดหน้าเตือน + ฟ้าพูด
  static void _handleMessageOpenedApp(RemoteMessage message) {
    final body = message.data['body'] ?? message.notification?.body ?? '';
    debugPrint('FCM opened app: $body');

    if (onReminderReceived != null && body.isNotEmpty) {
      onReminderReceived!(body);
    }
  }
}
