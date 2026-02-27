/// stt_service.dart — Speech-to-Text (พูดใส่แอป)
/// รองรับหา locale ภาษาไทยอัตโนมัติจากอุปกรณ์
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttService {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _isAvailable = false;
  static String _thaiLocaleId = 'th_TH'; // default, จะถูกอัพเดทตอน init

  static bool get isAvailable => _isAvailable;
  static bool get isListening => _speech.isListening;

  static Future<bool> init() async {
    _isAvailable = await _speech.initialize(
      onError: (error) => debugPrint('STT Error: ${error.errorMsg}'),
      onStatus: (status) => debugPrint('STT Status: $status'),
    );
    debugPrint('STT init: available=$_isAvailable');

    if (_isAvailable) {
      await _findThaiLocale();
    }

    return _isAvailable;
  }

  /// ค้นหา locale ภาษาไทยที่ดีที่สุดจากอุปกรณ์
  static Future<void> _findThaiLocale() async {
    try {
      final locales = await _speech.locales();
      debugPrint('STT available locales: ${locales.length}');

      // หา Thai locale — ลองหลายรูปแบบ
      for (final locale in locales) {
        final id = locale.localeId.toLowerCase();
        if (id.startsWith('th')) {
          _thaiLocaleId = locale.localeId;
          debugPrint('STT found Thai locale: $_thaiLocaleId (${locale.name})');
          return;
        }
      }

      // ถ้าไม่เจอ Thai → log warning
      debugPrint('STT WARNING: No Thai locale found! Using default: $_thaiLocaleId');
      debugPrint('STT available: ${locales.map((l) => l.localeId).take(10).toList()}');
    } catch (e) {
      debugPrint('STT findThaiLocale error: $e');
    }
  }

  static Future<void> startListening({
    required Function(String text) onResult,
    Function()? onDone,
    Function(String error)? onError,
    Duration? listenFor,
  }) async {
    if (!_isAvailable) {
      onError?.call('STT not available');
      return;
    }

    try {
      debugPrint('STT startListening with locale: $_thaiLocaleId');
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords);
          if (result.finalResult && onDone != null) {
            onDone();
          }
        },
        localeId: _thaiLocaleId,
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
        listenFor: listenFor ?? const Duration(seconds: 30),
      );
    } catch (e) {
      debugPrint('STT startListening error: $e');
      onError?.call(e.toString());
    }
  }

  static Future<void> stopListening() async {
    await _speech.stop();
  }
}
