// tts_web.dart — Web implementation: เล่นเสียงจาก backend /tts endpoint
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';

String _baseUrl = '';
void Function()? _onStart;
void Function()? _onComplete;
void Function(String)? _onError;
html.AudioElement? _audio;

Future<void> init({
  required String baseUrl,
  required void Function() onStart,
  required void Function() onComplete,
  required void Function(String) onError,
}) async {
  _baseUrl = baseUrl;
  _onStart = onStart;
  _onComplete = onComplete;
  _onError = onError;
}

Future<void> speak(String text) async {
  // หยุดเสียงเก่าก่อน
  await stop();

  final encoded = Uri.encodeComponent(text);
  final url = '$_baseUrl/tts?text=$encoded';

  _audio = html.AudioElement(url);
  _audio!.volume = 1.0;

  final completer = Completer<void>();

  _audio!.onPlay.listen((_) {
    _onStart?.call();
  });

  _audio!.onEnded.listen((_) {
    _onComplete?.call();
    if (!completer.isCompleted) completer.complete();
  });

  _audio!.onError.listen((_) {
    _onError?.call('Audio playback error');
    if (!completer.isCompleted) completer.complete();
  });

  try {
    await _audio!.play();
    await completer.future;
  } catch (e) {
    _onError?.call(e.toString());
  }
}

Future<void> stop() async {
  if (_audio != null) {
    _audio!.pause();
    _audio!.currentTime = 0;
    _audio = null;
  }
}
