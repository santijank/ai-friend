/// main.dart — จุดเริ่มต้นแอป ฟ้า AI Friend
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config.dart';
import 'services/local_storage.dart';
import 'services/notification_service.dart';
import 'services/fcm_service.dart';
import 'services/background_alert_service.dart';
import 'services/tts_service.dart';
import 'services/stt_service.dart';
import 'services/theme_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reminder_alert_screen.dart';

/// Global navigator key — ใช้ navigate จาก notification/FCM callback
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (ต้อง init ก่อน FCM)
  await Firebase.initializeApp();

  // เริ่มต้น services
  await LocalStorage.init();
  await NotificationService.init();
  await NotificationService.requestPermission();
  await NotificationService.requestBatteryOptimizationExemption();
  await NotificationService.cleanStalePendingNotifications();
  await FcmService.init();
  await TtsService.init();
  await SttService.init();

  // ตั้ง callback: กด notification → เปิดหน้าเตือน + ฟ้าพูด
  NotificationService.onNotificationTap = (payload) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ReminderAlertScreen(message: payload),
      ),
    );
  };

  // ตั้ง FCM callback: foreground message → เปิดหน้าเตือน + ฟ้าพูด
  FcmService.onReminderReceived = (message) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => ReminderAlertScreen(message: message),
      ),
    );
  };

  // ตั้ง FCM callback: stock alert → แสดง snackbar + พูด
  FcmService.onStockAlertReceived = (title, body) {
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('$title\n$body'),
          backgroundColor: body.contains('ขึ้น') ? Colors.green : Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    // พูดแจ้งเตือนหุ้น
    TtsService.speak(body);
  };

  // เริ่ม background alert polling (แจ้งเตือนแม้ปิดแอป)
  await BackgroundAlertService.initialize(AppConfig.apiBaseUrl);

  runApp(const AIFriendApp());
}

class AIFriendApp extends StatelessWidget {
  const AIFriendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'ฟ้า AI Friend',
          debugShowCheckedModeBanner: false,
          theme: ThemeService().theme,
          home: LocalStorage.isRegistered
              ? const HomeScreen()
              : const OnboardingScreen(),
        );
      },
    );
  }
}
