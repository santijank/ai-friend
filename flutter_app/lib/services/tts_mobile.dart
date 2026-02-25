// tts_mobile.dart — Mobile implementation: เล่นเสียงจาก backend /tts endpoint
// ใช้ audioplayers เล่น MP3 จาก backend Google TTS (คุณภาพดีเหมือน web)
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

String _baseUrl = '';
final AudioPlayer _player = AudioPlayer();
void Function()? _onStart;
void Function()? _onComplete;
void Function(String)? _onError;

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

  // Listen to player state changes
  _player.onPlayerStateChanged.listen((state) {
    if (state == PlayerState.playing) {
      _onStart?.call();
    } else if (state == PlayerState.completed) {
      _onComplete?.call();
    } else if (state == PlayerState.stopped) {
      _onComplete?.call();
    }
  });
}

Future<void> speak(String text) async {
  await stop();

  final encoded = Uri.encodeComponent(text);
  final url = '$_baseUrl/tts?text=$encoded';

  try {
    _onStart?.call();
    await _player.play(UrlSource(url));
  } catch (e) {
    _onError?.call(e.toString());
  }
}

Future<void> stop() async {
  try {
    await _player.stop();
  } catch (_) {}
}
