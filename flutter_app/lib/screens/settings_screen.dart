/// settings_screen.dart — หน้าตั้งค่า
import 'package:flutter/material.dart';
import '../services/local_storage.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/background_alert_service.dart';
import '../services/tts_service.dart';
import '../services/auth_service.dart';
import '../config.dart';
import 'mood_history_screen.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _personality;
  late String _wakeTime;
  late String _sleepTime;
  late bool _morningNotif;
  late bool _nightNotif;
  late bool _autoSpeak;
  late bool _darkMode;
  late bool _criticalAlerts;

  @override
  void initState() {
    super.initState();
    _personality = LocalStorage.personality;
    _wakeTime = LocalStorage.wakeTime;
    _sleepTime = LocalStorage.sleepTime;
    _morningNotif = LocalStorage.morningNotification;
    _nightNotif = LocalStorage.nightNotification;
    _autoSpeak = LocalStorage.autoSpeak;
    _darkMode = LocalStorage.darkMode;
    _criticalAlerts = LocalStorage.criticalAlertNotification;
  }

  final _personalityNames = {
    'friendly': 'เพื่อนสนิท 😎',
    'caring': 'พี่สาวอบอุ่น 🌸',
    'cheerful': 'น้องร่าเริง 🧸',
    'professional': 'พี่เลี้ยงมือโปร 🎩',
  };

  Future<void> _changePersonality() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('เลือกบุคลิก AI'),
        children: _personalityNames.entries.map((e) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, e.key),
            child: Row(
              children: [
                if (e.key == _personality)
                  const Icon(Icons.check, color: Color(0xFF6C9BCF)),
                if (e.key != _personality) const SizedBox(width: 24),
                const SizedBox(width: 8),
                Text(e.value, style: const TextStyle(fontSize: 16)),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (selected != null && selected != _personality) {
      setState(() => _personality = selected);
      await LocalStorage.saveSetting('personality', selected);
      await ApiService.updateSettings(
        userId: LocalStorage.userId,
        personality: selected,
      );
    }
  }

  Future<void> _changeTime(String type) async {
    final current = type == 'wake' ? _wakeTime : _sleepTime;
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 7,
      minute: int.tryParse(parts[1]) ?? 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );

    if (picked != null) {
      final timeStr =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';

      if (type == 'wake') {
        setState(() => _wakeTime = timeStr);
        await LocalStorage.saveSetting('wakeTime', timeStr);
        await ApiService.updateSettings(
          userId: LocalStorage.userId,
          wakeTime: timeStr,
        );
        // อัพเดท notification เช้า
        if (_morningNotif) {
          await NotificationService.scheduleDailyReminder(
            id: 1,
            title: '☀️ ฟ้าทักมา~',
            body: 'อรุณสวัสดิ์ ${LocalStorage.userName}! วันนี้จะเป็นวันที่ดีนะ!',
            hour: picked.hour,
            minute: picked.minute,
          );
        }
      } else {
        setState(() => _sleepTime = timeStr);
        await LocalStorage.saveSetting('sleepTime', timeStr);
        await ApiService.updateSettings(
          userId: LocalStorage.userId,
          sleepTime: timeStr,
        );
      }
    }
  }

  Future<void> _confirmDeleteData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบข้อมูลทั้งหมด'),
        content: const Text(
          'ข้อมูลทั้งหมดรวมถึงประวัติแชท กิจวัตร และการตั้งค่าจะถูกลบ\nคุณแน่ใจหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบทั้งหมด'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.logout();
      await NotificationService.cancelAll();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'ตั้งค่า',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // === โปรไฟล์ ===
            _buildSectionHeader('👤 โปรไฟล์'),
            _buildInfoTile('ชื่อ', LocalStorage.userName),
            _buildTapTile(
              'บุคลิก AI',
              _personalityNames[_personality] ?? _personality,
              _changePersonality,
            ),

            const Divider(height: 32),

            // === เวลา ===
            _buildSectionHeader('⏰ เวลา'),
            _buildTapTile('เวลาตื่น', _wakeTime, () => _changeTime('wake')),
            _buildTapTile('เวลานอน', _sleepTime, () => _changeTime('sleep')),

            const Divider(height: 32),

            // === การแจ้งเตือน ===
            _buildSectionHeader('🔔 การแจ้งเตือน'),
            SwitchListTile(
              title: const Text('เตือนเช้า'),
              subtitle: Text('ทุกวันเวลา $_wakeTime'),
              value: _morningNotif,
              onChanged: (val) async {
                setState(() => _morningNotif = val);
                await LocalStorage.saveSetting('morningNotification', val);
                if (val) {
                  final parts = _wakeTime.split(':');
                  await NotificationService.scheduleDailyReminder(
                    id: 1,
                    title: '☀️ ฟ้าทักมา~',
                    body: 'อรุณสวัสดิ์ ${LocalStorage.userName}!',
                    hour: int.parse(parts[0]),
                    minute: int.parse(parts[1]),
                  );
                } else {
                  await NotificationService.cancel(1);
                }
              },
            ),
            SwitchListTile(
              title: const Text('เตือนก่อนนอน'),
              subtitle: Text('ทุกวันเวลา $_sleepTime'),
              value: _nightNotif,
              onChanged: (val) async {
                setState(() => _nightNotif = val);
                await LocalStorage.saveSetting('nightNotification', val);
                if (val) {
                  final parts = _sleepTime.split(':');
                  await NotificationService.scheduleDailyReminder(
                    id: 2,
                    title: '🌙 ฟ้ามาสรุปวัน~',
                    body: 'มาดูกันว่าวันนี้ทำอะไรได้บ้าง!',
                    hour: int.parse(parts[0]),
                    minute: int.parse(parts[1]),
                  );
                } else {
                  await NotificationService.cancel(2);
                }
              },
            ),
            SwitchListTile(
              title: const Text('แจ้งเตือนภัยพิบัติ'),
              subtitle: const Text('แผ่นดินไหว ภัยธรรมชาติ ข่าวด่วน (มีเสียง)'),
              value: _criticalAlerts,
              onChanged: (val) async {
                setState(() => _criticalAlerts = val);
                await LocalStorage.saveSetting('criticalAlertNotification', val);
                if (val) {
                  await BackgroundAlertService.initialize(AppConfig.apiBaseUrl);
                } else {
                  await BackgroundAlertService.cancel();
                }
              },
            ),

            const Divider(height: 32),

            // === เสียง ===
            _buildSectionHeader('🔊 เสียง'),
            SwitchListTile(
              title: const Text('AI พูดอัตโนมัติ'),
              subtitle: const Text('เปิดเสียงเมื่อ AI ตอบ'),
              value: _autoSpeak,
              onChanged: (val) async {
                setState(() => _autoSpeak = val);
                await LocalStorage.saveSetting('autoSpeak', val);
                if (!val) await TtsService.stop();
              },
            ),

            const Divider(height: 32),

            // === อารมณ์ ===
            _buildSectionHeader('💭 อารมณ์'),
            ListTile(
              title: const Text('ดูประวัติอารมณ์'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MoodHistoryScreen(),
                  ),
                );
              },
            ),

            const Divider(height: 32),

            // === ข้อมูล ===
            _buildSectionHeader('🗑️ ข้อมูล'),
            ListTile(
              title: const Text(
                'ลบข้อมูลทั้งหมด',
                style: TextStyle(color: Colors.red),
              ),
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              onTap: _confirmDeleteData,
            ),

            const SizedBox(height: 32),
            const Center(
              child: Text(
                'ฟ้า AI Friend v${AppConfig.appVersion}',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color(0xFF6C9BCF),
        ),
      ),
    );
  }

  Widget _buildInfoTile(String title, String value) {
    return ListTile(
      title: Text(title),
      trailing: Text(
        value,
        style: const TextStyle(color: Colors.grey, fontSize: 15),
      ),
    );
  }

  Widget _buildTapTile(String title, String value, VoidCallback onTap) {
    return ListTile(
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(color: Colors.grey, fontSize: 15),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: onTap,
    );
  }
}
