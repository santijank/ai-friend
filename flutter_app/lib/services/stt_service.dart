/// stt_service.dart — Speech-to-Text (พูดใส่แอป)
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttService {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _isAvailable = false;

  static bool get isAvailable => _isAvailable;
  static bool get isListening => _speech.isListening;

  static Future<bool> init() async {
    _isAvailable = await _speech.initialize(
      onError: (error) => debugPrint('STT Error: ${error.errorMsg}'),
      onStatus: (status) => debugPrint('STT Status: $status'),
    );
    debugPrint('STT init: available=$_isAvailable');
    return _isAvailable;
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
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords);
          if (result.finalResult && onDone != null) {
            onDone();
          }
        },
        localeId: 'th_TH',
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
