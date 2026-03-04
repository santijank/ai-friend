/// stt_service.dart — Speech-to-Text ผ่าน speech_to_text package
/// ฟังเสียงแบบ inline ไม่แสดง Google popup — เหมาะกับ J.A.R.V.I.S. mode
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttService {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _initialized = false;
  static bool _isAvailable = false;

  static bool get isAvailable => _isAvailable;
  static bool get isListening => _speech.isListening;

  /// Init speech engine (เรียกครั้งเดียวตอนเปิดแอป)
  static Future<bool> init() async {
    try {
      _isAvailable = await _speech.initialize(
        onError: (error) {
          debugPrint('STT error: ${error.errorMsg}');
        },
        onStatus: (status) {
          debugPrint('STT status: $status');
        },
      );
      _initialized = true;
      debugPrint('STT init: available=$_isAvailable');
      return _isAvailable;
    } catch (e) {
      debugPrint('STT init error: $e');
      _isAvailable = false;
      return false;
    }
  }

  /// ฟังเสียงแบบ inline (ไม่มี popup)
  /// [onResult] — เรียกทุกครั้งที่รู้จำได้ข้อความ (partial + final)
  /// [onDone] — เรียกเมื่อหยุดฟัง
  /// [onError] — เรียกเมื่อเกิดข้อผิดพลาด
  static Future<void> startListening({
    required Function(String text) onResult,
    Function()? onDone,
    Function(String error)? onError,
    Duration? listenFor,
    String language = 'th-TH',
  }) async {
    // Re-init ถ้ายังไม่ได้ init หรือ engine หลุด
    if (!_initialized || !_isAvailable) {
      await init();
    }
    if (!_isAvailable) {
      onError?.call('Speech recognition not available');
      return;
    }

    // หยุดฟังก่อน (กัน conflict)
    if (_speech.isListening) {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    try {
      await _speech.listen(
        onResult: (result) {
          final text = result.recognizedWords;
          debugPrint('STT result: "$text" (final=${result.finalResult})');
          onResult(text);
          // เมื่อได้ผลลัพธ์สุดท้าย → บอก done
          if (result.finalResult) {
            onDone?.call();
          }
        },
        listenFor: listenFor ?? const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        localeId: language,
        cancelOnError: false,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('STT listen error: $e');
      onError?.call(e.toString());
    }
  }

  /// หยุดฟัง
  static Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  /// One-shot: ฟังครั้งเดียวแล้ว return ข้อความ (สำหรับ VoiceButton กดสั้น)
  static Future<String> recognizeSpeech({
    String language = 'th-TH',
    String prompt = 'พูดภาษาไทยได้เลย',
  }) async {
    if (!_initialized || !_isAvailable) {
      await init();
    }
    if (!_isAvailable) return '';

    String result = '';
    bool done = false;

    await startListening(
      language: language,
      onResult: (text) {
        result = text;
      },
      onDone: () {
        done = true;
      },
      onError: (_) {
        done = true;
      },
      listenFor: const Duration(seconds: 10),
    );

    // รอจนกว่าจะฟังเสร็จ (max 12 วินาที)
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (!done && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
      // ถ้า speech engine หยุดเอง → done
      if (!_speech.isListening) {
        done = true;
      }
    }

    // หยุดฟังถ้ายังฟังอยู่
    await stopListening();

    debugPrint('STT recognizeSpeech result: "$result"');
    return result;
  }
}
