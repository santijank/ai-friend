/// stt_service.dart — Speech-to-Text (พูดใส่แอป)
/// รองรับหา locale ภาษาไทยอัตโนมัติจากอุปกรณ์
/// แสดง dialog แนะนำถ้าไม่มี Thai speech recognition
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttService {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _isAvailable = false;
  static bool _hasThaiLocale = false;
  static String _thaiLocaleId = 'th_TH';
  static List<String> _allLocaleIds = [];

  static bool get isAvailable => _isAvailable;
  static bool get isListening => _speech.isListening;
  static bool get hasThaiLocale => _hasThaiLocale;
  static String get currentLocaleId => _thaiLocaleId;
  static List<String> get availableLocaleIds => _allLocaleIds;

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
      _allLocaleIds = locales.map((l) => l.localeId).toList();
      debugPrint('STT available locales (${locales.length}): ${_allLocaleIds.take(20).toList()}');

      // หา Thai locale — ลองหลายรูปแบบ
      // ลำดับ: th_TH > th-TH > th > อะไรก็ได้ที่ขึ้นต้นด้วย th
      final preferredIds = ['th_TH', 'th-TH', 'th'];

      for (final preferred in preferredIds) {
        for (final locale in locales) {
          if (locale.localeId.toLowerCase() == preferred.toLowerCase()) {
            _thaiLocaleId = locale.localeId;
            _hasThaiLocale = true;
            debugPrint('STT found Thai locale (exact): $_thaiLocaleId (${locale.name})');
            return;
          }
        }
      }

      // fallback: หาอะไรก็ได้ที่ขึ้นต้นด้วย th
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith('th')) {
          _thaiLocaleId = locale.localeId;
          _hasThaiLocale = true;
          debugPrint('STT found Thai locale (prefix): $_thaiLocaleId (${locale.name})');
          return;
        }
      }

      // ไม่เจอ Thai locale เลย
      _hasThaiLocale = false;
      debugPrint('STT WARNING: No Thai locale found! Device locales: $_allLocaleIds');
    } catch (e) {
      debugPrint('STT findThaiLocale error: $e');
      _hasThaiLocale = false;
    }
  }

  /// เรียก init ใหม่เพื่อ refresh locale list (หลังผู้ใช้ดาวน์โหลดภาษา)
  static Future<void> refreshLocales() async {
    if (_isAvailable) {
      await _findThaiLocale();
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
      debugPrint('STT startListening with locale: $_thaiLocaleId (hasThai=$_hasThaiLocale)');
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
