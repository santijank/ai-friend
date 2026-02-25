/// stt_service.dart — Speech-to-Text (พูดใส่แอป)
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttService {
  static final stt.SpeechToText _speech = stt.SpeechToText();
  static bool _isAvailable = false;

  static bool get isAvailable => _isAvailable;
  static bool get isListening => _speech.isListening;

  static Future<bool> init() async {
    _isAvailable = await _speech.initialize(
      onError: (error) => print('STT Error: $error'),
    );
    return _isAvailable;
  }

  static Future<void> startListening({
    required Function(String text) onResult,
    Function()? onDone,
  }) async {
    if (!_isAvailable) return;

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
    );
  }

  static Future<void> stopListening() async {
    await _speech.stop();
  }
}
