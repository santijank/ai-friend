/// thai_stt_dialog.dart — Dialog แนะนำผู้ใช้เปิดภาษาไทยสำหรับ Speech Recognition
import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

/// แสดง dialog แนะนำผู้ใช้เปิด Thai speech recognition
/// Returns true ถ้าผู้ใช้กด "ลองพูดอังกฤษ" (ดำเนินการต่อ)
/// Returns false/null ถ้าปิด dialog (ยกเลิก)
Future<bool?> showThaiSttDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.language, color: Color(0xFF6C9BCF)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'ระบบเสียงภาษาไทยยังไม่พร้อม',
              style: TextStyle(fontSize: 17),
            ),
          ),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'กรุณาดาวน์โหลดภาษาไทยสำหรับการพูด:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          Text('1. กด "เปิดตั้งค่า" ข้างล่าง'),
          SizedBox(height: 4),
          Text('2. หา "ภาษา" หรือ "Languages"'),
          SizedBox(height: 4),
          Text('3. เพิ่ม/ดาวน์โหลด "ภาษาไทย"'),
          SizedBox(height: 4),
          Text('4. กลับมาที่แอปแล้วลองใหม่'),
          SizedBox(height: 16),
          Text(
            'หรือลอง: Google app → ตั้งค่า → เสียง → ภาษา → เพิ่มภาษาไทย',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('ลองพูดเลย'),
        ),
        FilledButton.icon(
          onPressed: () {
            _openVoiceSettings();
            Navigator.pop(ctx, false);
          },
          icon: const Icon(Icons.settings, size: 18),
          label: const Text('เปิดตั้งค่า'),
        ),
      ],
    ),
  );
}

/// เปิดหน้าตั้งค่า Voice Input ของ Android โดยตรง
void _openVoiceSettings() {
  if (defaultTargetPlatform != TargetPlatform.android) return;

  try {
    // ลองเปิดหน้า Voice Input settings ก่อน
    const intent = AndroidIntent(
      action: 'com.android.settings.VOICE_INPUT_SETTINGS',
    );
    intent.launch().catchError((_) {
      // fallback: เปิดหน้า Language & Input settings
      const fallbackIntent = AndroidIntent(
        action: 'android.settings.INPUT_METHOD_SETTINGS',
      );
      fallbackIntent.launch().catchError((_) {
        // fallback สุดท้าย: เปิดหน้า Settings หลัก
        const settingsIntent = AndroidIntent(
          action: 'android.settings.SETTINGS',
        );
        settingsIntent.launch();
      });
    });
  } catch (_) {
    // ignore errors
  }
}
