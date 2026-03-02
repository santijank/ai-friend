/// fcm_service.dart — Firebase Cloud Messaging (Push Notifications)
/// ส่ง push notification จาก backend ตรงเวลา แม้ปิดแอป
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'local_storage.dart';

/// Background message handler — ต้องเป็น top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background message: ${message.notification?.title}');
  // Android จะแสดง notification อัตโนมัติจาก notification payload
  // ถ้าต้องการ custom handling เพิ่มได้ที่นี่
}

class FcmService {
  static final _messaging = FirebaseMessaging.instance;

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

    // ฟัง foreground messages → แสดง local notification
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
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

  /// แสดง local notification เมื่อ app อยู่ foreground
  /// (FCM ไม่แสดง notification เองตอน app เปิดอยู่)
  static void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    debugPrint('FCM foreground: ${notification.title}');

    final plugin = FlutterLocalNotificationsPlugin();
    plugin.show(
      message.hashCode,
      notification.title ?? '',
      notification.body ?? '',
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
      ),
    );
  }
}
