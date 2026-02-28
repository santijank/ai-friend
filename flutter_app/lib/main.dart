/// main.dart — จุดเริ่มต้นแอป ฟ้า AI Friend
import 'package:flutter/material.dart';
import 'config.dart';
import 'services/local_storage.dart';
import 'services/notification_service.dart';
import 'services/background_alert_service.dart';
import 'services/tts_service.dart';
import 'services/stt_service.dart';
import 'services/theme_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // เริ่มต้น services
  await LocalStorage.init();
  await NotificationService.init();
  await TtsService.init();
  await SttService.init();

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
