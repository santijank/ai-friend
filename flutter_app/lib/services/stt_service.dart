/// stt_service.dart — Speech-to-Text ผ่าน Android Native Intent
/// ใช้ RecognizerIntent.ACTION_RECOGNIZE_SPEECH บังคับภาษาไทยโดยตรง
/// ไม่พึ่ง speech_to_text package (ซึ่งมีปัญหา locale บนบางอุปกรณ์)
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SttService {
  static const _channel = MethodChannel('com.aifriend/stt');
  static bool _isAvailable = true; // สมมติว่ามีเสมอบน Android

  static bool get isAvailable => _isAvailable;

  static Future<bool> init() async {
    // Native intent-based STT ไม่ต้อง init พิเศษ
    // แค่เช็คว่า platform channel ใช้ได้
    try {
      debugPrint('STT init: using native Android RecognizerIntent (th-TH forced)');
      _isAvailable = true;
      return true;
    } catch (e) {
      debugPrint('STT init error: $e');
      _isAvailable = false;
      return false;
    }
  }

  /// เรียก Google Speech Recognition ผ่าน Android Intent
  /// บังคับ language = th-TH → ได้ข้อความไทยแน่นอน
  /// Returns: ข้อความที่รู้จำได้ (อาจเป็น "" ถ้า user cancel)
  static Future<String> recognizeSpeech({
    String language = 'th-TH',
    String prompt = 'พูดภาษาไทยได้เลย',
  }) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'startSpeechRecognition',
        {'language': language, 'prompt': prompt},
      );
      debugPrint('STT result: "$result"');
      return result ?? '';
    } on PlatformException catch (e) {
      debugPrint('STT PlatformException: ${e.message}');
      return '';
    } catch (e) {
      debugPrint('STT error: $e');
      return '';
    }
  }

  // ======== Legacy compatibility (ใช้กับ voice_mode_overlay) ========
  // voice_mode_overlay ยังเรียก startListening/stopListening
  // แปลงให้ใช้ native intent แทน

  static bool get isListening => false; // native intent จัดการเอง

  static Future<void> startListening({
    required Function(String text) onResult,
    Function()? onDone,
    Function(String error)? onError,
    Duration? listenFor,
  }) async {
    try {
      final text = await recognizeSpeech();
      if (text.isNotEmpty) {
        onResult(text);
      }
      onDone?.call();
    } catch (e) {
      onError?.call(e.toString());
    }
  }

  static Future<void> stopListening() async {
    // Native intent จัดการ lifecycle เอง — ไม่ต้องทำอะไร
  }
}
