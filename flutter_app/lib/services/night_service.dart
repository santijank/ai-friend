/// night_service.dart — ดึงข้อความสรุปก่อนนอนจาก Backend
import 'local_storage.dart';
import 'notification_service.dart';

class NightService {
  /// ตั้ง notification สรุปก่อนนอน
  static Future<void> setupNightWrap() async {
    if (!LocalStorage.nightNotification) return;

    final parts = LocalStorage.sleepTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 23;
    final minute = int.tryParse(parts[1]) ?? 0;

    await NotificationService.scheduleDailyReminder(
      id: 2,
      title: '🌙 ฟ้ามาสรุปวัน~',
      body: 'มาดูกันว่าวันนี้ทำอะไรได้บ้าง ${LocalStorage.userName}!',
      hour: hour,
      minute: minute,
    );
  }
}
